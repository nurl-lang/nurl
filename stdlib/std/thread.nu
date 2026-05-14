// stdlib/std/thread.nu — Threads, mutexes, condition variables
//
// Wraps the runtime bridge in stdlib/runtime.c (§19). Foundation for
// thread-per-connection HTTP serving (HTTP_SERVER_PLAN.md Phase 5) and
// any producer/consumer NURL code that needs message passing.
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
: Mutex { s raw }
: Cond { s raw }

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
    : i raw ( nurl_mutex_new )
    : s rp # s raw
    ^ @ Mutex { rp }
}

@ mutex_lock Mutex m → v {
    : s rp . m raw
    : i raw # i rp
    ( nurl_mutex_lock raw )
}

@ mutex_unlock Mutex m → v {
    : s rp . m raw
    : i raw # i rp
    ( nurl_mutex_unlock raw )
}

@ mutex_free Mutex m → v {
    : s rp . m raw
    : i raw # i rp
    ( nurl_mutex_free raw )
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
    : i raw ( nurl_cond_new )
    : s rp # s raw
    ^ @ Cond { rp }
}

@ cond_wait Cond c Mutex m → v {
    : s crp . c raw
    : i craw # i crp
    : s mrp . m raw
    : i mraw # i mrp
    ( nurl_cond_wait craw mraw )
}

@ cond_signal Cond c → v {
    : s rp . c raw
    : i raw # i rp
    ( nurl_cond_signal raw )
}

@ cond_broadcast Cond c → v {
    : s rp . c raw
    : i raw # i rp
    ( nurl_cond_broadcast raw )
}

@ cond_free Cond c → v {
    : s rp . c raw
    : i raw # i rp
    ( nurl_cond_free raw )
}
