// stdlib/std/thread.nu — Threads, mutexes, condition variables
//
// Foundation for thread-per-connection HTTP serving (HTTP_SERVER_PLAN.md
// Phase 5) and any producer/consumer NURL code that needs message
// passing.
//
// Mutex + Cond are pure-NURL FFI over libpthread (PURIFY.md Phase 6
// batch 1, 2026-05-23). On POSIX platforms `pthread_mutex_*` and
// `pthread_cond_*` are libc symbols; on Windows the mingw-w64 toolchain
// supplies them via libwinpthread (link with -lpthread). NURL-side
// storage is a `Cell` sized from `nurl_native_sizeof("pthread_mutex_t")`
// / `..._cond_t"`, which translates to the right shape per platform.
//
// Thread spawn/join/detach still go through the runtime trampoline in
// stdlib/runtime.c §19 — pthread_t is passed by value to pthread_join
// (and is a 16-byte struct on winpthreads) which NURL's FFI can't
// express. PURIFY Phase 6 batch 2 will replace those with a small
// pointer-taking trampoline.
//
// API:
//
//   ( thread_spawn   ( @ v ) f )           → ! Thread ThreadErr
//   ( thread_join    Thread t )            → i      (0 ok, -1 err)
//   ( thread_detach  Thread t )            → v
//   ( mutex_new )                          → Mutex
//   ( mutex_lock     Mutex m )             → v
//   ( mutex_unlock   Mutex m )             → v
//   ( mutex_free     Mutex m )             → v
//   ( mutex_with     Mutex m ( @ v ) body) → v   (lock + run + unlock)
//   ( cond_new )                           → Cond
//   ( cond_wait      Cond c Mutex m )      → v   (must hold m)
//   ( cond_signal    Cond c )              → v
//   ( cond_broadcast Cond c )              → v
//   ( cond_free      Cond c )              → v
//   ( thread_err_name ThreadErr e )        → s
//
// Memory model:
//
//   * Thread / Mutex / Cond are opaque single-pointer handles. Caller
//     must `thread_join` (or `thread_detach`) each spawned thread once,
//     and `mutex_free` / `cond_free` each allocator once.
//   * `thread_spawn` BORROWS the closure value and the captured env it
//     points at. The closure (and its env heap allocation) MUST OUTLIVE
//     the worker thread — typical pattern is to hold it in a local
//     binding and `thread_join` before that binding goes out of scope.
//   * The mutex passed to `cond_wait` must already be held by the
//     calling thread; the primitive atomically releases-and-reacquires
//     it per POSIX semantics.
//   * On WASI, every entry degrades to a no-op stub; `thread_spawn`
//     surfaces `ThreadCreate` so callers can fall back to a serial path.

$ `stdlib/core/string.nu`
$ `stdlib/core/cell.nu`

// FFI: direct libpthread for mutex + cond. On Linux/macOS these are
// libc; on mingw-w64 Windows they come from libwinpthread (link with
// -lpthread). Return value is the POSIX errno-style int — 0 on
// success, non-zero on failure. We ignore it: every documented failure
// (EAGAIN/EINVAL/ENOMEM/EBUSY/EDEADLK/EPERM) for these primitives is
// either a programmer error (unbalanced lock, destroying a held
// mutex) or an OOM that the caller can't sensibly recover from.
& `c` @ pthread_mutex_init     *u m *u attr → i
& `c` @ pthread_mutex_lock     *u m → i
& `c` @ pthread_mutex_unlock   *u m → i
& `c` @ pthread_mutex_destroy  *u m → i
& `c` @ pthread_cond_init      *u cv *u attr → i
& `c` @ pthread_cond_wait      *u cv *u m → i
& `c` @ pthread_cond_signal    *u cv → i
& `c` @ pthread_cond_broadcast *u cv → i
& `c` @ pthread_cond_destroy   *u cv → i

// ── ThreadErr ─────────────────────────────────────────────────────

: | ThreadErr {
    ThreadCreate  // pthread_create / _beginthreadex returned 0
    ThreadOther  // catch-all for unsupported targets, etc.
}

@ thread_err_name ThreadErr e → s {
    ^ ?? e {
        ThreadCreate → `ThreadCreate`
        ThreadOther → `ThreadOther`
    }
}

// ── Opaque handles ────────────────────────────────────────────────

: Thread { s raw }
: Mutex { Cell c }
: Cond  { Cell c }

// ── Thread lifecycle ──────────────────────────────────────────────

@ thread_spawn ( @ v ) f → !Thread ThreadErr {
    // Decompose the closure into (fn_ptr, env_ptr) — the C trampoline
    // calls fn_ptr(env_ptr). Closure-field-extract `#`-cast lands here:
    // bare-form, no outer parens — `( # ... )` would be parsed as a call
    // with `#` as the function name.
    : *u fnp # *u f 0
    : *u env # *u f 1
    : i raw ( nurl_thread_spawn fnp env )
    ? == raw 0 { ^ @ !Thread ThreadErr { F # ThreadErr ThreadCreate } } {}
    : s rp # s raw
    ^ @ !Thread ThreadErr { T @ Thread { rp } }
}

@ thread_join Thread t → i {
    : s rp . t raw
    : i raw # i rp
    ^ ( nurl_thread_join raw )
}

@ thread_detach Thread t → v {
    : s rp . t raw
    : i raw # i rp
    ( nurl_thread_detach raw )
}

// ── Mutex ─────────────────────────────────────────────────────────

@ mutex_new → Mutex {
    : Cell c ( cell_for_native `pthread_mutex_t` )
    ? ( cell_is_null c ) {} {
        ( pthread_mutex_init ( cell_ptr c ) # *u 0 )
    }
    ^ @ Mutex { c }
}

@ mutex_lock Mutex m → v {
    ( pthread_mutex_lock ( cell_ptr . m c ) )
}

@ mutex_unlock Mutex m → v {
    ( pthread_mutex_unlock ( cell_ptr . m c ) )
}

@ mutex_free Mutex m → v {
    : Cell c . m c
    ? ( cell_is_null c ) {} {
        ( pthread_mutex_destroy ( cell_ptr c ) )
    }
    ( cell_free c )
}

// Run `body` while holding `m`. Releases the lock even when body returns
// early (no panic recovery — NURL has no exception model, so an error
// in body just ends the program; this helper is for ergonomics, not
// scope-exit safety).
@ mutex_with Mutex m ( @ v ) body → v {
    ( mutex_lock m )
    ( body )
    ( mutex_unlock m )
}

// ── Condition variable ────────────────────────────────────────────

@ cond_new → Cond {
    : Cell cell ( cell_for_native `pthread_cond_t` )
    ? ( cell_is_null cell ) {} {
        ( pthread_cond_init ( cell_ptr cell ) # *u 0 )
    }
    ^ @ Cond { cell }
}

@ cond_wait Cond c Mutex m → v {
    ( pthread_cond_wait ( cell_ptr . c c ) ( cell_ptr . m c ) )
}

@ cond_signal Cond c → v {
    ( pthread_cond_signal ( cell_ptr . c c ) )
}

@ cond_broadcast Cond c → v {
    ( pthread_cond_broadcast ( cell_ptr . c c ) )
}

@ cond_free Cond c → v {
    : Cell cell . c c
    ? ( cell_is_null cell ) {} {
        ( pthread_cond_destroy ( cell_ptr cell ) )
    }
    ( cell_free cell )
}
