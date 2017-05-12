defmodule Loom.Dots do
  @moduledoc """
  A generic structure for associating values with dots (version vector pairs).

  They reflect work from ORSWOT (optimized observed-remove set without tombstones).
  """
  alias Loom.Dots

  @type actor :: term
  @type clock :: pos_integer
  @type dot :: {actor, clock}
  @type value :: term

  @opaque t :: %Dots{
    dots: %{dot => value},
    ctx: %{actor => clock},
    cloud: [dot],
    initial_counter: integer
  }

  defstruct dots: %{}, # A map of dots (version-vector pairs) to values
            ctx: %{},  # Current counter values for actors used in the dots
            cloud: [],  # A set of dots that we've seen but haven't been merged.
            initial_counter: 0

  @doc """
  Create a new Dots manager
  """
  @spec new() :: t
  def new, do: %Dots{}
  def new(initial_counter: initial_counter), do: %Dots{initial_counter: initial_counter}

  @doc """
  Checks for a dot's membership
  """
  @spec dotin(t, dot) :: boolean
  def dotin(%Dots{ctx: ctx, cloud: cloud}, {actor,clock}=dot) do
    # If this exists in the dot, and is greater than the value *or* is in the cloud
    (ctx[actor]||0) >= clock or Enum.any?(cloud, &(&1==dot))
    #Enum.any?(cloud, &(&1==dot))
  end

  @doc """
  Return the dots
  """
  @spec dots(t) :: %{dot => value}
  def dots(%Dots{dots: s}), do: s
  # def context(%Dots{ctx: c}), do: c
  # def cloud(%Dots{cloud: c}), do: c

  @doc """
  Compact the dots.

  This merges any newly-contiguously-joined deltas. This is usually called
  automatically as needed.
  """
  @spec compact(t) :: t
  def compact(dots), do: do_compact(dots)

  @doc """
  Joins any 2 dots together.

  Automatically compacts any contiguous dots.
  """
  @spec join(t, t) :: t
  def join(dots1, dots2), do: do_join(dots1, dots2)

  @doc """
  Adds and associates a value with a new dot for an actor.
  """
  @spec add({t, t}, actor, value) :: {t, t}
  def add({%Dots{dots: d, ctx: ctx, initial_counter: initial_counter}=dots, delta_dots}, actor, value) do
    clock = max(Dict.get(ctx, actor, 0), initial_counter) + 1 # What's the value of our clock?
    dot = {actor, clock}
    new_dots = %Dots{dots|
      dots: Dict.put(d, dot, value), # Add the value to the dot values
      ctx: Dict.put(ctx, actor, clock), # Add the actor/clock to the context
      initial_counter: initial_counter
    }
    # A new changeset
    new_delta = %Dots{dots: Dict.put(%{}, dot, value), cloud: [dot]}
              |> join(delta_dots)
              |> compact
    {new_dots, new_delta}
  end

  def init({%Dots{dots: d, ctx: ctx, initial_counter: initial_counter}=dots, delta_dots}, actor, value) do
    clock =Dict.get(ctx, actor, 0) + 1 # What's the value of our clock?
    dot = {actor, clock}
    new_dots = %Dots{dots|
      dots: Dict.put(d, dot, value), # Add the value to the dot values
      ctx: Dict.put(ctx, actor, clock), # Add the actor/clock to the context
      initial_counter: initial_counter
    }
    # A new changeset
    new_delta = delta_dots
    {new_dots, new_delta}
  end

  @doc """
  Removes a value from the set
  """
  @spec remove({t, t}, value) :: {t, t}
  #def remove({%Dots{dots: d, initial_counter: initial_counter}=dots, delta_dots}, pred) when is_function(pred) do
    #{new_d, delta_cloud} = Enum.reduce(d, {%{}, []}, fn ({dot, v}, {d, cloud}) ->
      #if pred.(v) do
        ## Don't reinsert dot/value, add dot to cloud for causation
        #{d, [dot|cloud]}
      #else
        ## Reinsert, don't worry about causation dot
        #{Dict.put(d, dot, v), cloud}
      #end
    #end)
    #new_dots = %Dots{dots|dots: new_d}
    #new_delta = %Dots{cloud: delta_cloud, initial_counter: initial_counter}
             #|> join(delta_dots)
             #|> compact
    #{new_dots, new_delta}
  #end
  def remove({%Dots{dots: d, initial_counter: initial_counter}=dots, 
    %Dots{dots: delta_d}=delta_dots}, pred) when is_function(pred) do
    {new_d, dots_cloud} = Enum.reduce(d, {%{}, []}, fn ({dot, v}, {d, cloud}) ->
      if pred.(v) do
        # Don't reinsert dot/value, add dot to cloud for causation
        {d, [dot|cloud]}
      else
        # Reinsert, don't worry about causation dot
        {Dict.put(d, dot, v), cloud}
      end
    end)
    {new_delta_d, delta_dots_cloud} = Enum.reduce(delta_d, {%{}, []}, fn ({dot, v}, {d, cloud}) ->
      if pred.(v) do
        # Don't reinsert dot/value, add dot to cloud for causation
        {d, [dot|cloud]}
      else
        # Reinsert, don't worry about causation dot
        {Dict.put(d, dot, v), cloud}
      end
    end)
    new_dots = %Dots{dots|dots: new_d, cloud: dots_cloud, initial_counter: initial_counter} |> compact
    new_delta = %Dots{delta_dots|dots: new_delta_d, cloud: dots_cloud ++ delta_dots_cloud, initial_counter: initial_counter} |> compact
    {new_dots, new_delta}
  end
  def remove(dots, value), do: remove(dots, &(&1==value))

  @doc """
  Removes all values from the set, but preserves the context.
  """
  def empty({%Dots{cloud: cloud, initial_counter: initial_counter}=dots, delta_dots}) do
    {%Dots{dots|dots: %{}}, join(%Dots{cloud: cloud, initial_counter: initial_counter}, delta_dots)}
  end

  @doc """
  Removes all values from the set
  """
  @spec remove({t, t}) :: {t, t}
  def remove({%Dots{dots: d, initial_counter: initial_counter}=dots, %Dots{}=delta}) do
    new_dots = %Dots{dots|dots: %{}}
    new_delta = join(delta, %Dots{cloud: Dict.keys(d), initial_counter: initial_counter})
    {new_dots, new_delta}
  end

  defp do_compact(%Dots{ctx: ctx, cloud: c, initial_counter: initial_counter}=dots) do
    {new_ctx, new_cloud} = compact_reduce(Enum.sort(c), ctx, initial_counter + 1, [])
    %Dots{dots|ctx: new_ctx, cloud: new_cloud}
  end

  @spec compact_reduce([dot], %{actor => clock}, integer, [dot]) :: {%{actor => clock}, [dot]}
  defp compact_reduce([], ctx, inc_initial_counter, cloud_acc) do
    {ctx, Enum.reverse(cloud_acc)}
  end
  defp compact_reduce([{actor, clock}=dot|cloud], ctx, inc_initial_counter, cloud_acc) do
    case {ctx[actor], clock} do
      {nil, ^inc_initial_counter} ->
        compact_reduce(cloud, Dict.put(ctx, actor, clock), inc_initial_counter, cloud_acc)
      {nil, clock} when clock >= inc_initial_counter ->
        # We can merge nil with 1 in the cloud
        compact_reduce(cloud, Dict.put(ctx, actor, clock), inc_initial_counter, cloud_acc)
      {nil, _} ->
        # Can't do anything with this
        compact_reduce(cloud, ctx, inc_initial_counter, [dot|cloud_acc])
      {ctx_clock, _} when ctx_clock + 1 == clock ->
        # Add to context, delete from cloud
        compact_reduce(cloud, Dict.put(ctx, actor, clock), inc_initial_counter, cloud_acc)
      {ctx_clock, _} when ctx_clock >= clock -> # Dominates
        # Delete from cloud by not accumulating.
        compact_reduce(cloud, ctx, inc_initial_counter, cloud_acc)
      {_, _} ->
        # Can't do anything with this.
        compact_reduce(cloud, ctx, inc_initial_counter, [dot|cloud_acc])
    end
  end

  #defp do_join(%Dots{dots: d1, ctx: ctx1, cloud: c1, initial_counter: initial_counter}=dots1, %Dots{dots: d2, ctx: ctx2, cloud: c2}=dots2) do
    #new_dots = do_join_dots(Enum.sort(d1), Enum.sort(d2), {dots1, dots2}, [])
    #new_ctx = Dict.merge(ctx1, ctx2, fn (_, a, b) -> max(a, b) end)
    #new_cloud = Enum.uniq(c1 ++ c2)
    #compact(%Dots{dots: new_dots, ctx: new_ctx, cloud: new_cloud, initial_counter: initial_counter})
  #end
  defp do_join(%Dots{dots: d1, ctx: ctx1, cloud: c1, initial_counter: initial_counter}=dots1, 
   %Dots{dots: d2, ctx: ctx2, cloud: c2}=dots2) do 

    keys1 = d1 |> Map.keys |> MapSet.new
    keys2 = d2 |> Map.keys |> MapSet.new
    keys1_with_ctx = for e <- Map.to_list(ctx1), into: keys1, do: e
    keys2_with_ctx = for e <- Map.to_list(ctx2), into: keys2, do: e
    keys_intersection = MapSet.intersection(keys1, keys2)
    keys1_ahead_ctx2 = keys1 |> Enum.filter(fn({actor, clock})-> clock > Map.get(ctx2, actor, 0) end)
    keys2_ahead_ctx1 = keys2 |> Enum.filter(fn({actor, clock})-> clock > Map.get(ctx1, actor, 0) end)
    new_dots = %{} 
                |> Enum.into(Map.take(d1, keys_intersection))
                |> Enum.into(Map.take(d1, keys1_ahead_ctx2))
                |> Enum.into(Map.take(d2, keys2_ahead_ctx1))

    new_ctx = Dict.merge(ctx1, ctx2, fn (_, a, b) -> max(a, b) end)
    new_cloud = Enum.uniq(c1 ++ c2)
    compact(%Dots{dots: new_dots, ctx: new_ctx, cloud: new_cloud, initial_counter: initial_counter})
   end

  # This function requires the use of ORDERED lists.
  # If we run out of d2, also takes care of case when we run out of both same time.
  defp do_join_dots(d1, [], {_, dots2}, acc) do
    # Remove when the other knows about our dots in context/cloud, but isn't in
    # their dot values list (they observed a remove)
    new_d1 = Enum.reject(d1, fn ({dot, _}) -> dotin(dots2, dot) end)
    Enum.reverse(acc, new_d1) |> Enum.into %{}
  end
  # If we run out of d1
  defp do_join_dots([], d2, {dots1, _}, acc) do
    # Add dot when it is only at the other side. This happens when they've got
    # values that we do not.
    new_d1 = Enum.reject(d2, fn ({dot, _}) -> dotin(dots1, dot) end)
    Enum.reverse(acc, new_d1) |> Enum.into %{}
  end
  # Always advance d1 when dot1 < dot2
  defp do_join_dots([{dot1,value1}|d1], [{dot2,_}|_]=d2, {_, dots2}=dots, acc) when dot1 < dot2 do
    # Remove if they know about dot1 and they don't have it in their dots
    # Otherwise keep our dot
    acc = if dotin(dots2, dot1), do: acc, else: [{dot1,value1}|acc]
    do_join_dots(d1, d2, dots, acc)
  end
  # Always advance d2 when dot2 < dot1
  defp do_join_dots([{dot1,_}|_]=d1, [{dot2,value2}|d2], {dots1, _}=dots, acc) when dot2 < dot1 do
    # If we know about dot2, then we already either have its value or don't
    # If we don't know about dot2, then we should grab it.
    acc = if dotin(dots1, dot2), do: acc, else: [{dot2,value2}|acc]
    do_join_dots(d1, d2, dots, acc)
  end
  # If we both got the same dot, just add it into the accumulator and advance both
  defp do_join_dots([{dot,value1}|d1], [{dot,_}|d2], dots, acc) do
    do_join_dots(d1, d2, dots, [{dot, value1}|acc])
  end
end
