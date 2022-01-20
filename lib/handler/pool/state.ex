defmodule Handler.Pool.State do
  @moduledoc false
  alias __MODULE__
  alias Handler.Pool
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
              pid(),
              String.t()
            }
          },
          pool: %Handler.Pool{}
        }

  @type exception :: %InsufficientMemory{} | %NoWorkersAvailable{}

  @spec cleanup_commitments(t(), reference()) :: t()
  def cleanup_commitments(state, ref) do
    %State{workers: workers} = state

    case Map.get(workers, ref) do
      {bytes_requested, _from, _task_id} ->
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
  @spec start_worker(t(), fun, keyword(), pid()) ::
          {:ok, t(), reference()} | {:reject, exception()}
  def start_worker(state, fun, opts, pid) do
    bytes_requested = Handler.max_heap_bytes(opts)
    task_id = Keyword.get(opts, :task_id)

    with :ok <- check_committed_resources(state, bytes_requested),
         {:ok, ref} <- kickoff_new_task(state, fun, opts) do
      new_state = commit_resources(state, ref, bytes_requested, pid, task_id)
      {:ok, new_state, ref}
    end
  end

  def kill_worker(state, task_id) do
    worker =
      state
      |> Map.get(:workers)
      |> Map.values()
      |> Enum.find(&(elem(&1, 2) == task_id))

    case worker do
      {_bytes_requested, pid, _task_id} ->
        Process.exit(pid, :user_killed)

      _ ->
        {:reject, "No task with given task_id in state"}
    end
  end

  @spec send_response(t(), reference(), term) :: t()
  def send_response(state, ref, result) do
    %State{workers: workers} = state

    case Map.get(workers, ref) do
      {_bytes_requested, pid, _task_id} ->
        send(pid, {ref, result})
        state

      nil ->
        raise "Received an un-tracked reference"
    end
  end

  defp kickoff_new_task(%State{pool: %Pool{delegate_to: pool}}, fun, opts)
       when not is_nil(pool) do
    Pool.async(pool, fun, opts)
  end

  defp kickoff_new_task(_state, fun, opts) do
    %Task{ref: ref} =
      Task.async(fn ->
        Handler.run(fun, opts)
      end)

    {:ok, ref}
  end

  defp commit_resources(%State{workers: workers} = state, ref, bytes_requested, pid, task_id) do
    workers = Map.put(workers, ref, {bytes_requested, pid, task_id})

    %{
      state
      | workers: workers,
        running_workers: state.running_workers + 1,
        bytes_committed: state.bytes_committed + bytes_requested
    }
  end

  defp check_committed_resources(state, bytes_requested) do
    cond do
      state.running_workers >= state.pool.max_workers ->
        {:reject, NoWorkersAvailable.exception(message: "No workers available")}

      state.bytes_committed + bytes_requested > state.pool.max_memory_bytes ->
        {:reject, InsufficientMemory.exception(message: "Not enough memory available")}

      true ->
        :ok
    end
  end
end
