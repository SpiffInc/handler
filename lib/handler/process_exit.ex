defmodule Handler.ProcessExit do
  @type t :: %__MODULE__{}
  defexception [:message, :reason]
end
