defmodule Handler.Pool.State do
  @moduledoc false
  alias __MODULE__
  alias Handler.Pool
  alias Handler.Pool.{InsufficientMemory, NoWorkersAvailable}
  import Handler.Opts

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
              from_pid :: pid(),
              task_pid :: pid(),
              task_name :: String.t()
            }
          },
          pool: %Handler.Pool{}
        }

  @type exception :: %InsufficientMemory{} | %NoWorkersAvailable{}

  @spec cleanup_commitments(t(), reference()) :: t()
  def cleanup_commitments(state, ref) do
    %State{workers: workers} = state

    case Map.get(workers, ref) do
      {bytes_requested, _from_pid, _task_pid, _task_name} ->
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
  @spec start_worker(t(), fun, Pool.opts(), pid()) ::
          {:ok, t(), reference()} | {:reject, exception()}
  def start_worker(state, fun, opts, from_pid) do
    bytes_requested = max_heap_bytes(opts)

    with :ok <- check_committed_resources(state, bytes_requested),
         {:ok, ref, task_pid} <- kickoff_new_task(state, fun, opts) do
      new_state = commit_resources(state, ref, bytes_requested, from_pid, task_pid, task_name(opts))
      {:ok, new_state, ref}
    end
  end

  def kill_worker(%State{pool: %Pool{delegate_to: pool}} = state, task_name)
      when not is_nil(pool) do
    if has_worker_named(state, task_name) do
      {:ok, number_killed} = Pool.kill(pool, task_name)
      {:ok, number_killed, state}
    else
      {:ok, 0, state}
    end
  end

  def kill_worker(state, task_name) do
    {state, number_killed} =
      Enum.reduce(state.workers, {state, 0}, fn
        {ref, {_bytes_commited, _from_pid, task_pid, ^task_name}}, {state, number_killed} ->
          Process.unlink(task_pid)
          Process.exit(task_pid, :user_killed)

          exception =
            Handler.ProcessExit.exception(
              message: "User killed the process",
              reason: :user_killed
            )

          state =
            state
            |> send_response(ref, {:error, exception})
            |> cleanup_commitments(ref)

          {state, number_killed + 1}

        _other_worker, {state, number_killed} ->
          {state, number_killed}
      end)

    {:ok, number_killed, state}
  end

  @spec send_response(t(), reference(), term) :: t()
  def send_response(state, ref, result) do
    %State{workers: workers} = state

    case Map.get(workers, ref) do
      {_bytes_requested, from_pid, _task_pid, _task_name} ->
        send(from_pid, {ref, result})
        state

      nil ->
        raise "Received an un-tracked reference"
    end
  end

  defp kickoff_new_task(%State{pool: %Pool{delegate_to: pool}}, fun, opts)
       when not is_nil(pool) do
    with {:ok, ref} <- Pool.async(pool, fun, opts) do
      {:ok, ref, nil}
    end
  end

  defp kickoff_new_task(_state, fun, opts) do
    %Task{ref: ref, pid: pid} =
      Task.async(fn ->
        Handler.run(fun, opts)
      end)

    {:ok, ref, pid}
  end

  defp commit_resources(
         %State{workers: workers} = state,
         ref,
         bytes_requested,
         from_pid,
         task_pid,
         task_name
       ) do
    workers = Map.put(workers, ref, {bytes_requested, from_pid, task_pid, task_name})

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

  defp has_worker_named(%{workers: workers}, task_name) do
    Enum.any?(workers, fn
      {_ref, {_bytes_requested, _from_pid, _task_pid, ^task_name}} -> true
      _ -> false
    end)
  end
end
