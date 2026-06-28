# swarm — a distributed compute cluster you join by installing it

`swarm` turns a set of ordinary machines into a compute cluster for
embarrassingly-parallel numeric work. A new member joins the cluster **just by
running the binary** — no member list, no config, no recompile:

```sh
nurlpkg install swarm           # drops the `swarm` binary on $PATH
swarm worker <relay-host> <port>   # ← that's the join. it now takes work.
```

It is built entirely on NURL's standard distributed stack (see
[`docs/DISTRIBUTED.md`](../../docs/DISTRIBUTED.md)): `net/relay` for reach
through NATs, `net/transport` for the pubkey-addressed seam, `dist/ring` for
consistent-hash key ownership, and `dist/job` for the submit → owner → result
dispatch. `swarm` is the thin application on top: membership-by-arrival, two
real workloads, and a CLI.

## Quick start

One machine runs a relay (the meeting point — one per cluster):

```sh
swarm relay 0.0.0.0 47700
```

Any number of machines join as workers (this is the whole "add a node" story):

```sh
swarm worker <relay-host> 47700        # auto-assigns a node id
swarm worker <relay-host> 47700 7      # or pin an id
```

From anywhere, place a **real** workload — it is sharded across the live
workers by key, each worker does genuine CPU work on its share, and the
partial results are summed:

```sh
swarm submit <relay-host> 47700 primes 1 1000000   # → result = 78498  (π(10^6))
swarm submit <relay-host> 47700 sumsq  0 1000       # → result = 332833500
```

Start more workers and submit again — the new workers take their share of the
keyspace on the next submit. Kill a worker and its keys re-home to the
survivors (`dist/job` forwards a submit for a key whose owner moved).

## How it works

1. **Join = announce.** A worker broadcasts a `HELLO` to the relay group
   (`census.nu`). Every node that hears it folds the worker's pubkey into its
   consistent-hash ring, and replies so the newcomer learns the existing
   members. The ring converges with no central coordinator.
2. **Submit = shard by key.** The coordinator discovers the live workers the
   same way, splits the requested range into many chunks, and keys each chunk
   so `dist/ring` routes it to its owning worker (`dist/job` carries it over
   the transport). More chunks than workers → even load.
3. **Execute = registered handler.** Each worker has registered a handler per
   workload kind (`work.nu`); it runs the honest computation on its chunk
   (primes are *counted by trial division*, not looked up) and returns the
   partial result, recorded idempotently by task id.
4. **Aggregate.** The coordinator awaits every chunk and sums them.

## Workloads

| kind     | `submit … <kind> <lo> <hi>`        | result                              |
|----------|------------------------------------|-------------------------------------|
| `primes` | count primes in `[lo, hi)`         | e.g. `primes 1 1000000` → `78498`   |
| `sumsq`  | Σ k² for k in `[lo, hi)` (i64)     | e.g. `sumsq 0 1000` → `332833500`   |

Both are verifiable by a closed form, which is exactly what the test suite
pins. Adding a workload is one handler in `work.nu` plus a kind constant.

## Tests

```sh
# pure logic (workloads, exact sharding, codecs) — deterministic, ASan-clean
NURL_STDLIB=<repo> ../../nurl.sh tests/work_test.nu /tmp/wt && /tmp/wt

# end-to-end over a local relay + worker set
./tests/live_smoke.sh
```

## Layout

```
src/main.nu     CLI (relay | worker | submit) + the node bundle and pump loop
src/census.nu   HELLO membership gossip → consistent-hash ring
src/work.nu     the real workloads: handlers, sharding, aggregation
```

## License

MIT OR Apache-2.0.
