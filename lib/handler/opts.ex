defmodule Handler.Opts do
  @moduledoc false

  def bytes_to_words(max_bytes) when is_integer(max_bytes) do
    div(max_bytes, :erlang.system_info(:wordsize))
  end

  def max_heap_bytes(opts) do
    Keyword.get(opts, :max_heap_bytes, 10 * 1024 * 1024)
  end

  def max_ms(opts) do
    Keyword.get(opts, :max_ms, 60_000)
  end

  def task_name(opts) do
    Keyword.get(opts, :task_name)
  end

  def validate_handler_opts!([]), do: :ok

  def validate_handler_opts!(opts) when is_list(opts) do
    Enum.each(opts, &validate_handler_opt!/1)
  end

  def validate_handler_opts!(_other) do
    raise ArgumentError, "Invalid opts provided, not a list"
  end

  defp validate_handler_opt!({:max_ms, number}) when is_integer(number) and number > 0, do: :ok

  defp validate_handler_opt!({:max_heap_bytes, number}) when is_integer(number) and number > 0,
    do: :ok

  defp validate_handler_opt!(other) do
    raise ArgumentError, "Invalid option #{inspect(other)}"
  end

  def validate_pool_opts!([]), do: :ok

  def validate_pool_opts!(opts) when is_list(opts) do
    Enum.each(opts, &validate_pool_opt!/1)
  end

  def validate_pool_opts!(_other) do
    raise ArgumentError, "Invalid opts provided, not a list"
  end

  defp validate_pool_opt!({:delegate_param, _term}), do: :ok

  defp validate_pool_opt!({:max_ms, number}) when is_integer(number) and number > 0, do: :ok

  defp validate_pool_opt!({:max_heap_bytes, number}) when is_integer(number) and number > 0,
    do: :ok

  defp validate_pool_opt!({:task_name, _name}), do: :ok

  defp validate_pool_opt!(other) do
    raise ArgumentError, "Invalid option #{inspect(other)}"
  end
end
