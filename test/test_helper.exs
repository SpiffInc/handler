ExUnit.start()

defmodule GenGenServer do
  @moduledoc """
  This is a generic GenServer (ie GenGenServer 🤣)

  This module is started as a worker in pool (see application.ex) and makes it easy to run a particular function
  like a dataview or a CE.Updater function on a node that is managing the state for a given customer.
  """

  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(nil) do
    {:ok, nil}
  end

  def handle_call(fun, _from, state) do
    {:reply, fun.(), state}
  end
end
