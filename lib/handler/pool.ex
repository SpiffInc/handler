defmodule Handler.Pool do
  defstruct delegate_fun: nil,
            delegate_to: nil,
            max_workers: 100,
            max_memory_bytes: 10 * 1024 * 1024 * 1024,
            name: nil

  alias __MODULE__
  alias Handler.Pool.State
  import Handler.Opts
  use GenServer

  @type t :: %Handler.Pool{
          delegate_fun: nil | {module(), fn_name :: atom(), first_argument :: term()},
          delegate_to: nil | name(),
          max_workers: non_neg_integer(),
          max_memory_bytes: non_neg_integer(),
          name: nil | name()
        }
  @type name :: GenServer.name()
  @type opts :: list(opt())
  @type opt :: Handler.opt() | {:task_name, String.t()} | {:delegate_param, term()}
  @type pool :: GenServer.server()
  @type exception :: Pool.InsufficientMemory.t() | Pool.NoWorkersAvailable.t()

  @user_killed_process_exit Handler.ProcessExit.exception(
                              message: "User killed the process",
                              reason: :user_killed
                            )

  @moduledoc """
  Manage a pool of resources used to run dangerous functions

  The Pool provides both a synchrous interface (`run/3`) as well as an asynchronous
  interface (`async/3` and `await/1`) for running functions.

  ## Composing Pools

  This module also provides a way to have limited resources for particular use-cases, that end up
  sharing bigger pools of resources. Take for instance a hosted multi-tenant application where you
  can safely use up to 10GB of memory for a particular task, but you don't want any one customer to
  use the whole pool, so each customer has a limit of just 5GB. You can handle this scenario using
  the `delegate_to` configuration.

      {:ok, _pid} = Handler.Pool.start_link(%Handler.Pool{
        max_memory: 10 * 1024 * 1024 * 1024,
        name: :shared_pool
      })
      {:ok, _pid} = Handler.Pool.start_link(%Handler.Pool{
        delegate_to: :shared_pool,
        max_memory: 5 * 1024 * 1024 * 1024,
        name: :customer_pool
      })

      100 = Pool.run(:customer_pool, fn -> 10 * 10 end, max_heap_bytes: 100 * 1024)
  """

  @doc """
  Asynchronously start a job

  Take a potentially dangerous function and run it in the pool. You'll either get back an ok tuple with
  a reference you can pass to the `await/1` function, or a reject tuple with an exception describing
  why the function couldn't be started.
  """
  @spec async(pool(), (() -> any()), opts()) :: {:ok, reference()} | {:reject, exception}
  def async(pool, fun, opts) do
    validate_pool_opts!(opts)
    GenServer.call(pool, {:run, fun, opts}, 1_000)
  end

  @doc """
  Wait for the result of a job kicked off by async
  """
  @spec await(reference()) :: any() | {:error, Handler.exception()}
  def await(ref) do
    receive do
      {^ref, result} ->
        result
    end
  end

  @doc """
  Run a potentially dangerous function in the pool

  This function has pretty much the same interface as `Handler.run/2` with
  the addition of the `{:reject, t:exception()}` return values when the pool
  does not have enough resources to start a particular function.
  """
  @spec run(pool(), (() -> any()), opts()) ::
          any() | {:error, Handler.exception()} | {:reject, exception()}
  def run(pool, fun, opts) do
    validate_pool_opts!(opts)

    with {:ok, ref} <- async(pool, fun, opts) do
      await(ref)
    end
  end

  @doc """
  Kill jobs by their `:name`

  When kicking off a job the `:name` option can be set and then later
  this function can be used to kill any jobs in progress with a `:name`
  matching the `task_name` of this function.

  The client that kicked off the work will receive an `{:error, exception}`
  as the result for the job. If you don't pass an exception, you will get back
  a `Handler.ProcessExit{reason: :user_killed}` by default.
  """
  @spec kill(pool(), String.t()) :: {:ok, integer()}
  def kill(pool, task_name, exception \\ @user_killed_process_exit) when is_binary(task_name) do
    GenServer.call(pool, {:kill, task_name, exception})
  end

  @doc """
  Kill a job by its `ref`

  When kicking off a job with the `async/3` function a `ref` is returned
  and that job can later be killed.

  The client that kicked off the work will receive an `{:error, exception}`
  as the result for the job. If you don't pass an exception, you will get back
  a `Handler.ProcessExit{reason: :user_killed}` by default.
  """
  @spec kill_by_ref(pool(), reference()) :: :ok | :no_such_worker
  def kill_by_ref(pool, ref, exception \\ @user_killed_process_exit) when is_reference(ref) do
    GenServer.call(pool, {:kill_ref, ref, exception})
  end

  @doc """
  Kill all jobs in a pool. Returns the number of killed jobs.

  The client that kicked off the work will receive an `{:error, exception}`
  as the result for the job. If you don't pass an exception, you will get back
  a `Handler.ProcessExit{reason: :user_killed}` by default.
  """
  @spec flush(pool()) :: {:ok, non_neg_integer()}
  def flush(pool, exception \\ @user_killed_process_exit) do
    GenServer.call(pool, {:flush, exception})
  end

  ## GenServer / OTP callbacks

  @spec start_link(Handler.Pool.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(%Pool{name: name} = config) when not is_nil(name) do
    opts = [name: name]
    GenServer.start_link(Pool, config, opts)
  end

  def start_link(%Pool{} = config) do
    GenServer.start_link(Pool, config)
  end

  @impl GenServer
  def init(%Pool{} = pool) do
    state = %State{pool: pool}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:run, fun, opts}, {from_pid, _tag}, state) do
    case State.start_worker(state, fun, opts, from_pid) do
      {:ok, state, ref} ->
        {:reply, {:ok, ref}, state}

      {:reject, exception} ->
        {:reply, {:reject, exception}, state}
    end
  end

  @impl GenServer
  def handle_call({:kill, task_name, exception}, _from, state) do
    {:ok, state, number_killed} = State.kill_worker(state, task_name, exception)
    {:reply, {:ok, number_killed}, state}
  end

  @impl GenServer
  def handle_call({:kill_ref, ref, exception}, _from, state) do
    {:ok, state, result} = State.kill_worker_by_ref(state, ref, exception)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:flush, exception}, _from, state) do
    {:ok, state, number_killed} = State.flush_workers(state, exception)
    {:reply, {:ok, number_killed}, state}
  end

  @impl GenServer
  def handle_info({ref, result}, state) when is_reference(ref) do
    if delegating_work?(state) do
      state =
        State.send_response(state, ref, result)
        |> State.cleanup_commitments(ref)

      {:noreply, state}
    else
      state = State.send_response(state, ref, result)
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, :normal}, state)
      when is_reference(ref) and is_pid(pid) do
    state = State.cleanup_commitments(state, ref)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, pid, :normal}, state) when is_pid(pid) do
    # tasks that are killed via :user_killed send this message back in
    # addition to the {:DOWN, ref, :process, pid, :normal} message
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(other, state) do
    require Logger
    Logger.error("#{__MODULE__} received unexpected message #{inspect(other)}")
    {:noreply, state}
  end

  defp delegating_work?(%State{} = state) do
    state.pool.delegate_to != nil or state.pool.delegate_fun != nil
  end
end
