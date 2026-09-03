// stdlib/std/async.nu — Stackful fiber primitives (Phase 1 + 2)
//
// Pure-NURL wrapper over the `runtime.c §24` async runtime. Phase 1
// shipped a single-thread round-robin scheduler with ucontext-based
// context switch and mmap'd 64 KB stacks with a 4 KB guard page below
// (POSIX). Windows and WASI return failure / no-ops until Phase 3.
//
// API:
//
//   ( spawn            ( @ v ) body )    → Fiber
//   ( yield )                             → v   (cooperative reschedule)
//   ( fiber_current )                     → ? Fiber
//   ( runtime_init     i workers )        → v   (Phase 1: workers ignored)
//   ( runtime_run )                       → v   (drain to scheduler idle)
//   ( runtime_shutdown )                  → v   (stop the run loop)
//
// Memory model:
//
//   * Fiber is an opaque single-pointer handle (`{ s ctl }`). The
//     scheduler owns the fiber's stack and control block; the runtime
//     frees them when the fiber's body returns. Do NOT call
//     `nurl_free` on a Fiber handle.
//   * `spawn` BORROWS the closure value and the captured env it points
//     at. The closure (and its env heap allocation) MUST OUTLIVE the
//     fiber's execution — typical pattern is to hold it in a local
//     binding through `runtime_run` and free both afterwards.
//   * From inside a fiber, `yield` parks the current fiber at the back
//     of the runqueue and returns when the scheduler reschedules it.
//     `runtime_run` returns only when every spawned fiber has exited.
//   * From OUTSIDE a fiber (e.g. main thread before `runtime_run`),
//     `yield` is a no-op and `fiber_current` returns None.
//   * Phase 1 is single-thread. M:N work-stealing across worker OS
//     threads is Phase 3 — the API does not change.
//   * `spawn` is a THREAD BOUNDARY for the compiler's purposes, and is
//     checked exactly like `thread_spawn`: every value the body
//     captures must be `Send` (stdlib/core/marker.nu). A fiber runs on
//     whichever worker pthread picks it up, so capturing an `Rc` is
//     the same undefined behaviour there as on a pthread — and it
//     stays undefined whether or not a given run happens to schedule
//     the fiber elsewhere, which is what makes it worth a compile
//     error rather than a race to find later.
//
// Minimal producer / consumer pattern:
//
//   $ `stdlib/std/async.nu`
//
//   @ worker *u env → v {
//     : i i 0
//     ~ < i 5 {
//       ( puts `tick` )
//       ( yield )
//       = i + i 1
//     }
//   }
//
//   @ main → i {
//     ( runtime_init 0 )
//     ( spawn \ ( worker 0 ) )
//     ( spawn \ ( worker 0 ) )
//     ( runtime_run )
//     ^ 0
//   }

// ── Runtime FFI bridge (factored into a separate `_ffi` module so
//    foundational consumers — e.g. `stdlib/std/channel.nu` for fiber-
//    aware parking — can pull in just the FFI declarations without
//    also dragging in this wrapper surface and tripping a duplicate-
//    declare at link time). ────────────────────────────────────────

$ `stdlib/std/async_ffi.nu`

// ── Opaque handle ──────────────────────────────────────────────────

: Fiber { s raw }

// ── spawn ──────────────────────────────────────────────────────────

// Spawn a new fiber to run `body`. The closure's (fn_ptr, env_ptr)
// pair lands on the scheduler's runqueue; the scheduler's workers
// pull it off and run it. Fire-and-forget — the fiber's control
// block is freed automatically once its body returns.
@ spawn ( @ v ) body → Fiber {
    // Decompose the closure exactly as `thread_spawn` does — bare-form
    // `#`-cast (parenthesised `( # ... )` would be parsed as a call
    // whose function is named `#`).
    : *u fnp # *u body 0
    : *u env # *u body 1
    : i raw ( nurl_fiber_spawn fnp env )
    : s rp # s raw
    ^ @ Fiber { rp }
}

// Spawn a fiber that OWNS its closure env: the runtime frees the env
// right after the body returns. Use for fire-and-forget per-item
// inline closures nothing else holds a handle to (one fiber per
// accepted connection, say) — with plain `spawn` those envs leaked,
// one per spawn, because `spawn` BORROWS the env and a fire-and-forget
// caller has no correct place to free it. Do NOT use when the spawner
// keeps the closure binding around to free (or reuse) it later.
@ spawn_owned ( @ v ) body → Fiber {
    : *u fnp # *u body 0
    : *u env # *u body 1
    : i raw ( nurl_fiber_spawn_owned fnp env )
    : s rp # s raw
    ^ @ Fiber { rp }
}

// Spawn a joinable fiber. The returned handle survives the fiber's
// completion; the caller MUST call `fiber_join` exactly once on it,
// which both waits for completion AND releases the control block.
// Calling `fiber_join` from a fiber currently blocks the worker
// thread — a fiber-to-fiber park lands in Phase 4 alongside the
// channel work.
@ spawn_joinable ( @ v ) body → Fiber {
    : *u fnp # *u body 0
    : *u env # *u body 1
    : i raw ( nurl_fiber_spawn_joinable fnp env )
    : s rp # s raw
    ^ @ Fiber { rp }
}

// Block (Phase 3: at the pthread level) until `f` has finished
// running, then free its control block. Joining a non-joinable
// fiber is a silent no-op. Joining the same handle twice is
// undefined.
@ fiber_join Fiber f → v {
    : s rp . f raw
    : i raw # i rp
    ( nurl_fiber_join raw )
}

// ── yield ──────────────────────────────────────────────────────────

// Cooperative reschedule: put the current fiber at the back of the
// runqueue and let the scheduler pick the next runnable one. From
// outside a fiber (no scheduler-attached current), this is a no-op.
@ yield → v {
    ( nurl_fiber_yield )
}

// ── fiber_current / fiber_worker_id ────────────────────────────────

// Returns the currently running fiber, or None if called from outside
// any fiber (e.g. main thread before `runtime_run` enters the loop).
@ fiber_current → ?Fiber {
    : i raw ( nurl_fiber_current )
    ? == raw 0 { ^ @ ?Fiber { F # Fiber @ Fiber { # s 0 } } } {}
    : s rp # s raw
    ^ @ ?Fiber { T @ Fiber { rp } }
}

// Returns 0..worker_count-1 when called from inside a fiber, or -1
// when called from outside any worker thread (e.g. the main thread
// between `runtime_init` and `runtime_run`). Useful for diagnostics
// — DO NOT use as a partitioning key: a fiber can migrate workers
// via the steal protocol.
@ fiber_worker_id → i {
    ^ ( nurl_fiber_worker_id )
}

// ── runtime lifecycle ──────────────────────────────────────────────

// Initialise the scheduler. Idempotent — safe to call multiple times.
// Phase 1: `workers` is ignored (single-thread). Phase 3 will read
// it as the worker-pool size; pass 0 to mean
// `min(nproc, NURL_WORKERS env)`.
@ runtime_init i workers → v {
    ( nurl_runtime_init workers )
}

// Drain the scheduler — runs every runnable fiber to completion or
// until `runtime_shutdown` is called. From outside a fiber this
// blocks the calling thread; from inside a fiber it is undefined
// behaviour (don't call `runtime_run` recursively).
@ runtime_run → v {
    ( nurl_runtime_run )
}

// Signal the scheduler to stop. After the currently running fiber
// yields or completes, `runtime_run` returns even if other fibers
// are still runnable. Phase 4 will additionally unpark every parked
// fiber with a cancellation flag.
@ runtime_shutdown → v {
    ( nurl_runtime_shutdown )
}

// ── I/O reactor & timers ──────────────────────────────────────────

// Park the current fiber until `fd` is readable OR `timeout_ms`
// milliseconds elapse. timeout_ms < 0 means infinite. Returns 1 if
// the fd became ready, 0 on timeout, -1 if not on a fiber. The
// underlying reactor is epoll on Linux and `poll(2)` on the other
// POSIX targets; any fd works (TCP, UDP, pipes); on WASI / Windows
// this is a no-op returning -1.
@ wait_readable i fd i timeout_ms → i {
    ^ ( nurl_reactor_wait_read fd timeout_ms )
}

// Park the current fiber until `fd` is writable OR `timeout_ms`
// milliseconds elapse. Same return conventions as wait_readable.
@ wait_writable i fd i timeout_ms → i {
    ^ ( nurl_reactor_wait_write fd timeout_ms )
}

// (Context-aware `sleep_ms` lives in `stdlib/std/time.nu` — calling
// it from a fiber parks via the reactor; from a plain OS thread it
// `nanosleep`s as before.)
