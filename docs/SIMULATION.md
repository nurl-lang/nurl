# Deterministic simulation testing

A distributed system's worst bugs live in interleavings and failures a
test on a working network never produces: a reply lost after the commit,
a peer that crashes with a request in hand, a retry that lands twice.
NURL tests them the way FoundationDB and TigerBeetle do: the whole system
runs in one process, over a simulated network that loses, delays,
reorders and partitions on purpose, with servers that crash and restart.
At the end the test checks what must hold for every run.

The pieces, each a standard-library or package API rather than a test
harness of its own:

| piece | what it gives | where |
|---|---|---|
| `NetSim` | nodes with whole TCP/IP stacks over a seeded bus: drops, latency, jitter, partitions | `stdlib/std/net_sim.nu`, [NETWORKING.md](NETWORKING.md#simulated-network--stdlibstdnet_simnu) |
| the transport seam | `TcpListener` / `TcpConn` over a simulated socket, so `HttpApp`, `HttpServer` and any protocol client run unchanged; TLS too (`netsim_listen_tls`, `tcp_starttls`) | `stdlib/std/net.nu`, `stdlib/std/tls.nu` |
| dialers | clients that dial through a `NetDialer` chosen at construction: http-client, psql, redis, nurldb | [NETWORKING.md](NETWORKING.md#clients-a-dialer-chosen-at-construction) |
| `netsim_crash` | a node crashes and reboots empty: every socket gone at once, no FIN | `stdlib/std/net_sim.nu` |
| `serve_on`, `db_crash` | nurldb served on a simulated listener; dropped as a killed process leaves it, reopened from its log | `packages/nurldb/src/server.nu`, `db.nu` |
| the simulation runtime | virtual time, seeded entropy and a seeded schedule: one seed, one run | `unikernel/build_nolibc.sh --sim` (agora #260) |

## Faults

```nurl
: NetSim net ( netsim_new 3 262 0 1 1 )  // 3 nodes, seed 262, no loss, 1 ms latency, 1 ms jitter
( netsim_partition net 1 2 )  // every frame between nodes 1 and 2 is lost…
( netsim_heal net 1 2 )  // …until healed; TCP's retransmission carries on
( netsim_crash net 2 )  // node 2 loses power and reboots
```

A crash takes every socket of the node at once, listeners and
connections, with no FIN. An operation through one of them finds it
closed (`NetClosed`). A server's accept loop on it ends. Its peers learn
of it as peers do: a reset when they next send to it, or their own
timeouts when it never answers. A peer that sent a request and is now
only waiting will wait forever unless it has a deadline, and the
scenario below is how NURL found that its database client had none
(`client_set_timeout`). The node can listen again at once, on the same
port.

A process restart is the program's part. nurldb's `serve_on` returns once
its listener stops accepting and its connections have ended. `db_crash`
then drops the database without a checkpoint, losing the dirty pages a
killed process loses, and `db_open` on the same directory recovers from
the write-ahead log:

```nurl
( netsim_crash net 2 )
?? srv { T h → { : i _j ( thread_join h ) } F _ → {} }  // serve_on returned
( db_crash d )
= d ?? ( db_open ( string_data dir ) ( db_default_opts ) ) { T x → x F e → { ^ 1 } }
: TcpListener l2 ?? ( netsim_listen net 2 5433 ) { T x → x F _ → { ^ 1 } }
// …and serve_on d l2 on a thread again
```

Unsynced writes survive this crash: the files are the host's, and a
write the log made without `fdatasync` is still in its page cache. A
storage seam that loses them (a simulated disk under `pfile`) is the next
piece. Until then, "acknowledged before the log was durable" is the one
crash bug this setup cannot catch.

## The flagship scenario — `compiler/tests/dst_flagship.nu`

Three nodes:

- **node 0**: three HTTP clients (packages/http-client through
  `netsim_dialer`);
- **node 1**: the service, an `HttpApp` with one route,
  `GET /op/:id/:client`. It applies operation `id` in one transaction,
  `INSERT INTO ops VALUES (id, client)` (the receipt) and
  `UPDATE acct SET bal = bal + 1` (the effect), and answers 200 once the
  COMMIT returns. If the receipt is already there, the operation is a
  retry of one that committed, and that is a 200 too: an operation is
  idempotent by its id. Anything else is a 503;
- **node 2**: nurldb.

Each client applies its operations in turn and retries a failed one with
the same id. Meanwhile the harness cuts the service off from the database
for 300 ms, heals the link, and crashes and restarts the database. Then
it reads the database directly and checks:

1. **Every acknowledged operation is there.** Every id a client was told
   succeeded has its receipt after recovery.
2. **None was applied twice.** The balance equals the number of
   receipts.
3. **Everyone finished.** Each operation was answered, or given up on
   after its retries. Nobody hangs on a crashed peer: the service reads
   the database with a deadline, and the clients read the service with
   one.

A run takes about two seconds on the hosted runtime, where a fault meets
from 9 to 12 operations in flight. The invariants are what make the test
worth having. Break the service on purpose by running the `UPDATE` as a
statement of its own, before the transaction that writes the receipt. A
retry of an operation whose first attempt died between the two then pays
twice, and check 2 fails in every run we tried (8/8; the balance reached
37–39 for 36 receipts). That is the bug class a single-machine test never
sees.

## Seeds

On the hosted runtime the scenario runs in real time, and its
interleavings vary from run to run: it checks that the invariants hold
for each one it meets. The simulation runtime (agora #260,
`unikernel/build_nolibc.sh --sim`) makes a run a function of its seed.
Time is virtual, so the 300 ms partition costs no wall time. Entropy
(TCP sequence numbers, `std/random`) and the scheduler's every choice
come from the seed, and `NURL_SIM=<seed>` replays one exactly. Still to
come before the scenario runs that way:

- `nurlpkg test --sim --seeds N` (agora #261): run a test under N seeds,
  print a failing seed's replay line;
- the bare runtime's reader-writer lock (agora #286): nurldb's log and
  buffer pool use `RwLocked`, which that runtime does not have yet.

Then the scenario becomes the DONE of agora #262: it passes for 1000
seeds, and the injected bug above is found by a seed that replays it
exactly.
