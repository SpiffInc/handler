# This isn't really a benchmark, but I wasn't sure where to put it.
# This script sets up several different pools and then runs a battery
# of tests for kicking off, killing, and crashing a bunch of different jobs.
# Throughout that process is periodically checks to make sure that all
# of the pools have cleaned up their states correctly

alias Handler.Pool

Logger.configure(
  handle_otp_reports: false,
  handle_sasl_reports: false,
  level: :none
)

# A few helper modules
defmodule Balance do
  def list(config, _param) do
    Enum.shuffle(config)
  end
end

defmodule EmptyPoolChecker do
  def check(pools) do
    Enum.each(pools, fn(pool) ->
      state = :sys.get_state(pool)
      unless state.workers == %{} do
        raise "Workers Not Empty! #{pool}"
      end
      unless state.running_workers == 0 do
        raise "Running workers != 0 #{pool}"
      end
      unless state.bytes_committed == 0 do
        raise "Bytes committed != 0 #{pool}"
      end
    end)
  end
end

defmodule SendMeAnExitMessage do
  use GenServer

  def send_exit(exit_message) do
    GenServer.call(SendMeAKillMessage, {:send_exit, exit_message, self()})
  end

  def start_link do
    GenServer.start_link(SendMeAnExitMessage, nil, name: SendMeAnExitMessage)
  end

  def init(nil) do
    {:ok, nil}
  end

  def handle_call({:send_exit, message, pid}, state) do
    true = Process.exit(pid, message)
    {:reply, :ok, state}
  end
end

{:ok, _} = SendMeAnExitMessage.start_link()

{:ok, _} = Pool.start_link(%Pool{
  max_workers: 100,
  max_memory_bytes: 100 * 1024 * 1024,
  name: :root1
})
{:ok, _} = Pool.start_link(%Pool{
  max_workers: 100,
  max_memory_bytes: 100 * 1024 * 1024,
  name: :root2
})
{:ok, _} = Pool.start_link(%Pool{
  max_workers: 100,
  max_memory_bytes: 100 * 1024 * 1024,
  name: :child1,
  delegate_to: :root1
})
{:ok, _} = Pool.start_link(%Pool{
  max_workers: 100,
  max_memory_bytes: 100 * 1024 * 1024,
  name: :child2,
  delegate_to: :root2
})

{:ok, _} = Pool.start_link(%Pool{
  max_workers: 100,
  max_memory_bytes: 100 * 1024 * 1024,
  name: :dynamic1,
  delegate_fun: {Balance, :list, [:root1, :root2]}
})
{:ok, _} = Pool.start_link(%Pool{
  max_workers: 100,
  max_memory_bytes: 100 * 1024 * 1024,
  name: :dynamic2,
  delegate_fun: {Balance, :list, [:child1, :child2]}
})

all_pools = [:root1, :root2, :child1, :child2, :dynamic1, :dynamic2]

IO.puts "All pools started, there are now #{Process.list() |> Enum.count()} processes running\n\n"

Enum.each(all_pools, fn(pool) ->
  refs =
    Enum.map(1..100, fn(i) ->
      name = "task_#{i}"
      {:ok, ref} = Pool.async(pool, fn -> :timer.sleep(1000) end, [max_heap_bytes: 10 * 1024, max_ms: 2_000, task_name: name])
      ref
    end)

  IO.puts "Sent 100 jobs to #{pool}, there are now #{Process.list() |> Enum.count()} processes running"

  {:ok, 1} = Pool.kill(pool, "task_100")
  :timer.sleep(10) # the kill is not synchronous

  IO.puts "Killed task_100, there are now #{Process.list() |> Enum.count()} processes running"

  Enum.each(refs, & Pool.await(&1))

  IO.puts "Waited for 100 jobs, there are now #{Process.list() |> Enum.count()} processes running"

  EmptyPoolChecker.check(all_pools)
  IO.puts "\n"
end)

bad_functions = [
  fn -> :timer.sleep(100); 1 / 0 end,
  fn -> :timer.sleep(50); SendMeAnExitMessage.send_exit(:kill) end,
  fn -> :timer.sleep(75); SendMeAnExitMessage.send_exit(:user_cancelled) end,
  fn -> :timer.sleep(25); SendMeAnExitMessage.send_exit(:brutal_kill) end,
  fn -> :timer.sleep(150); apply(:bad_module, :bad_fun, [:bad_arg]) end,
  fn -> :timer.sleep(120); GenServer.call(:foobar, :bad_request) end,
]

Enum.each(1..10, fn(_) ->
  IO.puts("Running a batch of bad tasks")

  refs = Enum.map(1..100, fn(i) ->
    pool = Enum.shuffle(all_pools) |> hd()
    name = "task_#{i}"
    fun = Enum.shuffle(bad_functions) |> hd()
    {:ok, ref} = Pool.async(pool, fun, [max_heap_bytes: 1024 * 1024, max_ms: 2_000, task_name: name])
    ref
  end)

  IO.puts "Sent 100 jobs, there are now #{Process.list() |> Enum.count()} processes running"

  Enum.each(refs, & Pool.await(&1))

  IO.puts "Waited for 100 jobs, there are now #{Process.list() |> Enum.count()} processes running"

  EmptyPoolChecker.check(all_pools)
  IO.puts "\n"
end)
