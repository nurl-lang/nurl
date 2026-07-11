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

- **Stackful.** Each fiber owns a real (mmap'd) stack, switched with
  `ucontext` — so *any* existing function can yield anywhere beneath any
  call depth. No compiler transformation, no state machines, no
  colouring. The cost is memory per fiber (fixed-size stacks) instead of
  Go-style movable stacks; the benefit is that every existing nurlc IR
  pattern works unchanged.
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
server on fibers: an accept fiber spawns one fiber per connection;
keep-alive, the request-line timeout and the DoS limits work as under
the thread pool. It returns when the listener closes and the fiber pool
drains.

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

Fibers need `ucontext` (`getcontext`/`makecontext`/`swapcontext`). The
runtime enables them where that is reliable and **stubs them
elsewhere** — on a stubbed platform `spawn` and the `*_async` calls
degrade transparently to their blocking forms, so the same program
still runs (just without fiber concurrency).

| Platform | Fibers |
|---|---|
| Linux (glibc) | ✔ ucontext |
| macOS | ✔ ucontext (`_XOPEN_SOURCE`) |
| FreeBSD / NetBSD / DragonFly | ✔ ucontext |
| Linux (musl), OpenBSD | stubbed (musl ships deprecated-removed ucontext) |
| Windows, WASI | stubbed |

The reactor is POSIX-only (`poll(2)`); it starts only where fibers are
enabled.

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
- **Reactor park-vs-unpark ordering.** `nurl__reactor_wait` registers the
  wait entry with `active = 0`; the worker loop flips it via
  `nurl__reactor_activate` only after the parking fiber's `swapcontext`
  completes, so an unpark cannot fire before the context is fully saved.
  Channel-coordinated parks use the symmetric `pending_unlock` deferral.
