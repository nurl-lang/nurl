// stdlib/std/thread.nu — Threads, mutexes, condition variables
//
// Pure-NURL FFI over libpthread. On POSIX `pthread_mutex_*` /
// `pthread_cond_*` / `pthread_create` are libc symbols; on Windows
// mingw-w64 supplies them via libwinpthread (link with -lpthread).
//
// What stays on the C side (runtime.c §19):
//
//   * `nurl_pthread_join_ptr` / `nurl_pthread_detach_ptr` — pthread_t
//     is passed BY VALUE to pthread_join / pthread_detach, and on
//     winpthreads it's a 16-byte struct. NURL's `&`-FFI cannot express
//     by-value-struct args, so these two pointer-taking trampolines
//     bridge the gap (deref, call, return).
//   * WASI stubs — wasi-libc has no pthread; all entries degrade.
//
// NURL-side storage:
//
//   * `Mutex { Cell c }` — Cell sized via `nurl_native_sizeof("pthread_mutex_t")`.
//   * `Cond  { Cell c }` — same pattern, "pthread_cond_t".
//   * `Thread { Cell t }` — same pattern, "pthread_t".
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
//   ( sem_new        i n )                 → Semaphore  n permits
//   ( sem_acquire    Semaphore s )         → v   block for a permit
//   ( sem_try_acquire Semaphore s )        → b   non-blocking
//   ( sem_release    Semaphore s )         → v   return a permit
//   ( sem_avail      Semaphore s )         → i   free permits (diagnostic)
//   ( sem_free       Semaphore s )         → v
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

$ `stdlib/core/cell.nu`
$ `stdlib/core/marker.nu`

// FFI: direct libpthread surface. On Linux/macOS these are libc; on
// mingw-w64 Windows they come from libwinpthread (link with -lpthread).
// Return value is the POSIX errno-style int — 0 on success, non-zero
// on failure. We ignore most of them: every documented failure
// (EAGAIN/EINVAL/ENOMEM/EBUSY/EDEADLK/EPERM) for the mutex/cond
// primitives is either a programmer error (unbalanced lock, destroying
// a held mutex) or an OOM the caller can't recover from. thread_spawn
// IS error-checking because pthread_create's EAGAIN ("would exceed
// thread cap") is a real recoverable condition.
& `c` @ pthread_mutex_init *u m *u attr → i32

& `c` @ pthread_mutex_lock *u m → i32

& `c` @ pthread_mutex_unlock *u m → i32

& `c` @ pthread_mutex_destroy *u m → i32

& `c` @ pthread_cond_init *u cv *u attr → i32

& `c` @ pthread_cond_wait *u cv *u m → i32

& `c` @ pthread_cond_signal *u cv → i32

& `c` @ pthread_cond_broadcast *u cv → i32

& `c` @ pthread_cond_destroy *u cv → i32

// pthread_create's start_routine signature is `void *(*)(void *)`.
// NURL closures compile to `void(*)(void *env)` — same arg shape; the
// return is discarded at the OS layer because the runtime trampolines
// below always pass NULL for the join's value pointer. ABI-compatible
// on every System V target (x86_64 / aarch64 / riscv64).
& `c` @ pthread_create *u t *u attr *u start *u arg → i32

// pthread_t is by-value and 16-byte struct on winpthreads — NURL has
// no struct-by-value FFI. These two trampolines (runtime.c §19) take
// pthread_t* and dereference inside C.
& `c` @ nurl_pthread_join_ptr *u t → i32

& `c` @ nurl_pthread_detach_ptr *u t → v

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

// Thread keeps the 8-byte `{ s raw }` shape it had pre-Phase 6 — `raw`
// is a heap pointer to a pthread_t-sized buffer (via nurl_alloc), and
// the public-facing handle stays cast-to-i64 round-trippable. This
// matters because compiler/tests/{thread_basic,arc_threads}.nu and
// stdlib/ext/http_server.nu's worker-pool path stash handles in a
// malloc'd i64 array via nurl_poke / nurl_peek for batch-join later
// — a 16-byte Cell wouldn't fit those slots.
// Mutex / Cond don't have that constraint, so they store a full Cell.
: Thread { s raw }
: Mutex { Cell c }
: Cond { Cell c }

// Send / Sync markers (stdlib/core/marker.nu). These three are the
// reason the marker traits exist at all: structurally a Mutex is
// `{ Cell c }`, and a bare Cell is a raw byte buffer with
// unsynchronised writes — !Sync, correctly, on its own. A Mutex is the
// thing that MAKES its contents shareable, so the derivation has to be
// told rather than asked. Same for Cond, and for Thread, whose `s raw`
// is a pthread_t buffer that join/detach reach from any thread.
//
// Each of these is an assertion, not a proof — NURL's spelling of
// Rust's `unsafe impl`. What backs them is the C side: every one of
// these handles is manipulated only through the pthread primitives
// below, which are themselves the memory-ordering points.
% Send Mutex {}

% Sync Mutex {}

% Send Cond {}

% Sync Cond {}

% Send Thread {}

% Sync Thread {}

// Counting semaphore built on Mutex + Cond. The permit count lives in a
// heap cell (`* i count`) so copying a Semaphore by value — e.g.
// capturing it in a worker closure — shares the same count, mutex, and
// condvar across threads (same handle-sharing as Mutex/Cond).
: Semaphore {
    Mutex m
    Cond c
    * i count
}

// Sharing a Semaphore across threads is the entire point of one — the
// permit count lives behind the Mutex above, so both questions are
// already answered by the fields; the markers say so explicitly rather
// than leaving it to the `* i count` field to survive the walk.
% Send Semaphore {}

% Sync Semaphore {}

// ── Thread lifecycle ──────────────────────────────────────────────

@ thread_spawn ( @ v ) f → !Thread ThreadErr {
    // Decompose the closure into (fn_ptr, env_ptr) — pthread_create
    // calls fn_ptr(env_ptr) on the worker thread. Closure-field-extract
    // `#`-cast lands here in bare-form, no outer parens — `( # ... )`
    // would be parsed as a call with `#` as the function name.
    : *u fnp # *u f 0
    : *u env # *u f 1
    : i sz ( nurl_native_sizeof `pthread_t` )
    : s ptr ( nurl_alloc sz )
    ? == 0 # i ptr {
        ^ @ !Thread ThreadErr { F # ThreadErr ThreadCreate }
    } {}
    : *u tp # *u ptr
    : i rc ( pthread_create tp # *u 0 fnp env )
    ? != rc 0 {
        ( nurl_free ptr )
        ^ @ !Thread ThreadErr { F # ThreadErr ThreadCreate }
    } {}
    ^ @ !Thread ThreadErr { T @ Thread { ptr } }
}

@ thread_join Thread t → i {
    : s ptr . t raw
    : *u tp # *u ptr
    : i rc ( nurl_pthread_join_ptr tp )
    ( nurl_free ptr )
    ^ ? == rc 0 0 -1
}

@ thread_detach Thread t → v {
    : s ptr . t raw
    : *u tp # *u ptr
    ( nurl_pthread_detach_ptr tp )
    ( nurl_free ptr )
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

// ── Semaphore ─────────────────────────────────────────────────────
//
// Counting semaphore: at most `n` holders may hold a permit at once.
// `sem_acquire` blocks until a permit is free; `sem_release` returns one
// and wakes a waiter. The classic tool for bounding concurrency — e.g.
// capping how many worker threads run a memory-heavy job (a compiler
// invocation, a large download) simultaneously while leaving the rest of
// the pool free to serve light requests.
//
//   : Semaphore gate ( sem_new 4 )
//   // on each worker, around the heavy section:
//   ( sem_acquire gate )  ( do_heavy_work )  ( sem_release gate )
//   // ... at shutdown:
//   ( sem_free gate )

@ sem_new i n → Semaphore {
    : Mutex m ( mutex_new )
    : Cond c ( cond_new )
    : *i count # *i ( nurl_alloc 8 )
    = . count 0 ? > n 0 n 0
    ^ @ Semaphore { m c count }
}

// Block until a permit is available, then take one.
@ sem_acquire Semaphore s → v {
    : *i cp . s count
    ( mutex_lock . s m )
    ~ <= . cp 0 0 {
        ( cond_wait . s c . s m )
    }
    = . cp 0 - . cp 0 1
    ( mutex_unlock . s m )
}

// Take a permit if one is free right now; never blocks. Returns T iff a
// permit was acquired (caller must sem_release on T).
@ sem_try_acquire Semaphore s → b {
    : *i cp . s count
    ( mutex_lock . s m )
    : ~ b ok F
    ? > . cp 0 0 {
        = . cp 0 - . cp 0 1
        = ok T
    } {}
    ( mutex_unlock . s m )
    ^ ok
}

// Return a permit and wake one waiter.
@ sem_release Semaphore s → v {
    : *i cp . s count
    ( mutex_lock . s m )
    = . cp 0 + . cp 0 1
    ( cond_signal . s c )
    ( mutex_unlock . s m )
}

// Current free-permit count. A point-in-time read (no lock held by the
// caller) — for diagnostics, not for acquire decisions (use
// sem_try_acquire, which is atomic).
@ sem_avail Semaphore s → i {
    : *i cp . s count
    ( mutex_lock . s m )
    : i v . cp 0
    ( mutex_unlock . s m )
    ^ v
}

@ sem_free Semaphore s → v {
    ( mutex_free . s m )
    ( cond_free . s c )
    ( nurl_free # s . s count )
}
