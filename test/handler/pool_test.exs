defmodule Handler.PoolTest do
  use ExUnit.Case, async: true
  alias Handler.Pool

  test "a basic pool" do
    config = %Pool{
      max_workers: 10,
      max_memory_bytes: 1024 * 1024
    }

    {:ok, pool} = Pool.start_link(config)
    fun = fn -> {:ok, self()} end
    opts = [max_heap_bytes: 10 * 1024, max_ms: 100]
    assert {:ok, worker_pid} = Pool.attempt_work(pool, fun, opts)
    assert is_pid(worker_pid)
    assert worker_pid != self()
  end

  test "executing multiple parallel jobs in a pool" do
    config = %Pool{
      max_workers: 20,
      max_memory_bytes: 1024 * 1024
    }

    {:ok, pool} = Pool.start_link(config)

    fun = fn ->
      :timer.sleep(10)
      {:ok, self()}
    end

    opts = [max_heap_bytes: 10 * 1024, max_ms: 20]

    Enum.map(1..20, fn _i ->
      Task.async(fn ->
        Pool.attempt_work(pool, fun, opts)
      end)
    end)
    |> Enum.map(fn task ->
      Task.await(task)
    end)
    |> Enum.each(fn result ->
      assert {:ok, worker_pid} = result
      assert is_pid(worker_pid)
      assert worker_pid != self()
    end)
  end

  test "pools that are too busy return NoWorkersAvailable" do
    config = %Pool{
      max_workers: 0,
      max_memory_bytes: 1024 * 1024
    }

    {:ok, pool} = Pool.start_link(config)
    opts = [max_heap_bytes: 10 * 1024, max_ms: 100]

    assert {:reject, %Pool.NoWorkersAvailable{} = exception} =
             Pool.attempt_work(pool, fn -> "ohai" end, opts)

    assert exception.message == "No workers available"
  end

  test "NoWorkersAvailable come back in parallel" do
    config = %Pool{
      max_workers: 5,
      max_memory_bytes: 1024 * 1024
    }

    {:ok, pool} = Pool.start_link(config)

    fun = fn ->
      :timer.sleep(10)
      {:ok, self()}
    end

    opts = [max_heap_bytes: 10 * 1024, max_ms: 20]

    results =
      Enum.map(1..10_000, fn _i ->
        Task.async(fn ->
          Pool.attempt_work(pool, fun, opts)
        end)
      end)
      |> Enum.map(fn task ->
        Task.await(task)
      end)

    # a few jobs should succeed, but most will see the pool busy
    groups = Enum.group_by(results, fn result -> elem(result, 0) end)
    assert Map.has_key?(groups, :ok)
    assert Map.has_key?(groups, :reject)
    assert Enum.count(groups.ok) >= 5
    assert Enum.count(groups.reject) >= 9000

    assert Enum.all?(groups.reject, fn
             {:reject, %Handler.Pool.NoWorkersAvailable{}} -> true
             _other -> false
           end)
  end

  test "InsufficientMemory is returned if a job is requesting too much memory" do
    config = %Pool{
      max_workers: 5,
      max_memory_bytes: 10 * 1024
    }

    {:ok, pool} = Pool.start_link(config)
    opts = [max_heap_bytes: 11 * 1024, max_ms: 20]

    assert {:reject, %Handler.Pool.InsufficientMemory{}} =
             Pool.attempt_work(pool, fn -> true end, opts)
  end

  test "InsufficientMemory is returned if a job is requesting too much in combination with other jobs" do
    config = %Pool{
      max_workers: 20,
      max_memory_bytes: 20 * 1024
    }

    {:ok, pool} = Pool.start_link(config)
    opts = [max_heap_bytes: 5 * 1024, max_ms: 20]

    fun = fn ->
      :timer.sleep(10)
      {:ok, true}
    end

    results =
      Enum.map(1..200, fn _i ->
        Task.async(fn ->
          Pool.attempt_work(pool, fun, opts)
        end)
      end)
      |> Enum.map(fn task ->
        Task.await(task)
      end)

    groups = Enum.group_by(results, fn result -> elem(result, 0) end)
    assert Map.has_key?(groups, :ok)
    assert Map.has_key?(groups, :reject)
    assert Enum.count(groups.ok) >= 4
    assert Enum.count(groups.reject) >= 100

    assert Enum.all?(groups.reject, fn
             {:reject, %Handler.Pool.InsufficientMemory{}} -> true
             _other -> false
           end)
  end
end
