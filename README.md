# Handler

Got a function that might get out of hand?
Let the Handler run it in its own process and it will "take care of" the process if things get too wild.

![handler](handler.png)

## Usage

```elixir
Handler.run(fn -> 1 + 1 end)
# => 2
Handler.run(fn -> :timer.sleep(61_000) end)
# => {:error, %Handler.Timeout{message: "process ran for longer than 60000ms"}}
Handler.run(fn -> load_tons_of_data_into_memory() end)
# => {:error, %Handler.OOM{message: "process tried to use more than 10485760 bytes of memory"}}
Handler.run(fn -> Process.exit(self(), :i_am_ded) end)
# => {:error, %Handler.ProcessExit{message: "process exited with :i_am_ded"}}
```

By default Handler puts a limit of 60sec and 10MB of heap space on the function you are running.
You can change these limits by passing the optional second argument.

```elixir
# Set 100MB heap limit and 2sec time limit
Handler.run(fn -> 1 + 1 end, max_heap_bytes: 100 * 1024 * 1024, max_ms: 2_000)
# => 2
```