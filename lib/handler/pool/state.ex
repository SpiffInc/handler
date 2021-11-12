defmodule Handler.Pool.State do
  @moduledoc false
  alias __MODULE__
  alias Handler.Pool.{InsufficientMemory, NoWorkersAvailable}

  defstruct running_workers: 0,
            bytes_committed: 0,
            workers: %{},
            pool: nil

  @type t :: %State{
          running_workers: non_neg_integer(),
          bytes_committed: non_neg_integer(),
          workers: %{
            reference() => {
              bytes_committed :: non_neg_integer(),
              GenServer.from()
            }
          },
          pool: %Handler.Pool{}
        }

  @type exception :: %InsufficientMemory{} | %NoWorkersAvailable{}

  @spec cleanup_commitments(t(), reference()) :: t()
  def cleanup_commitments(state, ref) do
    %State{workers: workers} = state

    case Map.get(workers, ref) do
      {bytes_requested, _from} ->
        workers = Map.delete(workers, ref)

        %{
          state
          | workers: workers,
            running_workers: state.running_workers - 1,
            bytes_committed: state.bytes_committed - bytes_requested
        }
      nil ->
        raise "Received an un-tracked reference"
    end
  end

  @doc """
  Try to start a job on a worker from the pool. If there is not enough
  memory or all the workers are busy, return `{:reject, t:exception()}`.
  """
  @spec start_worker(t(), fun, keyword(), GenServer.from()) :: {:ok, t()} | {:reject, exception()}
  def start_worker(state, fun, opts, from) do
    bytes_requested = Handler.max_heap_bytes(opts)

    cond do
      state.running_workers >= state.pool.max_workers ->
        {:reject, NoWorkersAvailable.exception(message: "No workers available")}

      state.bytes_committed + bytes_requested > state.pool.max_memory_bytes ->
        {:reject, InsufficientMemory.exception(message: "Not enough memory available")}

      true ->
        ref = kickoff_new_task(fun, opts)
        {:ok, update_state(state, ref, bytes_requested, from)}
    end
  end

  @spec send_response(t(), reference(), term) :: t()
  def send_response(state, ref, result) do
    %State{workers: workers} = state

    case Map.get(workers, ref) do
      {_bytes_requested, from} ->
        GenServer.reply(from, result)
        state

      nil ->
        raise "Received an un-tracked reference"
    end
  end

  defp kickoff_new_task(fun, opts) do
    %Task{ref: ref} =
      Task.async(fn ->
        Handler.run(fun, opts)
      end)

    ref
  end

  defp update_state(%State{workers: workers} = state, ref, bytes_requested, from) do
    workers = Map.put(workers, ref, {bytes_requested, from})

    %{
      state
      | workers: workers,
        running_workers: state.running_workers + 1,
        bytes_committed: state.bytes_committed + bytes_requested
    }
  end
end
