# Handler

Got a function that might get out of hand?
Let the Handler run it in its own process and it will "take care of" the process if things get out of hand.

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

## Pool Limits

You can also use Handler to manage a shared pool of resources. If there are not enough resources available
to run your function, you'll get back a `{:reject, exception}` value.

First start a supervised pool somewhere in your application tree.

```elixir application.ex
config = %Handler.Pool{
  max_workers: 20,
  max_memory_bytes: 5 * 1024 * 1024 * 1024,
  name: :my_pool
}

children = [
  {Handler.Pool, config}
]

opts = [strategy: :one_for_one, name: Peg.Supervisor]
Supervisor.start_link(children, opts)
```

Now that you have a pool being supervised, you can kick off some where from other parts of your project.

```elixir
Handler.Pool.run(:my_pool, fn -> danger_will_robinson() end, [max_heap_bytes: 1024 * 1024])
```