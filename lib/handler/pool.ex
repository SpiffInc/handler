defmodule Handler.Pool do
  defstruct [
    max_workers: 100,
    max_memory_bytes: 10 * 1024 * 1024 * 1024,
    name: nil
  ]
  alias __MODULE__
  alias Handler.Pool.{NoWorkersAvailable, Worker}
  use GenServer

  @get_poolboy_timeout 500
  @max_wait_ms_default 500

  def start_link(%Pool{} = config) do
    GenServer.start_link(Pool, config)
  end

  def attempt_work(pool, fun, opts) do
    with {:ok, poolboy} = GenServer.call(pool, :get_poolboy, @get_poolboy_timeout) do
      max_wait_ms = Keyword.get(opts, :max_wait_ms, @max_wait_ms_default)
      try do
        :poolboy.transaction(
          poolboy,
          fn worker -> Worker.attempt_work(worker, pool, fun, opts) end,
          max_wait_ms
        )
      catch
        :exit, _error ->
          {:error, NoWorkersAvailable.exception(message: "No workers available")}
      end
    end
  end

  def init(%Pool{} = config) do
    server_args = [worker_module: Worker, size: 0, max_overflow: config.max_workers]
    {:ok, poolboy} = :poolboy.start_link(server_args, [])
    {:ok, %{poolboy: poolboy}}
  end

  def handle_call(:get_poolboy, _from, state) do
    {:reply, {:ok, state.poolboy}, state}
  end
end
