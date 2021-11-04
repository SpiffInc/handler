defmodule Handler.Pool.NoWorkersAvailable do
  defexception [:message]
end

defmodule Handler.Pool.InsufficientMemory do
  defexception [:message]
end
