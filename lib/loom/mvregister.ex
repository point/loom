defmodule Loom.MVRegister do
  @moduledoc """
  A causally consistent multi-value register.

  A bit more causally rigorous than LWWRegister, MVRegister will replace
  observed values when they are set, but concurrent additions will co-occur,
  and a list will be returned for the value.

  This is good if you have some reasonable way of figuring out how to resolve
  this further down your app keychain (including user resolution), but you can't
  make it generic enough to work as a CRDT.
  """

  alias __MODULE__, as: Reg
  alias Loom.AWORSet, as: Set
  @type actor :: term
  @type t :: %Reg{
    set: Set.t
  }

  defstruct set: Set.new()

  @doc """
  Returns a new MVRegister CRDT.

  `nil` is a new CRDT's identity value, and by default the system time in
  microseconds is used as the clock value.

      iex> Loom.MVRegister.new |> Loom.MVRegister.value
      nil

  """
  @spec new :: t
  def new, do: %Reg{}

  @doc """
  Sets a value, erasing any current values.

      iex> alias Loom.MVRegister, as: Reg
      iex> Reg.new
      ...> |> Reg.set(:a, "test")
      ...> |> Reg.set(:a, "test2")
      ...> |> Reg.value
      "test2"

  """
  @spec set(t, actor, term) :: {t, t}
  @spec set({t,t}, actor, term) :: {t, t}
  def set(%Reg{}=reg, actor, value), do: set({reg, Reg.new}, actor, value)
  def set({%Reg{set: set}, %Reg{set: delta_set}}, actor, value) do
    {new_set, new_delta_set} = {set, delta_set}
                               |> Set.empty()
                               |> Set.add(actor, value)
    {%Reg{set: new_set}, %Reg{set: new_delta_set}}
  end

  @doc """
  Joins 2 MVRegisters

      iex> alias Loom.MVRegister, as: Reg
      iex> {a, _} = Reg.new |> Reg.set(:a, "test") |> Reg.set(:a, "test2")
      iex> {b, _} = Reg.new |> Reg.set(:b, "take over")
      iex> Reg.join(a, b) |> Reg.value
      ["test2", "take over"]
  """
  @spec join(t, t) :: t
  def join(%Reg{set: set_a}, %Reg{set: set_b}) do
    %Reg{set: Set.join(set_a, set_b)}
  end

  @doc """
  Returns the natural value of the register. If there is nothing, it's nil. If
  it's one thing, it's that value (this is the normal case). If it's more than
  one thing, all values are returned in a list.
  """
  @spec value(t) :: [term] | term | nil
  @spec value({t,t}) :: [term] | term | nil
  def value({reg, _}), do: value(reg)
  def value(%Reg{set: set}) do
    case Set.value(set) do
      [] -> nil
      [singleton] -> singleton
      mv -> mv
    end
  end

end
