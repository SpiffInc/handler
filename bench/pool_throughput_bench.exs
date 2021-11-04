# This benchmark is intentionally trying to highlight the bottlneeck of sending
# jobs through a single pool process. We expect there to be contention between
# the parallel clients. This can be guidance for people wondering if this will
# be a bottleneck for their use-case.

alias Handler.Pool
config = %Pool{
  max_workers: 50,
  max_memory_bytes: 1024 * 1024
}
{:ok, pool} = Pool.start_link(config)
fun = fn -> 10 * 10 end
opts = [max_heap_bytes: 10 * 1024, max_ms: 20]

Benchee.run(
  %{
    "bare function" => fn -> 100 = fun.() end,
    "handled function" => fn -> 100 = Handler.run(fun, opts) end,
    "pooled function" => fn -> 100 = Pool.attempt_work(pool, fun, opts) end
  },
  time: 10,
  parallel: 16
)
