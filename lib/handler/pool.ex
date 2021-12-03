defmodule Handler.Pool do
  defstruct delegate_to: nil,
            max_workers: 100,
            max_memory_bytes: 10 * 1024 * 1024 * 1024,
            name: nil

  alias __MODULE__
  alias Handler.Pool.State
  use GenServer

  @type t :: %Handler.Pool{
          delegate_to: nil | name(),
          max_workers: non_neg_integer(),
          max_memory_bytes: non_neg_integer(),
          name: nil | name()
        }
  @type name :: GenServer.name()
  @type pool :: GenServer.server()
  @type exception :: Pool.InsufficientMemory.t() | Pool.NoWorkersAvailable.t()

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
  @spec async(pool(), (() -> any()), Handler.opts()) :: {:ok, reference()} | {:reject, exception}
  def async(pool, fun, opts) do
    GenServer.call(pool, {:run, fun, opts}, 1_000)
  end

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
  @spec run(pool(), (() -> any()), Handler.opts()) ::
          any() | {:error, Handler.exception()} | {:reject, exception()}
  def run(pool, fun, opts) do
    with {:ok, ref} <- async(pool, fun, opts) do
      await(ref)
    end
  end

  ## GenServer / OTP callbacks

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
  def handle_call({:run, fun, opts}, {pid, _tag}, state) do
    case State.start_worker(state, fun, opts, pid) do
      {:ok, state, ref} ->
        {:reply, {:ok, ref}, state}

      {:reject, exception} ->
        {:reply, {:reject, exception}, state}
    end
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
  def handle_info(other, state) do
    require Logger
    Logger.error("#{__MODULE__} received unexpected message #{inspect(other)}")
    {:noreply, state}
  end

  defp delegating_work?(%State{} = state) do
    state.pool.delegate_to != nil
  end
end
