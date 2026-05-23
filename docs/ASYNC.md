# Async Runtime — Design & Phased Implementation Plan

> **Status (2026-05-23): Design only — no code shipped yet.**
> This document is the design for adding *stackful M:N work-stealing
> fibers* to NURL. It precedes any `runtime.c` change so the API and
> runtime shape can be reviewed in one place.
>
> Closes the open ROADMAP.md §1 item "Async/Await Design" and the
> critic.md §5 critique ("no panic / unwind model … no effect system,
> no async/await, no Future\[T\]. Concurrency today is raw threads and
> channels").
>
> Same structure as `HTTP_SERVER_PLAN.md` and `BORROW.md`: each phase is
> independently testable, leaves the tree green, and documents what the
> previous phase set up. Bootstrap fixed point must hold after every
> phase.

---

## Part I — The Decision: stackful M:N, not stackless async/await

### I.1  Why a concurrency upgrade now

NURL today exposes `thread_spawn` + `Channel[A]` + `Mutex` + `Cond`
(`stdlib/std/thread.nu`, `stdlib/std/channel.nu`). The HTTP server runs
in `server_run_pool` with N pthreads each blocking on `accept` — a
thread-per-connection model. This works for ~hundreds of conns; it
falls over at the 10k-conn scale where every modern AI gateway,
reverse-proxy, and SSE fan-out lands. Three concrete forcing functions:

1. **MCP fan-out.** A single MCP HTTP server hosting tools that fan out
   to multiple upstream LLM endpoints needs concurrent streaming I/O
   per request — N pthreads × M upstream streams scales poorly.
2. **Reverse-proxy / SSE pass-through** (`stdlib/ext/http_proxy.nu`).
   Each forwarded stream parks a worker thread blocked on libcurl
   multi; with async I/O the same worker can drive thousands of
   streams.
3. **NURL on resource-constrained targets.** The Milk-V Duo
   (`[[project-milkv-duo]]`) has 29 MB RAM total — pthread stacks at 2
   MB each cap the server at ~10 concurrent connections. Fibers with
   64 KB stacks lift that ceiling 30×.

### I.2  Two paths considered

| Aspect | Stackful fibers (chosen) | Stackless async/await |
|---|---|---|
| Compiler change | None — pure runtime + stdlib | Major: lower async fn → state machine |
| Function coloring | None — any fn can yield | `async fn` / `await` viral |
| Per-task memory | 64 KB stack default | ~hundreds of bytes |
| Context switch cost | ~50 ns (ucontext/swapcontext or asm) | ~5 ns (state-machine resume) |
| Composes with closures | Directly — closure = fiber body | Closures need their own state-machine lowering |
| Composes with `Channel[A]` | Drop-in: park fiber instead of cond_wait | Requires per-channel waker registry |
| Compiler-quirk surface | Zero (runtime-only) | High (every `async`/`await` site is a new gen* path) |
| Maintenance cost (bus factor 1) | Low | High |
| WASI support | Hard (no ucontext) — needs Asyncify or stub | Same single-threaded loop everywhere |
| Stack overflow detection | Guard page (mmap PROT_NONE) → SIGSEGV | N/A — fixed slot |

### I.3  Decision: stackful M:N work-stealing from day 1

**Stackful kuidut.** No function coloring is the deciding factor — NURL's
anti-ceremony surface would suffer if every IO-using stdlib function had
to be marked `async`, duplicated, or hidden behind a coloured-call site.
A `( read_file path )` should be a `read_file` regardless of whether the
caller is running on a fiber or directly on an OS thread.

**M:N alusta.** A single-threaded executor would be simpler for phase 1,
but every consumer (HTTP server, MCP HTTP, reverse proxy) wants real
parallelism, and retrofitting work-stealing onto a single-runqueue
scheduler tends to leak abstractions (the runqueue type changes shape;
the steal protocol mints a new public concept; existing tests pin the
pthread count at 1). Cheaper to design the M:N shape once.

**Channel[A] dual-mode.** Existing OS-thread callers of `chan_send`/
`chan_recv` (the `stdlib/std/thread.nu` consumers) keep the existing
mutex+cond path. New fiber callers park on the channel's fiber wait
queue. The Channel implementation detects which mode by checking the
current OS thread's fiber-scheduler-attached flag.

**The accepted cost.** ucontext is deprecated POSIX (works on glibc,
absent on musl). The plan ships a small x86_64 / aarch64 / riscv64
context-switch assembly fallback (~30 LOC per arch) for the
non-glibc case. ucontext is still the path-of-least-resistance for the
first phase.

---

## Part II — Architecture

### II.1  Object model

```
┌─────────────────────────────────────────────────────────────────────┐
│ NurlScheduler (one per process; lives for the lifetime of nurl_main)│
│                                                                     │
│  ┌───────────────────┐  ┌───────────────────┐  ┌─────────────────┐  │
│  │ Worker 0          │  │ Worker 1          │  │ … Worker N-1    │  │
│  │  - pthread        │  │  - pthread        │  │                 │  │
│  │  - runqueue deque │  │  - runqueue deque │  │                 │  │
│  │  - current fiber  │  │  - current fiber  │  │                 │  │
│  └───────────────────┘  └───────────────────┘  └─────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Reactor (one pthread, epoll/kqueue/IOCP)                     │   │
│  │  - parked-on-fd table:  fd → fiber                           │   │
│  │  - timer wheel:          deadline → fiber                    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ Global state                                                 │   │
│  │  - global runqueue (overflow target for steal pressure)      │   │
│  │  - park condvar (workers sleep here when local + steal fail) │   │
│  │  - shutdown flag                                             │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

A **fiber** is a (stack, context, state) triple:

```c
typedef enum { FS_NEW, FS_RUNNING, FS_RUNNABLE, FS_PARKED, FS_DONE } FiberState;

typedef struct NurlFiber {
    ucontext_t       ctx;       /* saved registers (POSIX) */
    void            *stack;     /* mmap'd, 64 KB default, guard page below */
    size_t           stack_sz;
    void           (*fn)(void*);/* fiber body — closure_fn_ptr */
    void            *env;       /* closure env_ptr */
    FiberState       state;
    struct NurlFiber*park_next; /* intrusive list link (channel wait queue, reactor table) */
    /* completion + join */
    long long        result;    /* spawn_with_result captures Future[T] payload here */
    int              joinable;  /* if joinable, scheduler does not free until joined */
    int              done_signaled;
    pthread_mutex_t  join_m;
    pthread_cond_t   join_c;
} NurlFiber;
```

A **worker** owns one *runqueue deque* (Chase-Lev wait-free, push/pop
the local end, steal from the foreign end). Workers run the **work loop**:

```
loop:
    f = local_runqueue.pop()              # local end, single-threaded fast path
    if f == NULL:
        f = try_steal_from_random_peer()  # foreign end of peer's deque
    if f == NULL:
        f = global_runqueue.pop()
    if f == NULL:
        park_on_global_condvar()           # woken by spawn or reactor-readiness
        continue
    switch_to(f)                           # ucontext_swap into the fiber
    # control returns here when the fiber yields or completes
    if f.state == DONE:
        if f.joinable: signal join_cond; else: free(f)
    elif f.state == PARKED:
        # park target (channel / reactor / sleep) has the linkage; we drop it
        pass
    else: # FS_RUNNABLE
        local_runqueue.push(f)
```

### II.2  Yielding and parking

Three primitives, all live on the fiber's stack while the worker's stack
holds the loop above:

- **`yield`** — fiber sets state RUNNABLE, swaps back to worker; worker
  re-pushes it onto the local runqueue (cooperative round-robin).
- **`park(reason)`** — fiber sets state PARKED, swaps back to worker;
  worker drops the reference. *Some other code path* must call
  `unpark(fiber)` later, which pushes it back onto a runqueue.
- **`exit`** — fiber sets state DONE, swaps back to worker; worker
  signals the join condvar (if joinable) or frees the slot.

`unpark(fiber)` is the single re-entry point. Channels, reactor, and
timers all call it. It pushes to:
1. The fiber's *origin* worker's local runqueue if that worker is
   currently parked on the global condvar (helps locality).
2. The global runqueue otherwise (lets a less-busy peer grab it via
   steal).

### II.3  Channel parking (II.5 detail)

`stdlib/std/channel.nu` today: `chan_recv` calls `cond_wait` while the
queue is empty. The new dual-mode flow:

```
chan_recv(ch):
    lock(ch.m)
    while queue.empty AND !closed:
        if current_thread_has_fiber():
            # park the calling fiber on this channel's wait queue
            push(ch.recv_waiters, current_fiber)
            unlock(ch.m)
            park(REASON_CHANNEL_RECV)
            lock(ch.m)               # reacquired on resume
        else:
            cond_wait(ch.c, ch.m)    # legacy pthread path
    ...

chan_send(ch, v):
    lock(ch.m)
    if !closed:
        push(ch.q, v)
        if !ch.recv_waiters.empty:
            unpark(pop(ch.recv_waiters))
        cond_signal(ch.c)            # also wake legacy threads
    unlock(ch.m)
```

Key invariant: a parked fiber holds *no locks*. The channel mutex is
released before `park()` and reacquired on resume. This is the same
discipline as `pthread_cond_wait`.

### II.4  I/O reactor

One reactor thread per process owns the epoll/kqueue/IOCP descriptor.
The async I/O wrappers (`tcp_read_async` etc.) attempt the syscall
non-blocking; on EAGAIN/EWOULDBLOCK they register `(fd, event)` →
`current_fiber` and `park()`. The reactor thread runs:

```
loop:
    timeout = min(timer_wheel.next_deadline_ms, INFINITE)
    n = epoll_wait(epfd, events, MAX, timeout)
    for ev in events[:n]:
        fiber = parked_by_fd[ev.fd]
        epoll_ctl(epfd, DEL, ev.fd)        # one-shot — re-register on next park
        unpark(fiber)
    drain_expired_timers()                  # unpark each timer's fiber
```

Edge-triggered + one-shot per registration gives us the simplest
correctness story: each park is a fresh registration, no leftover
events between operations.

Cross-platform abstraction (`runtime.c §24` new):

| API           | Linux                  | macOS                  | Windows         |
|---------------|------------------------|------------------------|-----------------|
| reactor_new   | `epoll_create1`         | `kqueue`                | `CreateIoCompletionPort` |
| reactor_arm   | `epoll_ctl(ADD, ONESHOT)`| `EV_SET(ADD\|ONESHOT)`  | `WSARecv` + OVERLAPPED   |
| reactor_wait  | `epoll_wait`            | `kevent`                | `GetQueuedCompletionStatusEx` |

WASI: stub everything to ENOTSUP. WASI threads aren't widely deployed
yet; the WASI build keeps the single-threaded blocking path.

### II.5  TLS integration

OpenSSL non-blocking mode raises `SSL_ERROR_WANT_READ` /
`SSL_ERROR_WANT_WRITE` from `SSL_read`/`SSL_write`/`SSL_accept`. The
async wrapper interprets these exactly like EAGAIN — arm the reactor
for the corresponding direction, park, resume. No SSL session state
changes between resume cycles; OpenSSL is designed for this.

The polymorphic `NurlTcp` from `runtime.c §18` already routes through
SSL when present. Adding `tcp_*_async` is one branch per primitive,
not a parallel SSL implementation.

---

## Part III — API surface

### III.1  Pure-NURL stdlib (`stdlib/std/async.nu`)

```
: Fiber { s ctl }                          // opaque handle

@ spawn ( @ v ) body → Fiber
@ spawn_joinable ( @ v ) body → Fiber      // joinable; not freed until joined
@ yield → v
@ sleep_ms i ms → v                        // park current fiber for ≥ ms
@ join Fiber f → v                         // block (or park) until f exits
@ runtime_init → v                         // call once at program start (idempotent)
@ runtime_run → v                          // drain all runnable fibers; returns when scheduler idle
@ runtime_shutdown → v                     // wake every parked fiber with cancellation
```

Result-returning spawn (built on join):

```
: Future [T] { Fiber f, *T result_slot }

@ spawn_with_result [T] ( @ T ) body → ( Future T )
@ future_await [T] ( Future T ) fut → T
@ future_free [T] ( Future T ) fut → v
```

### III.2  Async I/O primitives (`stdlib/std/net.nu` additions)

Mirror the existing sync API one-to-one. Same `NetErr` enum, same
`TcpConn`/`TcpListener` handles.

```
@ tcp_accept_async TcpListener → ! TcpConn NetErr
@ tcp_read_chunk_async TcpConn i max → ! ( Vec u ) NetErr
@ tcp_write_all_async TcpConn ( Vec u ) → ! v NetErr
@ tcp_connect_async s host i port i timeout_ms → ! TcpConn NetErr
@ tls_connect_async s host i port i timeout_ms → ! TcpConn NetErr
```

Behaviour: from a non-fiber context (no scheduler attached), every
`*_async` falls back to its blocking counterpart with a debug-log
warning. Calling code never has to check the context.

### III.3  HTTP server async path (`stdlib/ext/http_server.nu`)

```
@ server_run_async HttpServer → ! v NetErr
```

Same handler contract as `server_run` / `server_run_pool`
(`( @ HttpResponse HttpRequest )`). The implementation:

1. One *accept fiber* per listener.
2. Per accepted conn: spawn a *conn fiber* running the existing
   keep-alive loop, but with `tcp_read_chunk_async` and
   `tcp_write_all_async` in place of the blocking variants.
3. Per-conn idle timeout: a paired *timer fiber* that does
   `sleep_ms`, then on wake checks an atomic `last_activity_ms` and
   either re-arms or kills the conn fiber via cancellation.
4. Graceful shutdown via `signal_install_shutdown` triggers
   `runtime_shutdown` after the listener closes; in-flight fibers
   drain their current request, then exit.

### III.4  Function-coloring? Not in the surface

The whole point of stackful is that `( read_file path )` from inside a
fiber does what it always did. There is **no** `async` keyword, **no**
`await` operator, **no** parallel `async fn` declaration. The runtime
detects fiber-ness via `pthread_getspecific` of a per-thread "current
fiber" slot. If the slot is non-NULL, async wrappers may park; if NULL,
they call the blocking variant.

The two-page mental model: `spawn(closure)` puts the closure on a
fiber; everything else looks like normal NURL.

---

## Part IV — Memory model & ownership

### IV.1  Fiber stack lifetime

A fiber's stack is a separate `mmap` region. When the fiber's body
function returns or the scheduler frees the fiber, the stack is
`munmap`'d. **Implication:** any pointer into the fiber's stack
becomes dangling on fiber exit. This is the same rule as a returned
function's stack — nothing new for NURL programmers.

### IV.2  Owned-pointer auto-drop

Auto-drop is woven into the fiber body's IR exactly as for an ordinary
function: NURL's `gen_ret` and scope-exit logic don't know they're
running on a fiber. Heap allocations made during the fiber's execution
are dropped at the fiber's scope exits as usual. The compiler is
fiber-agnostic.

### IV.3  Capture-by-pointer (`: ~` mutable struct in closure)

The existing `BORROW.md` Phase 3 escape-analysis warning already
covers the dangerous shape — a `: ~`-mutable struct captured by
pointer into a closure that escapes via `vec_push`/`thread_spawn`/
return. The new `spawn` adds one more name to the warning's
recognised-shape list. *No new safety hole.*

### IV.4  Cancellation

`runtime_shutdown` sets each fiber's `cancel_requested` flag and
unparks every parked fiber. On resume, parked async I/O wrappers
detect the flag and return `NetCancelled` (new NetErr variant). The
fiber's body then unwinds normally — its scope-exit drops fire as
usual. **No abrupt termination, no leaked allocations.**

### IV.5  Channel send/recv ownership

Unchanged from the current Channel[A] design. Owned payloads transfer
via the queue. The parked-fiber path adds no new ownership transition
— the value lands in `ch.q` exactly as before, just under a different
mutex hold pattern.

---

## Part V — Phased implementation

### Phase 0 — Design doc (this document)

**Acceptance:** `docs/ASYNC.md` reviewed, decision recorded, blocking
items for downstream phases identified.

### Phase 1 — Core fiber primitives (runtime.c §24, single-thread)

Lay the foundation: context switch, stack lifecycle, single-thread
round-robin scheduler. No I/O, no work-stealing yet.

**Runtime additions (`stdlib/runtime.c §24` new):**

```c
long long nurl_fiber_spawn(void *fn, void *env);    /* → fiber handle */
void      nurl_fiber_yield(void);
void      nurl_runtime_init(int worker_count);      /* worker_count ignored in phase 1 */
void      nurl_runtime_run(void);                   /* drain to idle */
void      nurl_runtime_shutdown(void);
long long nurl_fiber_current(void);                 /* → handle or 0 */
```

**Stack lifecycle:** `mmap(64KB + 4KB guard)` with `PROT_NONE` on the
guard page; `munmap` on fiber exit. ucontext_t for save/restore via
`makecontext`/`swapcontext`.

**Acceptance:** `compiler/tests/async_basic.nu` spawns 100 fibers each
yielding 1000 times, checks all 100 000 yields execute and every fiber
completes. Compile-time fixed point holds.

### Phase 2 — NURL surface (`stdlib/std/async.nu`)

Pure-NURL wrappers over the Phase-1 runtime. `Fiber { s ctl }` handle;
`spawn`, `yield`, `runtime_init`, `runtime_run`. No `join`, no
`Future[T]` yet — those need Phase 3's joinable fibers.

**Acceptance:** `examples/async_yield.nu` demo runs end-to-end. Pure
stdlib — compiler untouched.

### Phase 3 — M:N work-stealing scheduler

Worker pool, per-thread deques, Chase-Lev steal. Atomic CAS for the
steal protocol. `NURL_WORKERS` env (default = `sysconf(_SC_NPROCESSORS_ONLN)`).

Adds **joinable fibers**: `spawn_joinable` returns a handle that
survives the fiber's exit; `join` blocks on a per-fiber condvar. From
inside a fiber, `join` parks instead of blocking.

**Acceptance:** Spin up 100k joinable fibers each computing
`fib(20)` then yielding 10 times; all complete; output is correct;
load distribution across workers is within 2× of even. Bootstrap fixed
point holds.

### Phase 4 — Channel[A] async integration

Modify `chan_send` / `chan_recv` / `chan_try_recv` so the wait queues
hold `*NurlFiber` pointers when called from a fiber context, and
`unpark(fiber)` on the wake side. Existing pthread-only callers
(every test in the corpus) keep their cond_wait path.

**Acceptance:** Ping-pong: two fibers exchange 1M `i` values over a
Channel\[i\] in under 1 second on a modern x86_64. Existing
`compiler/tests/channel_basic.nu` and the thread+channel HTTP server
tests still pass byte-for-byte.

### Phase 5 — I/O reactor (epoll/kqueue/IOCP)

Reactor thread, parked-on-fd table, timer wheel. Cross-platform
abstraction in `runtime.c §24` (extends Phase-1 section).

**Acceptance:** A NURL program creates two pipes, spawns one fiber per
pipe to read forever, spawns one writer fiber per pipe writing 1000
messages then closing; the reader fibers see exactly 1000 messages
each and EOF. Verified ASan/UBSan-clean.

### Phase 6 — Async TCP/TLS primitives

`tcp_accept_async`, `tcp_read_chunk_async`, `tcp_write_all_async`,
`tcp_connect_async`, `tls_connect_async`. OpenSSL `SSL_ERROR_WANT_*`
routed through the same park path as plain socket EAGAIN. Add
`NetErr::NetCancelled` for cancellation-on-shutdown.

**Acceptance:** Echo server using `tcp_accept_async` +
`tcp_read_chunk_async` + `tcp_write_all_async` handles 10k concurrent
loopback connections with each connection echoing 100 messages —
total ~1M messages, no leaks under ASan, sub-second wall time.
`NURL_NET_TESTS=1` gated.

### Phase 7 — HTTP server async path (`server_run_async`)

New entry point in `stdlib/ext/http_server.nu`. Same handler contract
as `server_run`. Per-conn fiber + per-conn timer fiber. Graceful
shutdown via `runtime_shutdown` after the listener closes.

**Acceptance:** `examples/async_http_server.nu` (HTTP version of
`examples/static_server.nu`) serves 10k concurrent keep-alive
connections; throughput compared against `server_run_pool` baseline.
Benchmark recorded in `docs/ASYNC.md` Part VII.

### Phase 8 — Examples, docs, gotchas, bootstrap check

- `examples/async_echo.nu` — minimal echo server
- `examples/async_http_server.nu` — full HTTP server
- `examples/async_ping_pong.nu` — Channel\[A\] benchmark
- `docs/GOTCHAS.md` — new fiber-specific traps (e.g., capturing a
  stack-allocated struct into a spawned closure)
- `README.md` — Concurrency Model section rewrite
- Bootstrap fixed point: stage1 ≡ stage2 byte-identical IR across the
  whole change
- Sanitiser sweep: 0 SAN_FAIL across the full corpus

---

## Part VI — Cross-platform & WASI notes

### VI.1  POSIX (Linux, macOS, BSD)

- ucontext_t for context switch. Works on glibc; absent on musl.
- For musl (and as a faster path for everyone) Phase 1+ ships an
  assembly switch for x86_64 (~30 LOC), aarch64 (~30 LOC), riscv64
  (~30 LOC). Selection is `#if defined(__GLIBC__) ? ucontext : asm`.
- Stack guard via `mmap(64KB + 4KB, PROT_NONE)` then
  `mprotect(stack, 64KB, PROT_READ|PROT_WRITE)` — stack overflow
  becomes SIGSEGV with a deterministic faulting page.

### VI.2  Windows

- `CreateFiber` + `SwitchToFiber` Win32 API gives stackful fibers
  natively. No assembly needed.
- IOCP for the reactor — different shape from epoll/kqueue
  (completion-based, not readiness-based), so the reactor abstraction
  hides this behind a single `wait_for_completions` call.

### VI.3  WASI

- No threads, no fibers, no epoll.
- `nurl_fiber_spawn` returns 0 (failure) on WASI; `runtime_run` is a
  no-op; `*_async` wrappers fall back to the blocking sync path. The
  language surface compiles; programs that *require* concurrency
  produce a clear "WASI: async runtime unsupported" runtime error
  rather than a build failure.
- Asyncify is on the table as a future ship if and when WASI threads
  become widely deployed.

### VI.4  Milk-V Duo (riscv64 Linux, 29 MB RAM)

- Plenty of headroom for the asm context switch (one of the three
  arches above).
- 64 KB stacks × 100 fibers = 6.4 MB — fits comfortably.
- epoll works on the C906 kernel; reactor compiles as-is.
- Async HTTP server on Duo is the headline use case.

---

## Part VII — Open questions

These are real questions the design intentionally leaves to
implementation time. Listed so a reviewer can flag a preferred answer
now.

1. **Default `NURL_WORKERS` floor.** Pinned at
   `sysconf(_SC_NPROCESSORS_ONLN)`? Capped at 8? Capped at the user's
   `ulimit -u` (max threads)? *Suggested:* `min(ncpu, 16)` with env
   override.

2. **Fiber stack size default.** 64 KB is conservative; Go starts at 8
   KB with growth. Without stack growth (NURL has no movable-stack
   support and the existing GC-free model makes adding it expensive),
   64 KB is safer. *Suggested:* 64 KB default, `NURL_FIBER_STACK_KB`
   env override.

3. **Cancellation: kill point granularity.** Phase 4 routes
   cancellation through async I/O return values. Pure-CPU loops never
   notice. Do we add a periodic `yield`-checks-cancel point? Go
   inserts cancel-check at every function preamble. *Suggested:* leave
   it to the I/O surface in v1; revisit if real workloads block.

4. **Channel-on-fiber send blocking on a full bounded channel.** The
   existing Channel\[A\] is unbounded. If we add `Bounded[A]` later,
   send-side park needs the same protocol. *Suggested:* defer until
   bounded channels are actually requested.

5. **`Future[T]` for multi-field T.** The heap-box path for multi-field
   `! T E` already exists. `Future[T]`'s `result_slot` can reuse it —
   single allocation per future. *Decision implied:* yes.

6. **Detached fibers and process exit.** If `main` returns while
   detached fibers are still running, do we wait or kill? *Suggested:*
   `runtime_run` returns only when every spawned fiber has exited.
   Background work needs `spawn_detached` (a flag) with a documented
   "you opted into this" caveat.

7. **Reactor thread on WASI.** Stub. No reactor, no async I/O.

8. **Compile-time gate for fiber support.** Should there be a build
   flag `--no-async` that drops every fiber primitive from the
   runtime, for users targeting truly embedded systems where mmap +
   pthread is unavailable? *Suggested:* yes — same shape as
   `BORROW.md`'s `--no-borrowck`, sentinel-checked at the FFI declaration
   site.

---

## Part VIII — Estimated scope

| Phase | NURL LOC | C LOC  | Cumulative |
|------:|---------:|-------:|-----------:|
|     1 |        0 |    600 |        600 |
|     2 |      150 |     20 |        770 |
|     3 |       50 |    700 |      1 520 |
|     4 |       80 |     50 |      1 650 |
|     5 |       30 |    700 |      2 380 |
|     6 |      300 |    150 |      2 830 |
|     7 |      400 |      0 |      3 230 |
|     8 |      600 |      0 |      3 830 |

Total: ~3 800 LOC across ~2 NURL stdlib modules, ~1 runtime section,
and ~3 examples. Comparable in size to the HTTP server roll-up
(2 000–3 000 LOC across 8 phases).

---

## Part IX — Comparison & inspiration

| Project | Model | Worker pool | I/O | Notes |
|---|---|---|---|---|
| Go | Stackful (goroutines) | M:N work-stealing | netpoller (epoll/kqueue) | Movable stacks; we don't replicate |
| Erlang/BEAM | Stackful processes | M:N | Asynchronous via `gen_tcp` + scheduler | Per-process heap; we share heap |
| Rust Tokio | Stackless `async`/`await` | M:N | Mio (epoll/kqueue) | Function coloring; we avoid |
| Lua coroutines | Stackful, single-thread | M:1 | None | No I/O integration; design starting point |
| libuv | C-side callbacks | Single-thread loop | epoll/kqueue/IOCP | Callback hell motivates fibers |
| Boost.Fiber | Stackful, M:N | M:N | Conditional | Closest analog to our shape |

NURL's design pulls from Go's `M:N` scheduler shape, Boost.Fiber's
runtime API contour, and BEAM's "each task is a tiny stack" memory
discipline. The major deviation from Go: no movable stacks. We accept
the 64 KB-per-fiber memory cost in exchange for *no* compiler magic
for stack-relocation safepoints — every existing nurlc IR pattern
continues to work unchanged.

---

*Last updated: 2026-05-23 — initial draft.*
