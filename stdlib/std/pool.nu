// stdlib/std/pool.nu — a bounded pool of reusable resources.
//
// Database connections, sessions with a remote service, anything that is
// expensive to make and is used by one caller at a time: a Pool makes
// them on demand with a factory closure, lends each to one caller at a
// time, and takes it back when the caller lets go.
//
//   ( pool_new [A E] make check cfg timeout_err closed_err )  → ( Pool A E )
//   ( pool_get [A E] p )                 → !( Pooled A E ) E   wait up to cfg's wait_ms
//   ( pool_get_ms [A E] p i ms )         → !( Pooled A E ) E   …up to ms (< 0: no bound)
//   ( pooled_get [A E] g )               → A    the resource, lent while g lives
//   ( pool_discard [A E] g )             → v    drop it instead of returning it
//   ( pool_fill [A E] p )                → !v E make resources up to cfg's min
//   ( pool_evict_idle [A E] p )          → i    drop the ones idle too long; how many
//   ( pool_close [A E] p )               → v    no more checkouts; idle ones dropped
//   ( pool_live / pool_idle / pool_waiting [A E] p ) → i   counts (a snapshot)
//
//   make   ( @ !A E )   a fresh resource, or the error pool_get hands back
//   check  ( @ b A )    run on each resource coming back: F discards it (a
//                       connection that saw an I/O error, one left inside a
//                       transaction). Keep it cheap — it runs on every return
//   cfg    PoolCfg { min max wait_ms idle_ms }
//            min      kept on eviction, and what pool_fill makes up front
//            max      the most resources alive at once (lent + idle + being made)
//            wait_ms  how long pool_get waits when all max are lent; < 0 for
//                     ever, 0 not at all
//            idle_ms  a resource idle longer than this is dropped (kept down
//                     to min); <= 0 keeps them
//   timeout_err / closed_err   the values of E pool_get reports for "waited
//                       wait_ms and nothing came back" and "the pool is
//                       closed", so a pool speaks its resource's own error
//                       type (psql's pg_pool reports PgErr, its factory's
//                       connect error included). PoolErr below is an E for
//                       pools that have none.
//
// A checkout is a GUARD: `Pooled A E` holds the resource and one owner of
// the pool, and its drop gives the resource back — at the end of the
// caller's scope, when the struct holding it goes, or in the unwind of a
// panic (docs/MEMORY.md §7.2). Nothing is returned by hand, and a resource
// cannot be returned twice. `pool_discard` is the one other way out: the
// caller saw the resource fail and it is dropped, which frees its place
// for a new one.
//
// Waiting is context-aware, as a Channel's is: on a fiber, pool_get parks
// the fiber (the worker runs other fibers meanwhile) with the runtime's
// timed park, which a returning resource and the deadline race for
// safely (nurl_fiber_park_with_mutex_ms); on a plain thread it waits on
// the pool's condvar with a bounded cond_wait_ms. Fibers and threads may
// share one pool. Waiters are served first come, first served, fibers
// before threads.
//
// The factory, the check and a resource's drop run with no lock held —
// they may do I/O (a connection's drop sends its goodbye) — so a slow
// connect does not stall the callers returning resources. A place for a
// resource being made is reserved first, so `max` holds however many
// callers make one at once.
//
// The pool is a shared handle: capture it in the threads and fibers that
// use it, store it, send it. Every copy is the same pool, and the last
// one drops the idle resources. A resource travels from whichever thread
// returned it to whichever one takes it next, so A must be Send; the
// handle is Sync because everything in it is reached under its mutex.
// The factory runs on whichever thread needs a resource, so what it
// captures crosses threads with the pool (the compiler follows the
// closure into the pool and checks its captures where the pool crosses).
//
//   : ( Pool Conn ConnErr ) pool ( pool_new [Conn ConnErr]
//       \ → !Conn ConnErr { ^ ( conn_open `db.example` ) }
//       \ Conn c → b { ^ ( conn_ok c ) }
//       @ PoolCfg { 1 16 5000 60000 } # ConnErr ConnTimeout # ConnErr ConnClosed )
//   ?? ( pool_get [Conn ConnErr] pool ) {
//       T g → { ( conn_send ( pooled_get [Conn ConnErr] g ) `PING` ) }  // returned here
//       F e → { … }
//   }

$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/async_ffi.nu`
$ `stdlib/std/time.nu`

// An error type for a pool whose resources have none of their own.
: | PoolErr {
    PoolTimeout  // waited wait_ms and no resource came back
    PoolClosed  // pool_close ran
    PoolCreate  // the factory failed
}

@ pool_err_name PoolErr e → s {
    ^ ?? e {
        PoolTimeout → `PoolTimeout`
        PoolClosed → `PoolClosed`
        PoolCreate → `PoolCreate`
    }
}

: PoolCfg {
    i min
    i max
    i wait_ms
    i idle_ms
}

: PoolImpl [A E] {
    Mutex m
    Cond c  // threads waiting for a resource
    ( Vec A ) idle  // a stack: the most recently returned on top
    ( Vec i ) since  // when each idle one came back (monotonic ms)
    i live  // made and not yet dropped: lent + idle + being made
    PoolCfg cfg
    ( @ !A E ) make
    ( @ b A ) check
    E timeout_err
    E closed_err
    ( Vec i ) fibers  // parked fibers waiting, oldest first
    i threads  // threads in cond_wait_ms
    b closed
}

: Pool [A E] { ( Shared ( PoolImpl A E ) ) ctl }

// Everything in the pool is reached under its own mutex.
% Sync Pool {}

// A checked-out resource: one owner of the pool and the resource. Its
// drop returns `val` to the pool (pool_discard drops it instead).
: Pooled [A E] {
    ( Shared ( PoolImpl A E ) ) ctl
    A val
}

@ Pool_share [A E] ( Pool A E ) p → ( Pool A E ) {
    ^ @ ( Pool A E ) { ( shared_clone [( PoolImpl A E )] . p ctl ) }
}

@ Pool_drop [A E] sink ( Pool A E ) p → v {}

@ __pool_now → i { ^ / ( monotonic_ns ) 1000000 }

// A resource comes to rest on top of the idle stack. Lock held.
@ __pool_push_idle [A E] * ( PoolImpl A E ) p sink A x → v {
    ( vec_push [A] . p idle x )
    ( vec_push [i] . p since ( __pool_now ) )
}

@ pool_new [A : Send E] ( @ !A E ) make ( @ b A ) check PoolCfg cfg E timeout_err E closed_err → ( Pool A E ) {
    : ~ PoolCfg k cfg
    ? < . k max 1 { = . k max 1 } {}
    ? < . k min 0 { = . k min 0 } {}
    ? > . k min . k max { = . k min . k max } {}
    ^ @ ( Pool A E ) { ( shared_new [( PoolImpl A E )] @ ( PoolImpl A E ) {
            ( mutex_new )
            ( cond_new )
            ( vec_new [A] )
            ( vec_new [i] )
            0
            k
            make
            check
            timeout_err
            closed_err
            ( vec_new [i] )
            0
            F
        } ) }
}

// Wake the oldest waiter, if any: a resource came back, or a place for a
// new one opened. A fiber whose deadline beat the wake is already on its
// way back to look for itself, so nothing is lost. Lock held.
@ __pool_wake_one [A E] * ( PoolImpl A E ) p → v {
    ? > ( vec_len [i] . p fibers ) 0 {
        ?? ( vec_remove [i] . p fibers 0 ) {
            T fh → { : i _w ( nurl_fiber_wake fh ) }
            F → {}
        }
        ^
    } {}
    ? > . p threads 0 { ( cond_signal . p c ) } {}
}

// Take the slots idle longer than idle_ms out of the stack — the oldest
// are at the bottom — keeping `live` at min or more. They go into `dead`
// for the caller to drop once the lock is let go. Lock held.
@ __pool_take_expired [A E] * ( PoolImpl A E ) p i now ( Vec A ) dead → v {
    : i ttl . . p cfg idle_ms
    ? <= ttl 0 { ^ } {}
    ~ & > ( vec_len [A] . p idle ) 0 > . p live . . p cfg min {
        ? <= - now ( vec_at [i] . p since 0 ) ttl { break } {}
        : ?i _t ( vec_remove [i] . p since 0 )
        ?? ( vec_remove [A] . p idle 0 ) {
            T x → { ( vec_push [A] dead x ) }
            F → {}
        }
        = . p live - . p live 1
        // (A place to make one opened: a waiter may want it.)
        ( __pool_wake_one [A E] p )
    }
}

@ pool_get [A E] ( Pool A E ) pool → !( Pooled A E ) E {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    ^ ( pool_get_ms [A E] pool . . p cfg wait_ms )
}

// Check a resource out, waiting at most `ms` milliseconds (< 0: no
// bound, 0: no wait) for one to come back when all `max` are lent.
@ pool_get_ms [A E] ( Pool A E ) pool i ms → !( Pooled A E ) E {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    : i start ( __pool_now )
    : i deadline ? < ms 0 -1 + start ms
    : ( Vec A ) dead ( vec_new [A] )
    ( mutex_lock . p m )
    ~ T {
        ? . p closed {
            ( mutex_unlock . p m )
            ^ @ !( Pooled A E ) E { F ( mem_dup . p closed_err ) }
        } {}
        : i now ( __pool_now )
        ( __pool_take_expired [A E] p now dead )
        ?? ( vec_pop [A] . p idle ) {
            T x → {
                : ?i _t ( vec_pop [i] . p since )
                ( mutex_unlock . p m )
                ^ @ !( Pooled A E ) E { T @ ( Pooled A E ) { ( shared_clone [( PoolImpl A E )] . pool ctl ) x } }
            }
            F → {}
        }
        ? < . p live . . p cfg max {
            // Reserve the place, then make the resource unlocked.
            = . p live + . p live 1
            ( mutex_unlock . p m )
            : ( @ !A E ) mk . p make
            ?? ( mk ) {
                T x → { ^ @ !( Pooled A E ) E { T @ ( Pooled A E ) { ( shared_clone [( PoolImpl A E )] . pool ctl ) x } } }
                F e → {
                    ( mutex_lock . p m )
                    = . p live - . p live 1
                    ( __pool_wake_one [A E] p )
                    ( mutex_unlock . p m )
                    ^ @ !( Pooled A E ) E { F e }
                }
            }
        } {}
        // All `max` are lent: wait for one to come back.
        ? & >= deadline 0 >= now deadline {
            ( mutex_unlock . p m )
            ^ @ !( Pooled A E ) E { F ( mem_dup . p timeout_err ) }
        } {}
        : i left ? < deadline 0 -1 - deadline now
        : i fcur ( nurl_fiber_current )
        : ~ b parked F
        ? != fcur 0 {
            ( vec_push [i] . p fibers fcur )
            : i rc ( nurl_fiber_park_with_mutex_ms # i ( mutex_raw . p m ) left )
            ? >= rc 0 {
                = parked T
                ( mutex_lock . p m )
                // Timed out (or woken by close): still queued — leave.
                : i nf ( vec_len [i] . p fibers )
                : ~ i k 0
                ~ < k nf {
                    ? == ( vec_at [i] . p fibers k ) fcur {
                        : ?i _gone ( vec_remove [i] . p fibers k )
                        break
                    } {}
                    = k + k 1
                }
            } {
                // No fiber backend after all: the mutex is still held.
                : ?i _back ( vec_pop [i] . p fibers )
            }
        } {}
        ? ! parked {
            = . p threads + . p threads 1
            : b _sig ( cond_wait_ms . p c . p m left )
            = . p threads - . p threads 1
        } {}
    }
}

// The resource, lent for as long as the guard lives.
@ pooled_get [A E] ( Pooled A E ) g → A { ^ . g val }

// The guard's drop: the resource goes back, unless the check refuses it
// or the pool closed — then it is dropped here, unlocked, and its place
// freed for a new one.
@ Pooled_drop [A E] sink ( Pooled A E ) g → v {
    // This IS the drop: the guard's two owned fields are taken over here.
    ( mem_forget g )
    : ( Shared ( PoolImpl A E ) ) sh . g ctl
    ( mem_take sh )
    : A x . g val
    ( mem_take x )
    ( __pool_return [A E] sh x F )
}

// Drop the resource instead of returning it (the caller saw it fail);
// its place is free for a new one.
@ pool_discard [A E] sink ( Pooled A E ) g → v {
    ( mem_forget g )
    : ( Shared ( PoolImpl A E ) ) sh . g ctl
    ( mem_take sh )
    : A x . g val
    ( mem_take x )
    ( __pool_return [A E] sh x T )
}

// A resource coming back: onto the idle stack, or — discarded, refused by
// the check, or the pool closed — dropped at the end, with no lock held
// (its drop may do I/O), its place freed. The pool owner `sh` goes last.
@ __pool_return [A E] sink ( Shared ( PoolImpl A E ) ) sh sink A x b gone → v {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] sh )
    : ~ b keep ! gone
    ? keep {
        : ( @ b A ) ck . p check
        = keep ( ck x )
    } {}
    ( mutex_lock . p m )
    ? & keep ! . p closed {
        ( __pool_push_idle [A E] p x )
    } {
        = . p live - . p live 1
    }
    ( __pool_wake_one [A E] p )
    ( mutex_unlock . p m )
}

// Make resources until `min` are alive (a warm start). The first
// factory error is handed back; what was made by then stays.
@ pool_fill [A E] ( Pool A E ) pool → !v E {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    ~ T {
        ( mutex_lock . p m )
        ? | . p closed >= . p live . . p cfg min {
            ( mutex_unlock . p m )
            ^ @ !v E { T 0 }
        } {}
        = . p live + . p live 1
        ( mutex_unlock . p m )
        : ( @ !A E ) mk . p make
        ?? ( mk ) {
            T x → {
                ( mutex_lock . p m )
                ( __pool_push_idle [A E] p x )
                ( __pool_wake_one [A E] p )
                ( mutex_unlock . p m )
            }
            F e → {
                ( mutex_lock . p m )
                = . p live - . p live 1
                ( mutex_unlock . p m )
                ^ @ !v E { F e }
            }
        }
    }
    ^ @ !v E { T 0 }
}

// Drop the resources idle longer than idle_ms (down to min alive) and
// say how many went. A checkout and a return do this too; a pool that
// sits unused needs a caller — a maintenance fiber, say — to do it.
@ pool_evict_idle [A E] ( Pool A E ) pool → i {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    : ( Vec A ) dead ( vec_new [A] )
    ( mutex_lock . p m )
    ( __pool_take_expired [A E] p ( __pool_now ) dead )
    ( mutex_unlock . p m )
    ^ ( vec_len [A] dead )
}

// No more checkouts: every waiter is woken and gets closed_err, the idle
// resources are dropped now, and the lent ones when they come back.
@ pool_close [A E] ( Pool A E ) pool → v {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    : ~ ( Vec A ) dead ( vec_new [A] )
    ( mutex_lock . p m )
    = . p closed T
    ~ > ( vec_len [A] . p idle ) 0 {
        ?? ( vec_pop [A] . p idle ) {
            T x → { ( vec_push [A] dead x ) = . p live - . p live 1 }
            F → {}
        }
    }
    ( vec_clear [i] . p since )
    ~ > ( vec_len [i] . p fibers ) 0 { ( __pool_wake_one [A E] p ) }
    ( cond_broadcast . p c )
    ( mutex_unlock . p m )
}

// Resources alive: lent, idle and being made.
@ pool_live [A E] ( Pool A E ) pool → i {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    ( mutex_lock . p m )
    : i n . p live
    ( mutex_unlock . p m )
    ^ n
}

@ pool_idle [A E] ( Pool A E ) pool → i {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    ( mutex_lock . p m )
    : i n ( vec_len [A] . p idle )
    ( mutex_unlock . p m )
    ^ n
}

// Callers waiting for a resource, fibers and threads.
@ pool_waiting [A E] ( Pool A E ) pool → i {
    : *( PoolImpl A E ) p ( shared_ptr [( PoolImpl A E )] . pool ctl )
    ( mutex_lock . p m )
    : i n + ( vec_len [i] . p fibers ) . p threads
    ( mutex_unlock . p m )
    ^ n
}
