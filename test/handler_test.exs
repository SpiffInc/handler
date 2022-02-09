defmodule HandlerTest do
  use ExUnit.Case
  doctest Handler

  test "runs simple functions" do
    assert Handler.run(fn -> 1 + 1 end) == 2
  end

  test "it catches process exits and returns them as error tuples" do
    assert {:error, exception} = Handler.run(fn -> Process.exit(self(), :i_am_ded) end)
    assert exception.message == "Process exited with :i_am_ded"
    assert exception.reason == :i_am_ded
    assert exception.__struct__ == Handler.ProcessExit
  end

  test "it catches unhandled exceptions as process exits, and returns them as errors" do
    assert {:error, exception} = Handler.run(fn -> 1 / 0 end)
    assert exception.message == "Process exited with :badarith"
    assert {:badarith, _stacktrace} = exception.reason
    assert exception.__struct__ == Handler.ProcessExit
  end

  test "it catches out-of-memory cases and returns them as errors" do
    assert {:error, exception} = Handler.run(fn -> build_big_map() end, max_heap_bytes: 4096)
    assert exception.message == "Process tried to use more than 4096 bytes of memory"
    assert exception.__struct__ == Handler.OOM
  end

  test "it catches timeouts and returns them as errors" do
    assert {:error, exception} = Handler.run(fn -> :timer.sleep(500) end, max_ms: 10)
    assert exception.message == "Took more than 10ms to complete"
    assert exception.__struct__ == Handler.Timeout
  end

  describe "validating opts" do
    test "opts that are not a list raise an error" do
      assert_raise(ArgumentError, fn ->
        Handler.run(fn -> true end, %{})
      end)
    end

    test "an unexpected tuple raises an error" do
      assert_raise(ArgumentError, fn ->
        Handler.run(fn -> true end, [max_time: 200])
      end)
    end

    test "a tuple with an invalid value" do
      assert_raise(ArgumentError, fn ->
        Handler.run(fn -> true end, [max_ms: "foobar"])
      end)
    end

    test "a non-tuple in the opts list" do
      assert_raise(ArgumentError, fn ->
        Handler.run(fn -> true end, [:hi])
      end)
    end
  end

  defp build_big_map do
    Enum.reduce(1..1_000_000, %{}, fn i, map ->
      Map.put(map, i, "string #{i}")
    end)
  end
end
