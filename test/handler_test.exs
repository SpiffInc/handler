defmodule HandlerTest do
  use ExUnit.Case
  doctest Handler

  test "runs simple functions" do
    assert Handler.run(fn -> 1 + 1 end) == 2
  end

  test "it catches process exits and returns them as error tuples" do
    assert {:error, exception} = Handler.run(fn -> Process.exit(self(), :i_am_ded) end)
    assert exception.message == "There was a process exit with :i_am_ded"
    assert exception.reason == :i_am_ded
    assert exception.__struct__ == Handler.ProcessExit
  end

  test "it catches unhandled exceptions as process exits, and returns them as errors" do
    assert {:error, exception} = Handler.run(fn -> 1 / 0 end)
    assert exception.message == "There was a process exit with :badarith"
    assert {:badarith, _stacktrace} = exception.reason
    assert exception.__struct__ == Handler.ProcessExit
  end
end
