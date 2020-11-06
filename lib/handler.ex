defmodule Handler do
  @moduledoc """
  Documentation for `Handler`.
  """

  alias Handler.{OOM, ProcessExit, Timeout}

  @doc """
  Run a potentially problematic function

  ## Examples

      iex> Handler.run(fn -> 1 + 1 end)
      2
      iex> Handler.run(fn -> :timer.sleep(200) end, max_ms: 10)
      {:error, %Handler.Timeout{message: "Took more than 10ms to complete"}}
      iex> Handler.run(fn -> Enum.map(1..10_000, & &1*100) end, max_heap_bytes: 4096)
      {:error, %Handler.OOM{message: "Process tried to use more than 4096 bytes of memory"}}
      iex> Handler.run(fn -> Process.exit(self(), :i_am_ded) end)
      {:error, %Handler.ProcessExit{message: "Process exited with :i_am_ded", reason: :i_am_ded}}

  """
  def run(fun, opts \\ []) do
    # default options to 20min and 1GB of RAM
    max_ms = Keyword.get(opts, :max_ms, 1_200_000)
    max_heap_bytes = Keyword.get(opts, :max_heap_bytes, 1024 * 1024 * 1024)
    max_heap_words = div(max_heap_bytes, :erlang.system_info(:wordsize))

    old_trap_exit = Process.flag(:trap_exit, true)

    result =
      fun
      |> kickoff_fun(max_heap_words)
      |> await_results(max_ms, max_heap_bytes)

    Process.flag(:trap_exit, old_trap_exit)

    result
  end

  defp await_results(%Task{ref: ref, pid: pid} = task, max_ms, max_heap_bytes) do
    receive do
      {^ref, result} ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ^ref, :process, ^pid, :killed} ->
        Process.demonitor(ref, [:flush])
        message = "Process tried to use more than #{max_heap_bytes} bytes of memory"
        {:error, OOM.exception(message: message)}

      {:DOWN, ^ref, :process, ^pid, {header, _stacktrace} = reason} ->
        Process.demonitor(ref, [:flush])
        message = "Process exited with #{inspect(header)}"
        {:error, ProcessExit.exception(message: message, reason: reason)}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        Process.demonitor(ref, [:flush])
        message = "Process exited with #{inspect(reason)}"
        {:error, ProcessExit.exception(message: message, reason: reason)}
    after
      max_ms ->
        Process.demonitor(ref, [:flush])
        Task.shutdown(task, :brutal_kill)
        message = "Took more than #{max_ms}ms to complete"
        {:error, Timeout.exception(message: message)}
    end
  end

  defp kickoff_fun(fun, max_heap_words) do
    Task.async(fn ->
      Process.flag(:max_heap_size, max_heap_words)
      fun.()
    end)
  end
end
