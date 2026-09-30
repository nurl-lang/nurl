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
//   * `Mutex { s p }` — a `[ owners ][ pthread_mutex_t ]` block, the
//     native part sized via `nurl_native_sizeof("pthread_mutex_t")`.
//   * `Cond  { s p }` — same pattern, "pthread_cond_t".
//   * `Thread { s raw }` — a `nurl_native_sizeof("pthread_t")` buffer.
//
// API:
//
//   ( thread_spawn   ( @ v ) f )           → ! Thread ThreadErr
//   ( thread_spawn_owned ( @ v ) f )       → ! Thread ThreadErr  (frees f's env after the body)
//   ( thread_join    Thread t )            → i      (0 ok, -1 err)
//   ( thread_detach  Thread t )            → v
//   ( mutex_new )                          → Mutex
//   ( mutex_lock     Mutex m )             → v
//   ( mutex_unlock   Mutex m )             → v
//   ( mutex_free     Mutex m )             → v   (early release; optional)
//   ( mutex_with     Mutex m ( @ v ) body) → v   (lock + run + unlock)
//   ( cond_new )                           → Cond
//   ( cond_wait      Cond c Mutex m )      → v   (must hold m)
//   ( cond_signal    Cond c )              → v
//   ( cond_broadcast Cond c )              → v
//   ( cond_free      Cond c )              → v   (early release; optional)
//   ( sem_new        i n )                 → Semaphore  n permits
//   ( sem_acquire    Semaphore s )         → v   block for a permit
//   ( sem_try_acquire Semaphore s )        → b   non-blocking
//   ( sem_release    Semaphore s )         → v   return a permit
//   ( sem_avail      Semaphore s )         → i   free permits (diagnostic)
//   ( sem_free       Semaphore s )         → v   (early release; optional)
//   ( thread_err_name ThreadErr e )        → s
//
// Memory model:
//
//   * Thread / Mutex / Cond / Semaphore are opaque single-pointer
//     handles. Caller must `thread_join` (or `thread_detach`) each
//     spawned thread once. A Mutex / Cond / Semaphore is reference
//     counted: every copy shares the one object and the last owner
//     destroys it — nothing to free by hand (docs/MEMORY.md §7.6).
//   * `thread_spawn` BORROWS the closure value and the captured env it
//     points at. The closure (and its env heap allocation) MUST OUTLIVE
//     the worker thread — typical pattern is to hold it in a local
//     binding and `thread_join` before that binding goes out of scope.
//     `thread_spawn_owned` is the fire-and-forget form: the env is freed
//     by the thread when the body returns, so an inline closure can be
//     spawned, detached and forgotten without leaking one env per spawn.
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

// pthread_create through a trampoline that runs the body on its own copy
// of the closure env and drops the copy once the body returns
// (runtime_ffi.c §19). What thread_spawn is made of.
& `c` @ nurl_pthread_create_owned *u t *u start *u env → i32

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
: Thread { s raw }

// A Mutex (a Cond) is a handle on one pthread object that every copy of
// it shares: storing a borrowed one into a struct, a Vec or a thread's
// closure takes another reference (`Mutex_share`), and whoever holds the
// last one destroys the object when it goes (`Mutex_drop`) — nothing to
// release by hand. `p` is a block laid out
//
//     [ i64 owners ][ pthread_mutex_t / pthread_cond_t ]
//
// with the native object sized at runtime (`nurl_native_sizeof`), so the
// handle is one word whatever the platform's pthread layout is.
: Mutex { s p }
: Cond { s p }

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

// Counting semaphore built on Mutex + Cond: a handle like them. Every
// copy — a worker closure's capture, a struct field — shares one count,
// mutex and condvar, and the last owner releases them.
: SemaphoreImpl {
    i owners
    i count
    Mutex m
    Cond c
}

: Semaphore { s p }

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
    // The thread runs on its own copy of the env (the runtime clones it
    // and drops the copy when the body returns — docs/MEMORY.md §7.4), so
    // the spawner's closure stays the spawner's to drop.
    : i rc ( nurl_pthread_create_owned tp fnp env )
    ? != rc 0 {
        ( nurl_free ptr )
        ^ @ !Thread ThreadErr { F # ThreadErr ThreadCreate }
    } {}
    ^ @ !Thread ThreadErr { T @ Thread { ptr } }
}

// The same as `thread_spawn`: every thread now runs on its own copy of
// the env. Kept for the programs written when `thread_spawn` borrowed
// the env and this was the only leak-free fire-and-forget spelling.
// Mirrors `spawn_owned` for fibers.
@ thread_spawn_owned ( @ v ) f → !Thread ThreadErr {
    : *u fnp # *u f 0
    : *u env # *u f 1
    : i sz ( nurl_native_sizeof `pthread_t` )
    : s ptr ( nurl_alloc sz )
    ? == 0 # i ptr {
        ^ @ !Thread ThreadErr { F # ThreadErr ThreadCreate }
    } {}
    : *u tp # *u ptr
    : i rc ( nurl_pthread_create_owned tp fnp env )
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

// ── Shared pthread objects ────────────────────────────────────────

& `c` @ nurl_atomic_i64_inc *u p → i

& `c` @ nurl_atomic_i64_dec_fetch *u p → i

// A zeroed `[ owners ][ native ]` block with one owner.
@ __sync_block_new s native → i {
    : ~ i sz ( nurl_native_sizeof native )
    ? < sz 8 { = sz 8 } {}
    : s p ( nurl_zalloc + 8 sz )
    : *i rc # *i p
    = . rc 0 1
    ^ # i p
}

// Another owner of `p`'s block.
@ __sync_block_share s p → v {
    ? != 0 # i p { ( nurl_atomic_i64_inc # *u p ) } {}
}

// Drop one owner of `p`'s block: T when that was the last one (the
// caller then destroys the object and frees the block).
@ __sync_block_release s p → b {
    ? == 0 # i p { ^ F } {}
    ^ <= ( nurl_atomic_i64_dec_fetch # *u p ) 0
}

// ── Mutex ─────────────────────────────────────────────────────────

@ mutex_new → Mutex {
    : i p ( __sync_block_new `pthread_mutex_t` )
    ( pthread_mutex_init # *u + p 8 # *u 0 )
    ^ @ Mutex { # s p }
}

// The pthread_mutex_t itself, for the runtime calls that take one
// (`nurl_fiber_park_with_mutex`).
@ mutex_raw Mutex m → *u {
    ^ # *u + # i . m p 8
}

@ mutex_lock Mutex m → v {
    ( pthread_mutex_lock # *u + # i . m p 8 )
}

@ mutex_unlock Mutex m → v {
    ( pthread_mutex_unlock # *u + # i . m p 8 )
}

@ Mutex_share Mutex m → Mutex {
    ( __sync_block_share . m p )
    ^ @ Mutex { . m p }
}

@ Mutex_drop sink Mutex m → v {
    ( mem_forget m )
    : s p . m p
    ? ( __sync_block_release p ) {
        ( pthread_mutex_destroy # *u + # i p 8 )
        ( nurl_free p )
    } {}
}

// Let go of `m` now rather than at the end of its owner's scope.
@ mutex_free sink Mutex m → v {}

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
    : i p ( __sync_block_new `pthread_cond_t` )
    ( pthread_cond_init # *u + p 8 # *u 0 )
    ^ @ Cond { # s p }
}

@ cond_wait Cond c Mutex m → v {
    ( pthread_cond_wait # *u + # i . c p 8 # *u + # i . m p 8 )
}

@ cond_signal Cond c → v {
    ( pthread_cond_signal # *u + # i . c p 8 )
}

@ cond_broadcast Cond c → v {
    ( pthread_cond_broadcast # *u + # i . c p 8 )
}

@ Cond_share Cond c → Cond {
    ( __sync_block_share . c p )
    ^ @ Cond { . c p }
}

@ Cond_drop sink Cond c → v {
    ( mem_forget c )
    : s p . c p
    ? ( __sync_block_release p ) {
        ( pthread_cond_destroy # *u + # i p 8 )
        ( nurl_free p )
    } {}
}

// Let go of `c` now rather than at the end of its owner's scope.
@ cond_free sink Cond c → v {}

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

@ sem_new i n → Semaphore {
    : *SemaphoreImpl impl # *SemaphoreImpl ( nurl_alloc Z SemaphoreImpl )
    = . impl owners 1
    = . impl count ? > n 0 n 0
    = . impl m ( mutex_new )
    = . impl c ( cond_new )
    ^ @ Semaphore { # s impl }
}

// Block until a permit is available, then take one.
@ sem_acquire Semaphore s → v {
    : *SemaphoreImpl impl # *SemaphoreImpl . s p
    ( mutex_lock . impl m )
    ~ <= . impl count 0 {
        ( cond_wait . impl c . impl m )
    }
    = . impl count - . impl count 1
    ( mutex_unlock . impl m )
}

// Take a permit if one is free right now; never blocks. Returns T iff a
// permit was acquired (caller must sem_release on T).
@ sem_try_acquire Semaphore s → b {
    : *SemaphoreImpl impl # *SemaphoreImpl . s p
    ( mutex_lock . impl m )
    : ~ b ok F
    ? > . impl count 0 {
        = . impl count - . impl count 1
        = ok T
    } {}
    ( mutex_unlock . impl m )
    ^ ok
}

// Return a permit and wake one waiter.
@ sem_release Semaphore s → v {
    : *SemaphoreImpl impl # *SemaphoreImpl . s p
    ( mutex_lock . impl m )
    = . impl count + . impl count 1
    ( cond_signal . impl c )
    ( mutex_unlock . impl m )
}

// Current free-permit count. A point-in-time read (no lock held by the
// caller) — for diagnostics, not for acquire decisions (use
// sem_try_acquire, which is atomic).
@ sem_avail Semaphore s → i {
    : *SemaphoreImpl impl # *SemaphoreImpl . s p
    ( mutex_lock . impl m )
    : i v . impl count
    ( mutex_unlock . impl m )
    ^ v
}

@ Semaphore_share Semaphore s → Semaphore {
    ( __sync_block_share . s p )
    ^ @ Semaphore { . s p }
}

@ Semaphore_drop sink Semaphore s → v {
    ( mem_forget s )
    : s p . s p
    ? ( __sync_block_release p ) {
        : *SemaphoreImpl impl # *SemaphoreImpl p
        : Mutex m . impl m
        ( mem_take m )
        : Cond c . impl c
        ( mem_take c )
        ( nurl_free p )
    } {}
}

// Let go of `s` now rather than at the end of its owner's scope.
@ sem_free sink Semaphore s → v {}
