defmodule Handler.Pool.NoWorkersAvailable do
  @type t :: %__MODULE__{}
  defexception [:message]
end

defmodule Handler.Pool.InsufficientMemory do
  @type t :: %__MODULE__{}
  defexception [:message]
end
