# This benchmark is an attempt to measure the overhead of using handler either directly
# or through a pool. We use a function which is extremely fast on its own, so we get can
# get an idea of how much extra time is spent in spinning up processes, setting process
# flags etc

alias Handler.Pool
config = %Pool{
  max_workers: 10,
  max_memory_bytes: 1024 * 1024
}
{:ok, pool} = Pool.start_link(config)
fun = fn -> 10 * 10 end
opts = [max_heap_bytes: 10 * 1024, max_ms: 20]

Benchee.run(
  %{
    "bare function" => fn -> 100 = fun.() end,
    "handled function" => fn -> 100 = Handler.run(fun, opts) end,
    "pooled function" => fn -> 100 = Pool.run(pool, fun, opts) end
  },
  time: 10
)
