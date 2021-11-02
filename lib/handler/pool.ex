defmodule Handler.Pool do
  defstruct max_workers: 100,
            max_memory_bytes: 10 * 1024 * 1024 * 1024,
            name: nil

  alias __MODULE__
  alias Handler.Pool.State
  use GenServer

  def start_link(%Pool{} = config) do
    GenServer.start_link(Pool, config)
  end

  def attempt_work(pool, fun, opts) do
    GenServer.call(pool, {:attempt, fun, opts})
  end

  def init(%Pool{} = pool) do
    register_name(pool)
    state = %State{pool: pool}
    {:ok, state}
  end

  def handle_call({:attempt, fun, opts}, from, state) do
    case State.start_worker(state, fun, opts, from) do
      {:ok, state} ->
        {:noreply, state}

      {:reject, exception} ->
        {:reply, {:reject, exception}, state}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    state = State.result_received(state, ref, result)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, :normal}, state)
      when is_reference(ref) and is_pid(pid) do
    {:noreply, state}
  end

  def handle_info(other, state) do
    require Logger
    Logger.error("#{__MODULE__} received unexpected message #{inspect(other)}")
    {:noreply, state}
  end

  defp register_name(%Pool{name: name}) when is_atom(name) do
    if name == nil do
      true
    else
      Process.register(self(), name)
    end
  end
end
