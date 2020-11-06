defmodule HandlerTest do
  use ExUnit.Case
  doctest Handler

  test "greets the world" do
    assert Handler.hello() == :world
  end
end
