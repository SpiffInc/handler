defmodule Handler.Pool.State do
  @moduledoc false
  alias __MODULE__
  alias Handler.Pool.{NoMemoryAvailable, NoWorkersAvailable}

  defstruct running_workers: 0,
            total_bytes_promised: 0,
            workers: %{},
            pool: nil

  @type t :: %State{
          running_workers: non_neg_integer(),
          total_bytes_promised: non_neg_integer(),
          workers: %{
            reference() => {
              bytes_promised :: non_neg_integer(),
              GenServer.from()
            }
          },
          pool: %Handler.Pool{}
        }

  @type exception :: %NoMemoryAvailable{} | %NoWorkersAvailable{}

  @spec start_worker(t(), fun, keyword(), GenServer.from()) :: {:ok, t()} | {:reject, exception()}
  def start_worker(state, fun, opts, from) do
    bytes_requested = Handler.max_heap_bytes(opts)

    cond do
      state.running_workers >= state.pool.max_workers ->
        {:reject, NoWorkersAvailable.exception(message: "No workers available")}

      state.total_bytes_promised + bytes_requested > state.pool.max_memory_bytes ->
        {:reject, NoMemoryAvailable.exception(message: "Not enough memory available")}

      true ->
        ref = kickoff_new_task(fun, opts)
        {:ok, update_state(state, ref, bytes_requested, from)}
    end
  end

  @spec result_received(t(), reference(), term) :: t()
  def result_received(state, ref, result) do
    %State{workers: workers} = state

    case Map.get(workers, ref) do
      {bytes_requested, from} ->
        GenServer.reply(from, result)
        workers = Map.delete(workers, ref)

        %{
          state
          | workers: workers,
            running_workers: state.running_workers - 1,
            total_bytes_promised: state.total_bytes_promised - bytes_requested
        }

      nil ->
        raise "Got an unexpected result"
    end
  end

  defp kickoff_new_task(fun, opts) do
    %Task{ref: ref} =
      Task.async(fn ->
        Handler.run(fun, opts)
      end)

    ref
  end

  defp update_state(%__MODULE__{workers: workers} = state, ref, bytes_requested, from) do
    workers = Map.put(workers, ref, {bytes_requested, from})

    %{
      state
      | workers: workers,
        running_workers: state.running_workers + 1,
        total_bytes_promised: state.total_bytes_promised + bytes_requested
    }
  end
end
