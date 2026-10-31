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
//   * `Cond  { s p }` — same pattern, "nurl_fcond_t": the runtime's
//     condition variable, a pthread_cond_t for the threads that wait
//     on it plus the fibers parked on it (runtime_ffi.c §19). A fiber
//     that waits parks — its worker runs other fibers meanwhile —
//     where a pthread_cond_wait would stop the worker thread, and every
//     fiber on it, the one that would signal included (agora #255).
//   * `Thread { s p }` — a `[ owners ][ settled ][ pthread_t ]` block,
//     the pthread_t sized via `nurl_native_sizeof("pthread_t")`.
//
// API:
//
//   ( thread_spawn   ( @ v ) f )           → ! Thread ThreadErr
//   ( thread_spawn_owned ( @ v ) f )       → ! Thread ThreadErr  (frees f's env after the body)
//   ( thread_join    Thread t )            → i      (0 ok; -1 err, or already
//                                                      joined / detached)
//   ( thread_detach  Thread t )            → v      (no-op once joined / detached)
//   ( mutex_new )                          → Mutex
//   ( mutex_lock     Mutex m )             → v
//   ( mutex_unlock   Mutex m )             → v
//   ( mutex_free     Mutex m )             → v   (early release; optional)
//   ( mutex_with     Mutex m ( @ v ) body) → v   (lock + run + unlock)
//   ( locked_new     [T] x )               → ( Locked T )  a value with its own lock
//   ( locked_with    [T] l ( @ v T ) f )   → v   run f on the value, holding the lock
//   ( locked_get     [T] l )               → T   a copy, taken under the lock
//   ( locked_set     [T] l x )             → v   replace the value under the lock
//   ( locked_take    [T] l )               → T   check the value out to change it
//   ( locked_restore [T] l x )             → v   check it back in
//   ( locked_update  [T] l f )             → v   f changes the value in place
//   ( locked_apply   [T R] l f )           → R   …and hands back a result
//   ( locked_await   [T R] l f )           → R   f runs on the value each time
//                                               it changes, until it hands back
//                                               a result (a monitor: wait until)
//   ( cond_new )                           → Cond
//   ( cond_wait      Cond c Mutex m )      → v   (must hold m)
//   ( cond_wait_ms   Cond c Mutex m i ms ) → b   …at most ms milliseconds
//                                               (ms < 0: no bound); F when
//                                               the time ran out
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
//     handles, reference counted: every copy (a struct field, a Vec
//     element, a closure capture, `X_share`) is the same object and the
//     last owner releases it — nothing to free by hand (docs/MEMORY.md
//     §7.6). A Mutex / Cond / Semaphore is destroyed then.
//   * A Thread is joined or detached at most once, through any copy:
//     the first `thread_join` / `thread_detach` settles it, and a later
//     one is a no-op (`thread_join` returns -1). A thread nobody settled
//     is DETACHED when the last copy of its handle goes — it keeps
//     running, and its resources are reclaimed when it ends (Rust's
//     JoinHandle). So a fire-and-forget spawn is
//     `( thread_spawn \ → v { … } )` with the result discarded; join to
//     wait for the body. `@ Thread { # s 0 }` is no thread — a
//     placeholder for one not spawned (yet): joining it returns -1,
//     detaching or dropping it does nothing.
//   * The thread runs on its OWN copy of the closure env (the runtime
//     clones it — or adopts a closure written in the call, handed over —
//     and drops it when the body returns), so the
//     spawner's closure stays the spawner's to drop and an inline
//     closure can be spawned without outliving anything.
//   * The mutex passed to `cond_wait` must already be held by the
//     calling thread; the primitive atomically releases-and-reacquires
//     it per POSIX semantics.
//   * On WASI, every entry degrades to a no-op stub; `thread_spawn`
//     surfaces `ThreadCreate` so callers can fall back to a serial path.

$ `stdlib/core/cell.nu`
$ `stdlib/core/marker.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/core/rcbox.nu`

// FFI: direct libpthread surface. On Linux/macOS these are libc; on
// mingw-w64 Windows they come from libwinpthread (link with -lpthread).
// Return value is the POSIX errno-style int — 0 on success, non-zero
// on failure. We ignore most of them: every documented failure
// (EAGAIN/EINVAL/ENOMEM/EBUSY/EDEADLK/EPERM) for the mutex/cond
// primitives is either a programmer error (unbalanced lock, destroying
// a held mutex) or an OOM the caller can't recover from. thread_spawn
// IS error-checking because pthread_create's EAGAIN ("would exceed
// thread cap") is a real recoverable condition.
& `c` @ pthread_mutex_init *u m in *u attr → i32

& `c` @ pthread_mutex_lock sync *u m → i32

& `c` @ pthread_mutex_unlock sync *u m → i32

& `c` @ pthread_mutex_destroy *u m → i32

& `c` @ pthread_cond_init *u cv in *u attr → i32

& `c` @ pthread_cond_wait sync *u cv sync *u m → i32

& `c` @ pthread_cond_signal sync *u cv → i32

& `c` @ pthread_cond_broadcast sync *u cv → i32

& `c` @ pthread_cond_destroy *u cv → i32

// pthread_cond_timedwait over a relative bound in milliseconds (the
// absolute struct timespec deadline is laid out on the C side,
// runtime_ffi.c §19). 1 signalled (or spuriously woken), 0 timed out.
& `c` @ nurl_cond_wait_ms sync *u cv sync *u m i ms → i32

// The Cond's own primitives (runtime_ffi.c §19): a wait on a fiber parks
// the fiber; ms < 0 is no bound. 1 woken (or spuriously), 0 timed out.
& `c` @ nurl_fcond_init *u cv → i32

& `c` @ nurl_fcond_destroy *u cv → i32

& `c` @ nurl_fcond_wait_ms sync *u cv sync *u m i ms → i32

& `c` @ nurl_fcond_signal sync *u cv → i32

& `c` @ nurl_fcond_broadcast sync *u cv → i32

// pthread_create's start_routine signature is `void *(*)(void *)`.
// NURL closures compile to `void(*)(void *env)` — same arg shape; the
// return is discarded at the OS layer because the runtime trampolines
// below always pass NULL for the join's value pointer. ABI-compatible
// on every System V target (x86_64 / aarch64 / riscv64).
& `c` @ pthread_create *u t in *u attr in *u start in *u arg → i32

// pthread_t is by-value and 16-byte struct on winpthreads — NURL has
// no struct-by-value FFI. These two trampolines (runtime.c §19) take
// pthread_t* and dereference inside C.
& `c` @ nurl_pthread_join_ptr *u t → i32

& `c` @ nurl_pthread_detach_ptr *u t → v

// pthread_create through a trampoline that runs the body on its own copy
// of the closure env and drops the copy once the body returns
// (runtime_ffi.c §19). What thread_spawn is made of.
& `c` @ nurl_pthread_create_owned *u t in *u start in *u env → i32

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

// A Thread is a handle on one spawned thread that every copy of it
// shares; whoever holds the last copy settles the thread if nobody did
// (ThreadImpl's drop detaches it). The pthread_t is a RawBlock sized at
// runtime (`nurl_native_sizeof`), which releases itself. `settled`
// counts the joins and detaches asked for: the one that moves it from 0
// owns the thread's single join-or-detach, so two copies can never join
// (or join and detach) the same pthread_t.
: ThreadImpl { i settled RawBlock tid }

% Drop ThreadImpl {
    unsafe @ drop ThreadImpl t → v {
        ? == 0 . t settled { ( nurl_pthread_detach_ptr ( raw_block_ptr . t tid ) ) } {}
    }
}

: Thread { ( Shared ThreadImpl ) ctl }

// A Mutex (a Cond) is a handle on one pthread object that every copy of
// it shares: storing a borrowed one into a struct, a Vec or a thread's
// closure takes another reference (`Mutex_share`), and whoever holds the
// last one destroys the object when it goes (the impl's drop) — nothing
// to release by hand. The native object is a RawBlock sized at runtime
// (`nurl_native_sizeof`), so the handle is one word whatever the
// platform's pthread layout is; `obj` caches its address.
: MutexImpl { RawBlock blk }

% Drop MutexImpl { unsafe @ drop MutexImpl m → v { ( pthread_mutex_destroy ( raw_block_ptr . m blk ) ) } }

: CondImpl { RawBlock blk }

% Drop CondImpl { unsafe @ drop CondImpl c → v { ( nurl_fcond_destroy ( raw_block_ptr . c blk ) ) } }

: Mutex { ( Shared MutexImpl ) ctl }
: Cond { ( Shared CondImpl ) ctl }

// Send / Sync markers (stdlib/core/marker.nu). These three are the
// reason the marker traits exist at all: structurally a Mutex is
// `{ Cell c }`, and a bare Cell is a raw byte buffer with
// unsynchronised writes — !Sync, correctly, on its own. A Mutex is the
// thing that MAKES its contents shareable, so the derivation has to be
// told rather than asked. Same for Cond, and for Thread, whose block
// holds a pthread_t that join/detach reach from any thread.
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
// mutex and condvar in a counted block (stdlib/core/rcbox.nu), and the
// last owner drops them.
: SemaphoreImpl {
    i count
    Mutex m
    Cond c
}

: Semaphore { ( Shared SemaphoreImpl ) ctl }

// Sharing a Semaphore across threads is the entire point of one — the
// permit count lives behind the Mutex above, so both questions are
// already answered by the fields; the markers say so explicitly rather
// than leaving it to the `* i count` field to survive the walk.
% Send Semaphore {}

% Sync Semaphore {}

// ── Thread lifecycle ──────────────────────────────────────────────

// A thread started on a fresh one-owner handle: fn(env) on its own copy
// of the env (the runtime clones it, or adopts a closure written in the
// call, and drops it when the body returns — docs/MEMORY.md §7.4), so
// the spawner's closure stays the
// spawner's to drop. F when the thread could not be had (its handle is
// then marked settled, so dropping it detaches nothing).
@ __thread_start * u fnp * u env inout Thread out → b {
    : ~ i sz ( nurl_native_sizeof `pthread_t` )
    ? < sz 8 { = sz 8 } {}
    : RawBlock tid ( raw_block_zero sz )
    : *u tp ( raw_block_ptr tid )
    = out @ Thread { ( shared_new [ThreadImpl] @ ThreadImpl { 0 tid } ) }
    ? != 0 ( nurl_pthread_create_owned tp fnp env ) {
        = . ( __thi out ) settled 1
        ^ F
    } {}
    ^ T
}

@ __thi Thread t → *ThreadImpl { ^ ( shared_ptr [ThreadImpl] . t ctl ) }

// The pthread_t of `t`.
@ __thread_tid Thread t → *u { ^ ( raw_block_ptr . ( __thi t ) tid ) }

@ thread_spawn ( @ v ) f → !Thread ThreadErr {
    // A handle whose copies are one state that `f` captures goes with it
    // only with every owner of that state (docs/MEMORY.md §6.5).
    ( mem_send_check [( @ v )] f `thread_spawn` )
    // Decompose the closure into (fn_ptr, env_ptr) — pthread_create
    // calls fn_ptr(env_ptr) on the worker thread. Closure-field-extract
    // `#`-cast lands here in bare-form, no outer parens — `( # ... )`
    // would be parsed as a call with `#` as the function name.
    : *u fnp # *u f 0
    : *u env # *u f 1
    : ~ Thread t ( thread_null )
    ? ( __thread_start fnp env t ) {} {
        ^ @ !Thread ThreadErr { F # ThreadErr ThreadCreate }
    }
    ^ @ !Thread ThreadErr { T t }
}

// The same as `thread_spawn`: every thread now runs on its own copy of
// the env. Kept for the programs written when `thread_spawn` borrowed
// the env and this was the only leak-free fire-and-forget spelling.
// Mirrors `spawn_owned` for fibers.
@ thread_spawn_owned ( @ v ) f → !Thread ThreadErr {
    ( mem_send_check [( @ v )] f `thread_spawn_owned` )
    : *u fnp # *u f 0
    : *u env # *u f 1
    : ~ Thread t ( thread_null )
    ? ( __thread_start fnp env t ) {} {
        ^ @ !Thread ThreadErr { F # ThreadErr ThreadCreate }
    }
    ^ @ !Thread ThreadErr { T t }
}

// A handle on no thread (a slot filled later): join and detach do
// nothing on it, and dropping it releases nothing.
@ thread_null → Thread { ^ @ Thread { ( shared_null [ThreadImpl] ) } }

// Claim `t`'s one join-or-detach: T for the first caller only.
@ __thread_claim Thread t → b {
    ? == 0 ( shared_addr [ThreadImpl] . t ctl ) { ^ F } {}
    ^ == 0 ( nurl_atomic_i64_inc # *u ( __thi t ) )
}

// Wait for the thread to finish. 0 once it has; -1 when the join failed
// or the thread was already joined or detached (through this copy of the
// handle or another), so a second join never touches the pthread_t again.
@ thread_join Thread t → i {
    ? ( __thread_claim t ) {} { ^ -1 }
    ? == 0 ( nurl_pthread_join_ptr ( __thread_tid t ) ) { ^ 0 } {}
    // Not joined (a thread joining itself): give the claim back, so the
    // last owner still detaches it.
    = . ( __thi t ) settled 0
    ^ -1
}

// Let the thread run on its own; it is reclaimed when it ends. A no-op
// once the thread was joined or detached.
@ thread_detach Thread t → v {
    ? ( __thread_claim t ) { ( nurl_pthread_detach_ptr ( __thread_tid t ) ) } {}
}

@ Thread_share Thread t → Thread { ^ @ Thread { ( shared_clone [ThreadImpl] . t ctl ) } }

// The last owner detaches a thread nobody joined or detached — it keeps
// running and is reclaimed when it ends (ThreadImpl's drop).
@ Thread_drop sink Thread t → v {}

// ── Shared pthread objects ────────────────────────────────────────

& `c` @ nurl_atomic_i64_inc sync *u p → i

& `c` @ nurl_atomic_i64_dec_fetch sync *u p → i

// A zeroed block the size of the native object `native`.
@ __sync_block s native → RawBlock {
    : ~ i sz ( nurl_native_sizeof native )
    ? < sz 8 { = sz 8 } {}
    ^ ( raw_block_zero sz )
}

@ __mutex_obj Mutex m → *u { ^ ( raw_block_ptr . ( shared_ptr [MutexImpl] . m ctl ) blk ) }

@ __cond_obj Cond c → *u { ^ ( raw_block_ptr . ( shared_ptr [CondImpl] . c ctl ) blk ) }

// ── Mutex ─────────────────────────────────────────────────────────

@ mutex_new → Mutex {
    : RawBlock b ( __sync_block `pthread_mutex_t` )
    ( pthread_mutex_init ( raw_block_ptr b ) # *u 0 )
    ^ @ Mutex { ( shared_new [MutexImpl] @ MutexImpl { b } ) }
}

// The pthread_mutex_t itself, for the runtime calls that take one
// (`nurl_fiber_park_with_mutex`).
@ mutex_raw Mutex m → *u { ^ ( __mutex_obj m ) }

@ mutex_lock Mutex m → v { ( pthread_mutex_lock ( __mutex_obj m ) ) }

@ mutex_unlock Mutex m → v { ( pthread_mutex_unlock ( __mutex_obj m ) ) }

@ Mutex_share Mutex m → Mutex { ^ @ Mutex { ( shared_clone [MutexImpl] . m ctl ) } }

@ Mutex_drop sink Mutex m → v {}

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

// ── Locked ──────────────────────────────────────────────────────────

// A value with its own lock (docs/MEMORY.md §6.5). An Arc's payload is
// frozen once made, so the state threads share and change is a Locked
// one: the value is reached only through the functions below, each of
// which holds the lock for the whole call — which lock guards which data
// is decided by the type, not by where `mutex_lock` calls fall. A Locked
// is itself a shared handle (every copy is the same value, the last one
// releases it), so it is captured or sent to the threads that use it;
// T must be Send, since it is reached from whichever thread holds the
// lock.
: LockedImpl [T] {
    Mutex mu
    T val
    // Checked out (locked_take): the value is with one thread, and every
    // other operation waits on `cv` until it is restored.
    b taken
    Cond cv
    // Threads and fibers waiting on `cv` (a fiber parks, its worker runs
    // on): a restore with nobody waiting skips the broadcast (changed
    // only with `mu` held).
    i waiters
}

: Locked [T] { ( Shared ( LockedImpl T ) ) ctl }

% Sync Locked {}

@ locked_new [T] sink T x → ( Locked T ) {
    // The value goes where every thread holding the Locked reaches it: a
    // handle in it whose copies are one state may have no owner outside
    // (docs/MEMORY.md §6.5). So, below, for every value going in — and for
    // the value after a closure ran on it, which may have kept a copy of
    // it, or stored one of a handle kept outside: checked before the lock
    // is let go (a failure panics with it held, as a panic in `f` does).
    ( mem_send_check [T] x `locked_new` )
    ^ @ ( Locked T ) { ( shared_new [( LockedImpl T )] @ ( LockedImpl T ) { ( mutex_new ) x F ( cond_new ) 0 } ) }
}

// A Locked over the all-zero value of T. Outside `unsafe` only for a T
// a zero is a value of (the arc_zero rule); an `unsafe` caller that fills
// every other field in — under locked_take — before anything reads it
// vouches for that (a large engine record built field by field).
@ locked_zero [T] → ( Locked T ) {
    : ( Shared ( LockedImpl T ) ) sh ( shared_zero [( LockedImpl T )] )
    : *( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] sh )
    = . p mu ( mutex_new )
    = . p cv ( cond_new )
    ^ @ ( Locked T ) { sh }
}

@ Locked_share [T] ( Locked T ) l → ( Locked T ) {
    ^ @ ( Locked T ) { ( shared_clone [( LockedImpl T )] . l ctl ) }
}

@ Locked_drop [T] sink ( Locked T ) l → v {}

// Run `f` on the value while holding the lock. `f` gets a view: what it
// does to a container changes the value; a copy it keeps is its own (a
// scalar is replaced with locked_set).
@ locked_with [T] ( Locked T ) l ( @ v T ) f → v {
    : *( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] . l ctl )
    ( mutex_lock . p mu )
    ~ . p taken { = . p waiters + . p waiters 1 ( cond_wait . p cv . p mu ) = . p waiters - . p waiters 1 }
    ( f . p val )
    ( mem_send_check [T] . p val `locked_with` )
    ( mutex_unlock . p mu )
}

// Run `f` on the value IN PLACE while holding the lock: `f` takes it
// `inout`, so it may change any field, scalars included, and the value
// never moves — it stays at the address it has had since locked_new (what
// a record other code holds the address of needs). Nothing is copied.
@ locked_update [T] ( Locked T ) l ( @ v inout T ) f → v {
    : ~ * ( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] . l ctl )
    ( mutex_lock . p mu )
    ~ . p taken { = . p waiters + . p waiters 1 ( cond_wait . p cv . p mu ) = . p waiters - . p waiters 1 }
    ( f . p val )
    ( mem_send_check [T] . p val `locked_update` )
    // (A thread in locked_await looks again at the changed value.)
    ? > . p waiters 0 { ( cond_broadcast . p cv ) } {}
    ( mutex_unlock . p mu )
}

// locked_update with a result: `f`'s, returned once the lock is let go.
@ locked_apply [T R] ( Locked T ) l ( @ R inout T ) f → R {
    : ~ * ( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] . l ctl )
    ( mutex_lock . p mu )
    ~ . p taken { = . p waiters + . p waiters 1 ( cond_wait . p cv . p mu ) = . p waiters - . p waiters 1 }
    : R r ( f . p val )
    ( mem_send_check [T] . p val `locked_apply` )
    ? > . p waiters 0 { ( cond_broadcast . p cv ) } {}
    ( mutex_unlock . p mu )
    ^ r
}

// A monitor's wait: run `f` on the value IN PLACE with the lock held — and
// again each time another thread changes the value (locked_update,
// locked_apply, locked_set, locked_restore) — until it hands back a
// result, which is returned once the lock is let go. Between two runs the
// lock is not held, so the thread waits without stopping the ones that
// will change what it is waiting for. `f` may change the value too (to
// register itself, say); a run that changes it and hands back nothing
// wakes the other waiters before this one sleeps.
//
//   ( locked_await [Queue Job] q \ inout Queue x → ?Job { ^ ( queue_pop x ) } )
@ locked_await [A R] ( Locked A ) l ( @ ?R inout A ) f → R {
    : ~ * ( LockedImpl A ) p ( shared_ptr [( LockedImpl A )] . l ctl )
    ( mutex_lock . p mu )
    ~ T {
        ~ . p taken { = . p waiters + . p waiters 1 ( cond_wait . p cv . p mu ) = . p waiters - . p waiters 1 }
        : ?R r ( f . p val )
        ( mem_send_check [A] . p val `locked_await` )
        ? > . p waiters 0 { ( cond_broadcast . p cv ) } {}
        ? . r 0 {
            ( mutex_unlock . p mu )
            ^ . r 1
        } {}
        = . p waiters + . p waiters 1
        ( cond_wait . p cv . p mu )
        = . p waiters - . p waiters 1
    }
}

// A copy of the value, taken under the lock.
@ locked_get [T] ( Locked T ) l → T {
    : *( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] . l ctl )
    ( mutex_lock . p mu )
    ~ . p taken { = . p waiters + . p waiters 1 ( cond_wait . p cv . p mu ) = . p waiters - . p waiters 1 }
    : T c ( mem_dup . p val )
    ( mutex_unlock . p mu )
    // A copy of a handle whose copies are one state is that state, which
    // the threads holding the Locked change: none is handed out.
    ( mem_send_check [T] c `locked_get` )
    ^ c
}

// Replace the value under the lock (the old one is dropped).
@ locked_set [T] ( Locked T ) l sink T x → v {
    ( mem_send_check [T] x `locked_set` )
    : *( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] . l ctl )
    ( mutex_lock . p mu )
    ~ . p taken { = . p waiters + . p waiters 1 ( cond_wait . p cv . p mu ) = . p waiters - . p waiters 1 }
    = . p val x
    ? > . p waiters 0 { ( cond_broadcast . p cv ) } {}
    ( mutex_unlock . p mu )
}

// Take the value out to change it, holding no lock while it is out:
// every other operation on the Locked — from any thread — waits until
// `locked_restore` puts it back. Nothing is copied. (Taken twice by one
// thread without a restore in between, the second take waits forever, as
// a mutex locked twice does.)
@ locked_take [T] ( Locked T ) l → T {
    : *( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] . l ctl )
    ( mutex_lock . p mu )
    ~ . p taken { = . p waiters + . p waiters 1 ( cond_wait . p cv . p mu ) = . p waiters - . p waiters 1 }
    // (Claimed out of its slot, it leaves zero bytes there.)
    : T x . p val
    ( mem_take x )
    = . p taken ! F  // (`T` is the type parameter here)
    ( mutex_unlock . p mu )
    ^ x
}

// Put back the value `locked_take` took out, and wake the threads
// waiting for it. Panics when the value was not taken.
@ locked_restore [T] ( Locked T ) l sink T x → v {
    ( mem_send_check [T] x `locked_restore` )
    : *( LockedImpl T ) p ( shared_ptr [( LockedImpl T )] . l ctl )
    ( mutex_lock . p mu )
    ? ! . p taken { ( mutex_unlock . p mu ) ( nurl_panic `locked_restore: the value was not taken` ) } {}
    // It replaces the zero bytes locked_take left: they own nothing, so
    // they are swapped out and forgotten rather than run through the
    // value's drop glue (which walks every field of a large record).
    : T zero ( mem_replace [T] . p val x )
    ( mem_forget zero )
    = . p taken F
    ? > . p waiters 0 { ( cond_broadcast . p cv ) } {}
    ( mutex_unlock . p mu )
}

// ── Condition variable ────────────────────────────────────────────

@ cond_new → Cond {
    : RawBlock b ( __sync_block `nurl_fcond_t` )
    ( nurl_fcond_init ( raw_block_ptr b ) )
    ^ @ Cond { ( shared_new [CondImpl] @ CondImpl { b } ) }
}

// Wait on `c` with `m` held (held again on return). On a fiber the fiber
// parks and its worker runs other fibers; on a thread the thread sleeps.
// Woken by cond_signal / cond_broadcast — or spuriously: loop on the
// predicate.
@ cond_wait Cond c Mutex m → v { ( nurl_fcond_wait_ms ( __cond_obj c ) ( __mutex_obj m ) -1 ) }

// cond_wait for at most `ms` milliseconds (ms < 0: no bound). F when the
// time ran out, T when signalled — or woken spuriously, as cond_wait may
// be: the caller loops on its predicate and its own deadline either way.
@ cond_wait_ms Cond c Mutex m i ms → b { ^ != 0 ( nurl_fcond_wait_ms ( __cond_obj c ) ( __mutex_obj m ) ms ) }

@ cond_signal Cond c → v { ( nurl_fcond_signal ( __cond_obj c ) ) }

@ cond_broadcast Cond c → v { ( nurl_fcond_broadcast ( __cond_obj c ) ) }

@ Cond_share Cond c → Cond { ^ @ Cond { ( shared_clone [CondImpl] . c ctl ) } }

@ Cond_drop sink Cond c → v {}

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
    : i count ? > n 0 n 0
    ^ @ Semaphore { ( shared_new [SemaphoreImpl] @ SemaphoreImpl { count ( mutex_new ) ( cond_new ) } ) }
}

// Block until a permit is available, then take one.
@ sem_acquire Semaphore s → v {
    : *SemaphoreImpl impl ( shared_ptr [SemaphoreImpl] . s ctl )
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
    : *SemaphoreImpl impl ( shared_ptr [SemaphoreImpl] . s ctl )
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
    : *SemaphoreImpl impl ( shared_ptr [SemaphoreImpl] . s ctl )
    ( mutex_lock . impl m )
    = . impl count + . impl count 1
    ( cond_signal . impl c )
    ( mutex_unlock . impl m )
}

// Current free-permit count. A point-in-time read (no lock held by the
// caller) — for diagnostics, not for acquire decisions (use
// sem_try_acquire, which is atomic).
@ sem_avail Semaphore s → i {
    : *SemaphoreImpl impl ( shared_ptr [SemaphoreImpl] . s ctl )
    ( mutex_lock . impl m )
    : i v . impl count
    ( mutex_unlock . impl m )
    ^ v
}

@ Semaphore_share Semaphore s → Semaphore { ^ @ Semaphore { ( shared_clone [SemaphoreImpl] . s ctl ) } }

@ Semaphore_drop sink Semaphore s → v {}

// Let go of `s` now rather than at the end of its owner's scope.
@ sem_free sink Semaphore s → v {}
