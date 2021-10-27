# This is a generic GenServer (ie GenGenServer 🤣)
# This module is part of the implementation of the Handler.Pool functionality
# and it should be considered an implementation detail which can change at any
# time.
# For now we are using poolboy and this module is specified as the worker_module
# so we can pass arbitrary functions to be executed in the pool.

defmodule Handler.Pool.Worker do
  @moduledoc false

  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  def attempt_work(worker, pool, fun, opts) do
    GenServer.call(worker, {pool, fun, opts}, :infinity)
  end

  def init(nil) do
    {:ok, nil}
  end

  def handle_call({_pool, fun, opts}, _from, state) do
    result = Handler.run(fun, opts)
    {:reply, result, state}
  end
end
