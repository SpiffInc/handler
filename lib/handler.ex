defmodule Handler do
  @moduledoc """
  Documentation for `Handler`.
  """

  alias Handler.ProcessExit

  @doc """
  Run a potentially problematic function

  ## Examples

      iex> Handler.run(fn -> 1 + 1 end)
      2

  """
  def run(fun, opts \\ []) do
    # default options to 20min and 1GB of RAM
    max_time_ms = Keyword.get(opts, :max_time_ms, 1_200_000)
    max_heap_size_bytes = Keyword.get(opts, :max_heap_size_bytes, 1024 * 1024 * 1024)
    max_heap_size_words = div(max_heap_size_bytes, :erlang.system_info(:wordsize))

    old_trap_exit = Process.flag(:trap_exit, true)

    result =
      fun
      |> kickoff_fun(max_heap_size_words)
      |> await_results(max_time_ms)

    Process.flag(:trap_exit, old_trap_exit)

    result
  end

  defp await_results(%Task{ref: ref, pid: pid} = task, max_time_ms) do
    receive do
      {^ref, result} ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ^ref, :process, ^pid, :killed} ->
        Process.demonitor(ref, [:flush])
        {:error, "OOM"}

      {:DOWN, ^ref, :process, ^pid, {header, _stacktrace} = reason} ->
        Process.demonitor(ref, [:flush])
        message = "There was a process exit with #{inspect(header)}"
        {:error, ProcessExit.exception(message: message, reason: reason)}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        Process.demonitor(ref, [:flush])
        message = "There was a process exit with #{inspect(reason)}"
        {:error, ProcessExit.exception(message: message, reason: reason)}
    after
      max_time_ms ->
        Process.demonitor(ref, [:flush])
        Task.shutdown(task, :brutal_kill)
        {:error, "Statement update timed out after #{div(max_time_ms, 1000)}sec"}
    end
  end

  defp kickoff_fun(fun, max_heap_size_words) do
    Task.async(fn ->
      Process.flag(:max_heap_size, max_heap_size_words)
      fun.()
    end)
  end
end
