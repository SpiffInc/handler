# This benchmark is intentionally trying to highlight the bottlneeck of sending
# jobs through a single pool process. We expect there to be contention between
# the parallel clients. This can be guidance for people wondering if this will
# be a bottleneck for their use-case.

# Please note that the benchmark will return the performance seen by 1 client
# so a result of 11,600 ips at a parallel setting of 16 means that the pool was
# handling 185,600 jobs per second

alias Handler.Pool
config = %Pool{
  max_workers: 50,
  max_memory_bytes: 1024 * 1024
}
{:ok, pool} = Pool.start_link(config)
fun = fn -> 10 * 10 end
opts = [max_heap_bytes: 10 * 1024, max_ms: 100]

Benchee.run(
  %{
    "bare function" => fn -> 100 = fun.() end,
    "handled function" => fn -> 100 = Handler.run(fun, opts) end,
    "pooled function" => fn -> 100 = Pool.run(pool, fun, opts) end
  },
  time: 10,
  parallel: 16
)
