defmodule Handler.PoolTest do
  use ExUnit.Case, async: true
  alias Handler.Pool

  test "work can be run in the pool" do
    server_args = [worker_module: GenGenServer, size: 0, max_overflow: 25]
    worker_args = []
    {:ok, pid} = :poolboy.start_link(server_args, worker_args)
    fun = fn -> {:ok, self()} end
    assert {:ok, worker_pid} = :poolboy.transaction(pid, fn worker -> GenServer.call(worker, fun, :infinity) end, 250)
    assert is_pid(worker_pid)
    assert worker_pid != self()
  end

  test "a basic pool" do
    config = %Pool{
      max_workers: 10,
      max_memory_bytes: 1024 * 1024
    }
    {:ok, pool} = Pool.start_link(config)
    fun = fn -> {:ok, self()} end
    opts = [max_memory_bytes: 10 * 1024, max_ms: 100, max_wait_ms: 100]
    assert {:ok, worker_pid} = Pool.attempt_work(pool, fun, opts)
    assert is_pid(worker_pid)
    assert worker_pid != self()
  end
end
