defmodule Handler.Pool.NoWorkersAvailable do
  defexception [:message]
end

defmodule Handler.Pool.NoMemoryAvailable do
  defexception [:message]
end
