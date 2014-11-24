defmodule Loom.AWORSet do
  alias Loom.AWORSet, as: Set
  alias Loom.Dots

  defstruct dots: %Dots{}

  def new, do: %Set{dots: Dots.new}

  def value(%Set{dots: d}) do
    (for {_, v} <- Dots.dots(d), do: v) |> Enum.uniq
  end

  def member?(%Set{dots: d}, value) do
    Dots.dots(d) |> Enum.any?(fn {_, v} -> v == value end)
  end

  def add(%Set{}=set, actor, value), do: add({set, Set.new}, actor, value)
  def add({%Set{dots: d}, %Set{dots: delta_dots}}, actor, value) do
    {new_dots, new_delta_dots} = {d, delta_dots}
                               |> Dots.remove(value)
                               |> Dots.add(actor, value)
    {%Set{dots: new_dots}, %Set{dots: new_delta_dots}}
  end

  def remove(%Set{}=set, value), do: remove({set, Set.new}, value)
  def remove({%Set{dots: d}=set, %Set{dots: delta_dots}}, value) do
    if member?(set, value) do
      {new_dots, new_delta_dots} = {d, delta_dots} |> Dots.remove(value)
      {%Set{dots: new_dots}, %Set{dots: new_delta_dots}}
    else
      raise Loom.PreconditionError, unobserved: value
    end
  end

  def empty(%Set{}=set), do: empty({set, Set.new})
  def empty({%Set{dots: d}=set, %Set{dots: delta_dots}}) do
    {new_dots, new_delta_dots} = Dots.remove({d, delta_dots})
    {%Set{dots: new_dots}, %Set{dots: new_delta_dots}}
  end

  def join(%Set{dots: d1}, %Set{dots: d2}) do
    %Set{dots: Dots.join(d1, d2)}
  end

end
