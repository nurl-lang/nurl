# Async runtime — stackful fibers, no function colouring

NURL ships an **M:N stackful-fiber runtime**: many lightweight fibers
multiplex onto a small pool of OS worker threads, with an I/O reactor
that parks a fiber on a socket and resumes it when the socket is ready.
The defining property is **no function colouring** — there is no
`async` keyword, no `await`, no split between sync and async functions.
Ordinary code runs unchanged inside a fiber; blocking I/O calls become
cooperative automatically when invoked from fiber context.

```nurl
$ `stdlib/std/async.nu`

@ main → i {
    ( runtime_init 0 )                  // 0 = worker count from NURL_WORKERS, default = cores
    ( spawn \ → v { ( nurl_print `hello from a fiber\n` ) } )
    ( runtime_run )                     // blocks until every fiber is done
    ^ 0
}
```

## 1. The model

- **Stackful.** Each fiber owns a real (mmap'd) stack, switched by
  swapping the callee-saved registers and `rsp` (see §5) — so *any*
  existing function can yield anywhere beneath any call depth. No
  compiler transformation, no state machines, no colouring. The cost is
  memory per fiber (fixed-size stacks) instead of Go-style movable
  stacks; the benefit is that every existing nurlc IR pattern works
  unchanged.
- **M:N.** `runtime_init workers` starts a pool of OS threads
  (`workers = 0` reads `$NURL_WORKERS`, defaulting to the core count).
  Fibers are scheduled onto whichever worker is free.
- **Work stealing.** Each worker keeps a run queue (mutex-protected
  FIFO); an idle worker steals the front half of a victim's queue. This
  is deliberately simple — a lock-free deque is unnecessary at the
  scale the runtime currently serves.
- **Service order.** A worker runs fibers in the order they became
  runnable. Every push onto a run queue stamps the fiber from one
  clock; the worker takes the older of its own queue's head and the
  global queue's head, and a yield re-stamps the fiber behind
  everything that became runnable meanwhile. So a worker never runs a
  fiber while an older one waits in its queues: not a spawn ahead of
  an unparked fiber, not fresh I/O ahead of older I/O. Until agora
  #113 the local queue simply came first, and on a saturated worker
  fibers spilled or unparked onto the global queue were overtaken by
  everything pushed locally after them. tls-bench measured that as
  handshake p99 at 1.4–4.5× p50 where rustls stayed near 1.3×;
  `compiler/tests/sched_ready_order` measured the order itself (a
  reader overtaken by 55 of 99 later ones before, none after).
- **Admission.** A fiber parked in an accept runs as soon as its
  listener is polled ready, ahead of everything queued: the Linux
  netpoller hands it back to run now, the poll(2) reactor puts it at the
  head of the global queue with the oldest stamp, and the unikernel's
  socket layer wakes it to the head of the bare runtime's run queue.
  Accepting is how the connections waiting in the kernel's queue enter
  the service order (each one's fiber is stamped when it is spawned),
  and it is cheap: an accept and a spawn per connection. Queued at the
  tail like any woken fiber, the accept first waited a whole pass of the
  run queue, and everything that became runnable meanwhile went ahead of
  connections that had arrived before it. On a saturated TLS server a
  new connection then waited one pass in the kernel's queue and another
  in the run queue, by however much work happened to be queued at each:
  the handshake latency spread over 4–11 ms where rustls held 5–8 ms
  (agora #113, measured per connection by joining the client's and the
  server's timestamps on the source port). With admission the accept
  waits at most one poll window, and the spread is inside rustls's own
  run-to-run range: handshake p99/p50 medians of three runs 1.57 against
  rustls's 1.62 (full X25519, 2.25 before) and 1.57 against 1.46
  (resumed, 1.85 before); rustls's ratio moved between 1.42 and 2.05 on
  that host. `compiler/tests/sched_accept_admission` holds the bound: a
  connection is accepted within half a pass of a 64-fiber queue (before:
  never, a full pass and more).
- **Netpoller (Linux).** There is no reactor thread on Linux: an IDLE
  WORKER becomes the I/O poller (the Go netpoller / tokio driver
  shape). It takes the poll lease and blocks in `epoll_wait` itself; a
  ready fiber resumes directly on that worker — no queue hop, no
  cross-thread wake chain, no core migration. That direct run is for
  an idle worker only: what a busy worker's poll wakes joins the
  queues' tails in event order. Surplus ready fibers are
  split: the oldest few stay on the poller's own local queue (warm
  cache, no wake), and anything beyond that bounded share is appended
  to the global FIFO as one pre-linked chain, which every worker
  drains in fair batches (`len / workers + 1` per grab, one lock
  acquisition). The split is what bounds tail latency: under
  saturation stealing never fires (it needs an empty thief queue), so
  an unbounded local haul would drain a 100-event burst at one core's
  speed — measured as a multi-ms p99. Workers also run a cadence poll
  (every 16th dispatch, whatever is queued) so the epoll instance is
  drained continuously instead of only when the queues run dry. Ready
  I/O enters the service order when it is polled, so this also bounds
  how long it waits unpolled; without it the pool lives in
  feast-famine cycles. Sockets are registered once per fd lifetime
  (`EPOLLIN|EPOLLOUT|EPOLLET`, persistent); readiness edges that
  arrive while a fiber is busy are banked in per-fd ready bits, so
  under load the next wait consumes the bit and skips the park
  entirely. Deadlines live in a min-heap; an `eventfd` wakes a
  sleeping poller when a nearer deadline or new runnable work appears.
  The edge-triggered contract is safe because every stdlib wait runs
  only after the fd answered `EAGAIN` — a fresh readiness transition
  is always a fresh edge. Closing a socket routes through the
  netpoller (`nurl_close_sock`), which wakes any parked waiter and
  resets the per-fd slot before the fd number can be reused.
- **Reactor (other POSIX).** On non-Linux POSIX a dedicated thread
  runs the portable `poll(2)` loop plus a timer wheel: a fiber that
  would block registers the fd and parks; the reactor unparks it when
  the fd is ready or the timeout fires. (A `kqueue` netpoller is the
  matching upgrade path for macOS/BSD.)

## 2. API surface (`stdlib/std/async.nu`)

| Function | Meaning |
|---|---|
| `runtime_init i workers → v` | start the pool (0 ⇒ `$NURL_WORKERS`, default cores) |
| `runtime_run → v` | block until the pending-fiber count reaches 0 |
| `runtime_shutdown → v` | request shutdown, wake workers, join threads |
| `spawn ( @ v ) body → Fiber` | fire-and-forget fiber |
| `spawn_joinable ( @ v ) body → Fiber` | fiber whose completion can be awaited |
| `fiber_join Fiber f → v` | park until a joinable fiber finishes |
| `yield → v` | cooperative reschedule point |
| `fiber_current → ?Fiber` | the running fiber, `None` outside fiber context |
| `fiber_worker_id → i` | index of the worker executing this fiber |
| `wait_readable i fd i timeout_ms → i` | park until fd readable / timeout |
| `wait_writable i fd i timeout_ms → i` | park until fd writable / timeout |

`Fiber` is an opaque handle (`: Fiber { s raw }`). `sleep_ms` lives in
`stdlib/std/time.nu`; inside a fiber it parks on the timer wheel instead
of blocking the worker.

## 3. Async I/O

The socket layer (`stdlib/std/net.nu`) provides fiber-aware variants of
the blocking primitives:

- `tcp_accept_async` — park on the listener until a connection arrives
- `tcp_read_chunk_async` — park until readable, then read
- `tcp_write_all_async` — park on write backpressure

Called **outside** fiber context (or on a platform where fibers are
stubbed — §5), each falls back to its blocking counterpart
transparently. Everything above the socket layer is colouring-free by
construction: the HTTP request parser, response builder, router and
middleware are plain functions that work identically under
`server_run_pool` (threads) and `server_run_async` (fibers).

**Channels are fiber-aware** (`stdlib/std/channel.nu`): `chan_send` /
`chan_recv` park the calling fiber on the channel's waiter list and
resume on the next send/recv; from a plain thread the same calls use the
per-channel condvar. One `Channel[A]` type serves both worlds.

**Pools are fiber-aware too** (`stdlib/std/pool.nu`): a checkout that
finds every resource lent parks the fiber with a deadline
(`nurl_fiber_park_with_mutex_ms`), and a returned resource wakes it with
`nurl_fiber_wake` — the two race for the wait entry under the reactor
lock, so a wake that loses to the deadline does nothing and the fiber
runs once. A thread on the same pool waits on its condvar.

**`server_run_async`** (`stdlib/ext/http_server.nu`) drives the HTTP
server on fibers: an accept fiber spawns one fiber per connection. It
returns when the listener closes and the fiber pool drains. Since 0.46.0
the three serve paths share one `__serve_accepted` — so keep-alive, the
request-line timeout and the DoS limits are literally the same code
under `server_run`, `server_run_pool` and `server_run_async`, rather
than three implementations that were supposed to agree. (They did not:
the async path had neither admission control nor a per-connection idle
timeout before that.)

**TLS works on the fiber path** as of 0.46.0, which is what makes it a
deployment mode rather than a demo. Two things had to change. First,
`std/tls.nu`'s `__fill` / `_tls_sock_write` are context-aware: on a
fiber, `EAGAIN` parks on the reactor and the worker moves to another
connection; off a fiber they block exactly as before, so a threaded
caller is unaffected. Second, the handshake moved off the accept fiber
— `tcp_accept_transport` accepts without handshaking and
`tcp_conn_complete_tls` runs the handshake on the *connection's* own
fiber, so handshakes overlap instead of serialising one behind another
(675 → 7 034 handshakes/s on a 12-core i7-5930K). A connection whose
handshake fails is now one failed connection; a plain-TCP probe against
a TLS port used to take the whole accept loop down with it.

**Outbound connects park too.** `tcp_connect` (and everything built on
it: `tcp_connect_tls*`, the psql, redis and HTTP clients) used to run a
blocking `getaddrinfo` and a blocking `connect(2)` even on a fiber, so a
slow DNS answer or a SYN to an unreachable host stalled the whole
worker and every fiber queued on it. On a fiber the socket is now
non-blocking and the fiber parks for writability on the netpoller; a
name is resolved by `getaddrinfo` on a small resolver thread pool
(`stdlib/runtime_ffi.c` §18-r) and the fiber parks on the job's
completion eventfd meanwhile. `tcp_connect_timeout` puts one deadline
over both, on the netpoller's timer heap. The same pass fixed a
scheduler starvation: a worker whose local queue never emptied — a
fiber yielding in a loop — never looked at the netpoller or the global
queue, so timer, I/O and unpark wakes on that worker waited for as long
as it kept yielding. (Then every 128th dispatch looked at both first;
since #113 the cadence poll and the service order cover it.)

`packages/http` exposes this as **`http_app_async n`** — fiber per
connection, `n` worker pthreads, `0` meaning one per CPU the *process*
may run on — the affinity mask (`taskset`, cpusets) capped by the
container's cgroup CPU quota (`sys_available_parallelism`), not the
machine's CPU count; a pool larger than that only time-slices against
itself.

## 4. Semantics worth knowing

- **`runtime_run` waits for pending = 0.** Every `spawn` bumps a pending
  count; every completed fiber decrements it. A server's accept fiber
  keeps the count non-zero on purpose — stop it via `server_stop` /
  `runtime_shutdown`.
- **Spawn is not a thread.** The closure runs on some worker's fiber; a
  CPU-bound fiber that never yields occupies its worker until it does.
  `yield` inside long computations keeps latency flat.
- **Crossing fibers follows the same ownership rules as threads.** A
  `spawn` closure moves its owned captures (naming one again is an error)
  and takes its own share of each `Channel` / `Mutex` / `Arc` / `Locked` /
  `RwLocked` / `Atomic` ([`MEMORY.md` §6.2](MEMORY.md)); state fibers
  change lives in a `( Locked T )`, an `( RwLocked T )` or an `Atomic`, or
  goes through a `Channel`, and an `Arc` shares a value nobody changes ([`MEMORY.md` §6.5](MEMORY.md); see
  [Operational caveats](#operational-caveats)).

## 5. Platform support

Fibers need pthreads, `mmap`, and a stackful context switch. The switch
has two backends:

- **`stdlib/runtime_ctx.c`** — NURL's own inline-assembly switch on all three
  64-bit ISAs (`x86_64` SysV, `AArch64` AAPCS64, and `RISC-V64` LP64D), and
  on x64 Windows (the Microsoft x64 ABI: `rdi`, `rsi` and `xmm6`–`xmm15`
  callee-saved too, and the TIB's stack bounds switched per fiber, since the
  CRT's `longjmp` — every panic — unwinds against them). It
  depends on the instruction set alone, so it needs no libc support at
  all (including musl, macOS ARM64 where Apple's `ucontext` is broken, and
  freestanding unikernels), and it does not pay `swapcontext`'s `sigprocmask`
  syscall: 8 M yields through the scheduler take 0.38 s against ucontext's
  6.90 s, with `sys` time going from 2.1 s to zero.
- **`ucontext`** (`getcontext`/`makecontext`/`swapcontext`) — fallback on
  other POSIX architectures whose libcs ship a working one.

| Platform | Fibers |
|---|---|
| Linux x86_64 / arm64 / riscv64 (glibc **or musl**) | ✔ own asm switch (`runtime_ctx.c`) |
| macOS x86_64 / arm64 | ✔ own asm switch (`runtime_ctx.c`) |
| FreeBSD / NetBSD / DragonFly (x86_64 / arm64) | ✔ own asm switch (`runtime_ctx.c`, `ucontext` fallback on other ISAs) |
| Unikernel (x86_64 / arm64 / riscv64) | ✔ own asm switch (`runtime_bare.c`) |
| Windows x64 (MSVC-target clang and MinGW) | ✔ own asm switch (`runtime_ctx.c`), `VirtualAlloc` stacks |
| OpenBSD | stubbed (removed `swapcontext`) |
| Windows arm64, WASI | stubbed |

The I/O backend is the `epoll` netpoller on Linux and a `poll(2)`
reactor thread elsewhere — `WSAPoll` on Windows, where the reactor's wake
channel and the resolver pool's completion signal are self-connected
loopback UDP sockets (`WSAPoll` waits on sockets only). It starts only
where fibers are enabled.

**What "stubbed" means, precisely.** The `*_async` I/O calls do degrade
to their blocking forms and stay correct. `spawn` does **not**: with no
backend it returns a null handle and *the closure never runs at all*.
A program that spawns work and prints the result gets zeros and exit 0
— a silent wrong answer, not a slower right one. Treat a stubbed
platform as "no async", not as "async without concurrency".

**Where the backend exists, a spawn that fails is now loud.** It used to
have the same shape as the stub for a different reason: `spawn` returns
a `Fiber`, not a `Result`, so when the runtime could not allocate a
fiber's stack the caller was handed a handle to nothing. Measured on a
4 MiB unikernel guest, a program that asked for 200 fibers got eleven,
printed the count of the eleven as though that were the answer, and
exited 0. Both runtimes now print

```text
nurl: cannot create a fiber — out of memory for its stack (11 live)
```

and abort, the way the runtime already aborts when `malloc` fails — a
fiber's stack is an allocation like any other, and "this machine is too
small for this program" is a thing to say rather than to hide. Budget
**68 KiB per fiber** (a 64 KiB stack and a 4 KiB guard page) when
sizing a machine.

## 6. Design lineage

The shape pulls from Go's M:N scheduler, Boost.Fiber's runtime API
contour, and BEAM's "each task is a tiny stack" discipline. The major
deviation from Go: no movable stacks. NURL accepts the fixed
stack-per-fiber memory cost in exchange for *no* compiler machinery for
stack relocation — which is what keeps arbitrary existing code legal
inside a fiber.

---

## Operational caveats

The fiber runtime is designed to look and feel like ordinary code (no
`async`/`await` colouring), but a few platform and usage realities leak
through. None of these are *language* surprises the compiler can diagnose —
they are runtime/operational notes; the compiler's own diagnostics cover the
source-level traps.

- **One async call flips the handle to non-blocking.** Once any of
  `tcp_accept_async` / `tcp_read_chunk_async` / `tcp_write_all_async` runs on
  a `TcpListener` / `TcpConn`, the underlying socket has `O_NONBLOCK` set. A
  subsequent **sync** call on the same handle from a non-fiber context then
  surfaces `EAGAIN` as `NetTimeout`. Stay in async mode for that handle, or
  call `tcp_set_nonblock_*` to flip it back.
- **`runtime_run` blocks until `pending = 0`.** Every un-reaped `spawn` (the
  fire-and-forget shape) bumps the pending count; every fiber that runs to
  completion decrements it. A long-running accept fiber that never returns
  keeps `runtime_run` blocked forever — which is exactly what a server wants.
  Call `server_stop` / `runtime_shutdown` to stop on demand, or
  `server_drain s deadline_ms` for a graceful stop that also closes idle
  keep-alive connections (their fibers would otherwise wait out the idle
  timeout) and bounds the wait for requests in flight.
- **A spawned closure moves what it captures.** A `: ~` by-reference
  capture may not reach a `spawn` closure, as for `thread_spawn` (see
  [`MEMORY.md` §2.3](MEMORY.md)); for shared mutable state across fibers
  use a `( Locked T )` (e.g. `( Locked ( Vec i ) )`) or a `Channel` rather
  than a stack struct — an `Arc` is for a value nobody changes.

### Implementation notes (runtime maintainers)

- **TLS reads must stay un-inlined under LTO.** Any `runtime.c §24` function
  that reads `nurl__tls_worker` carries `__attribute__((noinline))`:
  cross-TU inlining of a `__thread` access under `clang -O2 -flto` lowers the
  segment-register-relative load incorrectly, returning a stale/NULL worker
  pointer (symptom: `nurl_fiber_current` returns 0 inside a resumed fiber, so
  fiber-aware `tcp_accept` falls through to the blocking path and surfaces
  `NetTimeout`). A new TLS-reading runtime entry point must be annotated the
  same way.
- **The spin-then-park window is learned per fiber.**
  `nurl__reactor_wait` may probe the fd before paying a park
  (`nurl__spin_ready`). Each fiber keeps an estimate of how long its I/O
  waits take — every wait counts, a spin that caught the fd and a park
  alike — and spins only while that estimate is below the cap, for twice
  the estimate plus a margin (the whole cap before it has one). A
  closed-loop peer (c=1, plaintext or TLS) answers within the window
  and skips the park — ~28 k req/s at c=1 against ~12 k without the spin
  — while a client with think time, an idle keep-alive connection or a
  listener stops being spun on after a wait or two. The window used to be
  a fixed 256 poll(2) calls (80–250 µs, by the machine's syscall cost)
  on every wait, which at 500–2000 req/s on one connection cost 235–484
  µs of CPU per request; it is 72–84 µs now (tokio: 65–76). The cap is
  `NURL_SPIN_US` (µs; 0 = never spin), else 100 µs, else 0 under a
  cgroup CPU quota or with one usable CPU; and only a runtime with at
  most 4 live fibers spins at all, so a loaded server does not burn
  cores.
- **Park-vs-unpark ordering.** `nurl__reactor_wait` fills the wait
  entry but does not publish it; the worker loop hands it to
  `nurl__reactor_activate` only after the parking fiber's context
  switch completes, so an unpark cannot fire before the context is
  fully saved. On Linux the activation IS the point the entry becomes
  matchable (chain insert / ready-bit consume under the netpoller
  lock); on the poll(2) backend it flips the entry's `active` flag.
  Channel-coordinated parks use the symmetric `pending_unlock`
  deferral.
- **The netpoller's edge-triggered contract.** A wait may only follow
  an `EAGAIN` (or a short write) on that fd — that is what makes a
  banked ready bit trustworthy and a missed edge impossible. Every
  `stdlib` async wrapper already has this shape (try, then wait);
  a new wrapper must keep it. The reverse order (wait first, then
  read) can hang under `EPOLLET`: data still in the buffer delivers
  no new edge.
