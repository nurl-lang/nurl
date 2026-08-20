# Async runtime — stackful fibers, no function colouring

NURL ships an **M:N stackful-fiber runtime**: many lightweight fibers
multiplex onto a small pool of OS worker threads, with an I/O reactor
that parks a fiber on a socket and resumes it when the socket is ready.
The defining property is **no function colouring** — there is no
`async` keyword, no `await`, no split between sync and async functions.
Ordinary code runs unchanged inside a fiber; blocking I/O calls become
cooperative automatically when invoked from fiber context.

```
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
- **Reactor.** One dedicated thread runs a `poll(2)` loop plus a timer
  wheel. A fiber that would block on a socket registers the fd and
  parks; the reactor unparks it when the fd is ready or the timeout
  fires. (`poll(2)` is POSIX-portable; an `epoll`/`kqueue` backend is a
  known upgrade path if a 10k-connection consumer appears.)

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

`packages/http` exposes this as **`http_app_async n`** — fiber per
connection, `n` worker pthreads, `0` meaning one per core.

## 4. Semantics worth knowing

- **`runtime_run` waits for pending = 0.** Every `spawn` bumps a pending
  count; every completed fiber decrements it. A server's accept fiber
  keeps the count non-zero on purpose — stop it via `server_stop` /
  `runtime_shutdown`.
- **Spawn is not a thread.** The closure runs on some worker's fiber; a
  CPU-bound fiber that never yields occupies its worker until it does.
  `yield` inside long computations keeps latency flat.
- **Crossing fibers follows the same ownership rules as threads.** The
  borrow checker's escape analysis applies to `spawn` closures like
  `thread_spawn` ones; shared mutable state belongs behind a heap-backed
  handle (see [Operational caveats](#operational-caveats)).

## 5. Platform support

Fibers need pthreads, `mmap`, and a stackful context switch. The switch
has two backends:

- **`stdlib/runtime_ctx.c`** — NURL's own, in x86_64 SysV asm. It
  depends on the instruction set alone, so it needs no libc support at
  all, and it does not pay `swapcontext`'s `sigprocmask` syscall: 8 M
  yields through the scheduler take 0.38 s against ucontext's 6.90 s,
  with `sys` time going from 2.1 s to zero.
- **`ucontext`** (`getcontext`/`makecontext`/`swapcontext`) — everywhere
  else, on the libcs that ship a working one.

| Platform | Fibers |
|---|---|
| Linux x86_64 (glibc **or musl**) | ✔ own switch |
| macOS x86_64 | ✔ own switch |
| Linux/macOS arm64, FreeBSD / NetBSD / DragonFly | ✔ ucontext |
| OpenBSD | stubbed (removed `swapcontext`) |
| Windows, WASI | stubbed |

The reactor is POSIX-only (`poll(2)`); it starts only where fibers are
enabled.

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

```
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
  Call `server_stop` / `runtime_shutdown` to drain on demand.
- **Capturing a stack-borrowed pointer in a spawned closure** is the same
  hazard as `thread_spawn`. The borrow checker's escape analysis catches the
  documented shapes (see [`MEMORY.md` §2.3](MEMORY.md)); for shared mutable
  state across fibers use a heap-backed handle (`Mutex` + `Vec[i]`, …) rather
  than a `: ~`-captured stack struct.

### Implementation notes (runtime maintainers)

- **TLS reads must stay un-inlined under LTO.** Any `runtime.c §24` function
  that reads `nurl__tls_worker` carries `__attribute__((noinline))`:
  cross-TU inlining of a `__thread` access under `clang -O2 -flto` lowers the
  segment-register-relative load incorrectly, returning a stale/NULL worker
  pointer (symptom: `nurl_fiber_current` returns 0 inside a resumed fiber, so
  fiber-aware `tcp_accept` falls through to the blocking path and surfaces
  `NetTimeout`). A new TLS-reading runtime entry point must be annotated the
  same way.
- **The spin-then-park window is sized for a TLS peer.**
  `nurl__reactor_wait` spins before paying the two-thread park/wake
  chain. That window was 64 probes (~25 µs), which a plaintext HTTP peer
  answers inside but a TLS turnaround (decrypt + handle + encrypt,
  ~35–45 µs on loopback) does not — so every keep-alive HTTPS request at
  low concurrency missed the spin and ate a full park. It is 256 probes
  since 0.46.0, and gated to ≤ 4 live fibers so a loaded server does not
  burn cores spinning. Changing either number moves the low-concurrency
  HTTPS cell in `bench/HTTP_RESULTS.md` and nothing else.
- **Reactor park-vs-unpark ordering.** `nurl__reactor_wait` registers the
  wait entry with `active = 0`; the worker loop flips it via
  `nurl__reactor_activate` only after the parking fiber's `swapcontext`
  completes, so an unpark cannot fire before the context is fully saved.
  Channel-coordinated parks use the symmetric `pending_unlock` deferral.
