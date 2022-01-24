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
    assert {:ok, worker_pid} = Pool.run(pool, fun, opts)
    assert is_pid(worker_pid)
    assert worker_pid != self()
  end

  test "pools with registered names" do
    {:ok, _} =
      Pool.start_link(%Pool{
        max_workers: 10,
        max_memory_bytes: 1024 * 1024,
        name: :registered_name
      })

    assert {:ok, 100} =
             Pool.run(:registered_name, fn -> {:ok, 10 * 10} end, max_heap_bytes: 3 * 1024)
  end

  test "pools using Registry" do
    via_key = {:via, Registry, {Handler.Reg, :pool}}
    {:ok, _reg} = Registry.start_link(keys: :unique, name: Handler.Reg)

    {:ok, _} =
      Pool.start_link(%Pool{
        max_workers: 10,
        max_memory_bytes: 1024 * 1024,
        name: via_key
      })

    assert {:ok, 100} = Pool.run(via_key, fn -> {:ok, 10 * 10} end, max_heap_bytes: 3 * 1024)
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
        Pool.run(pool, fun, opts)
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

  test "jobs that run too long return a timeout" do
    config = %Pool{
      max_workers: 10,
      max_memory_bytes: 1024 * 1024
    }

    {:ok, pool} = Pool.start_link(config)

    fun = fn -> :timer.sleep(100) end
    opts = [max_heap_bytes: 10 * 1024, max_ms: 50]

    assert {:error, %Handler.Timeout{}} = Pool.run(pool, fun, opts)
  end

  test "pools that are too busy return NoWorkersAvailable" do
    config = %Pool{
      max_workers: 0,
      max_memory_bytes: 1024 * 1024
    }

    {:ok, pool} = Pool.start_link(config)
    opts = [max_heap_bytes: 10 * 1024, max_ms: 100]

    assert {:reject, %Pool.NoWorkersAvailable{} = exception} =
             Pool.run(pool, fn -> "ohai" end, opts)

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
          Pool.run(pool, fun, opts)
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
    assert {:reject, exception} = Pool.run(pool, fn -> true end, opts)
    assert %Handler.Pool.InsufficientMemory{} = exception
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
          Pool.run(pool, fun, opts)
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

  test "kills a job by its given task_id" do
    task_id = "task_1234"

    config = %Pool{
      max_workers: 5,
      max_memory_bytes: 1024 * 1024
    }

    {:ok, pool} = Pool.start_link(config)

    fun = fn ->
      :timer.sleep(60_000)
      {:ok, self()}
    end

    opts = [max_heap_bytes: 10 * 1024, max_ms: 1_000, task_id: task_id]

    Task.async(fn -> Pool.run(pool, fun, opts) end)

    # ensure pool is done initilizing worker
    :sys.get_state(pool)

    assert {:ok, _ref} = Pool.kill(pool, task_id)

    assert {:reject, "No task with given task_id in state"} = Pool.kill(pool, task_id)
  end

  describe "composed pools" do
    test "jobs successfully delegate to the root pool" do
      {_root, composed} = setup_composed_pools()
      opts = [max_heap_bytes: 5 * 1024, max_ms: 20]
      assert {:ok, 100} = Pool.run(composed, fn -> {:ok, 10 * 10} end, opts)
    end

    test "resources are marked free from both pools" do
      {_root, composed} = setup_composed_pools()
      opts = [max_heap_bytes: 5 * 1024, max_ms: 20]

      Enum.each(1..100, fn _ ->
        assert {:ok, 100} = Pool.run(composed, fn -> {:ok, 10 * 10} end, opts)
      end)
    end

    test "memory limits of composed pool are enforced" do
      {_root, composed} = setup_composed_pools()

      opts = [max_ms: 30, max_heap_bytes: 11 * 1024]
      {:reject, exception} = Pool.run(composed, fn -> :ok end, opts)
      assert %Handler.Pool.InsufficientMemory{} = exception
    end

    test "worker limits of composed pool are enforced" do
      {_root, composed} = setup_composed_pools()

      opts = [max_ms: 30, max_heap_bytes: 3 * 1024]
      assert {:ok, _ref} = Pool.async(composed, fn -> :timer.sleep(20) end, opts)
      assert {:reject, exception} = Pool.run(composed, fn -> 10 * 10 end, opts)
      assert %Handler.Pool.NoWorkersAvailable{} = exception
    end

    test "memory limits of root pool are enforced" do
      {root, composed} = setup_composed_pools()

      opts = [max_ms: 200, max_heap_bytes: 12 * 1024]
      {:ok, _ref} = Pool.async(root, fn -> :timer.sleep(100) end, opts)

      opts = [max_ms: 200, max_heap_bytes: 9 * 1024]
      {:reject, exception} = Pool.run(composed, fn -> :ok end, opts)
      assert %Handler.Pool.InsufficientMemory{} = exception
    end

    test "worker limits of root pool are enforced" do
      {root, composed} = setup_composed_pools()
      opts = [max_ms: 200, max_heap_bytes: 5 * 1024]
      {:ok, _ref} = Pool.async(root, fn -> :timer.sleep(100) end, opts)
      {:ok, _ref} = Pool.async(root, fn -> :timer.sleep(100) end, opts)

      opts = [max_ms: 30, max_heap_bytes: 3 * 1024]
      assert {:reject, exception} = Pool.run(composed, fn -> 10 * 10 end, opts)
      assert %Handler.Pool.NoWorkersAvailable{} = exception
    end

    test "killing workers in a composed pools" do
      task_id = "task_1234"
      {root, composed} = setup_composed_pools()

      opts = [max_ms: 200, max_heap_bytes: 2 * 1024, task_id: task_id]
      {:ok, _ref} = Pool.async(composed, fn -> :timer.sleep(60_000) end, opts)

      {:ok, _ref} = Pool.kill(composed, task_id)
      {:reject, "No task with given task_id in state"} = Pool.kill(composed, task_id)
    end
  end

  defp setup_composed_pools do
    {:ok, root} =
      Pool.start_link(%Pool{
        max_workers: 2,
        max_memory_bytes: 20 * 1024
      })

    {:ok, customer1} =
      Pool.start_link(%Pool{
        max_workers: 1,
        max_memory_bytes: 10 * 1024,
        delegate_to: root
      })

    {root, customer1}
  end
end
