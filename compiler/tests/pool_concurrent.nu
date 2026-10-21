// pool_concurrent.nu — std/pool.nu shared by threads, by fibers, and by
// both at once, with fewer resources than callers: every checkout is
// served, no more than `max` resources are ever lent at the same time, no
// more than `max` are ever made, and a wait bounded by a deadline ends at
// it — on a plain thread (cond_wait_ms) and on a fiber (the runtime's
// timed park), where a returning resource and the deadline race for the
// waiter.
// requires: live fibers

$ `stdlib/core/io.nu`
$ `stdlib/std/pool.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

: Res { i id Atomic inuse Atomic peak }

@ say s label i n → v {
    ( nurl_print label ) ( nurl_print ` ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
}

@ make_pool Atomic made Atomic inuse Atomic peak i max i wait → ( Pool Res PoolErr ) {
    ^ ( pool_new [Res PoolErr]
    \ → !Res PoolErr { ^ @ !Res PoolErr { T @ Res { ( atomic_add made 1 ) inuse peak } } }
    \ Res r → b { ^ T }
    @ PoolCfg { 0 max wait 0 }
    # PoolErr PoolTimeout
    # PoolErr PoolClosed )
}

// One checkout: count it in use while held, note the peak, let others in.
@ use_one ( Pool Res PoolErr ) p Atomic ok b fiber → v {
    ?? ( pool_get [Res PoolErr] p ) {
        T g → {
            : Res r ( pooled_get [Res PoolErr] g )
            : i now + ( atomic_add . r inuse 1 ) 1
            : i _m ( atomic_max . r peak now )
            ? fiber { ( yield ) } {}
            : i _d ( atomic_sub . r inuse 1 )
            : i _k ( atomic_add ok 1 )
        }
        F _ → {}
    }
}

@ main → i {
    // ── threads: 8 × 2000 checkouts over 3 resources ──
    : Atomic made ( atomic_new 0 )
    : Atomic inuse ( atomic_new 0 )
    : Atomic peak ( atomic_new 0 )
    : Atomic ok ( atomic_new 0 )
    : ( Pool Res PoolErr ) p ( make_pool made inuse peak 3 -1 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        ?? ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 2000 { ( use_one p ok F ) = k + k 1 }
        } ) { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( say `threads: served` ( atomic_load ok ) )
    ( say `threads: at most 3 at once` ? <= ( atomic_load peak ) 3 1 0 )
    ( say `threads: at most 3 made` ? <= ( atomic_load made ) 3 1 0 )
    ( say `threads: none lent now` - ( pool_live [Res PoolErr] p ) ( pool_idle [Res PoolErr] p ) )

    // A thread's wait bounded at 30 ms, with every resource held.
    : Atomic made1 ( atomic_new 0 )
    : ( Pool Res PoolErr ) one ( make_pool made1 inuse peak 1 30 )
    {
        : !( Pooled Res PoolErr ) PoolErr held ( pool_get [Res PoolErr] one )
        : i t0 / ( monotonic_ns ) 1000000
        ?? ( pool_get [Res PoolErr] one ) {
            T g → { ( say `thread wait: got one` 1 ) }
            F e → { ( nurl_print `thread wait: ` ) ( nurl_print ( pool_err_name e ) ) ( nurl_print `\n` ) }
        }
        ( say `thread wait: waited its bound` ? >= - / ( monotonic_ns ) 1000000 t0 30 1 0 )
    }

    // ── fibers: 64 × 200 checkouts over 3 resources, 4 workers ──
    ( runtime_init 4 )
    : Atomic fmade ( atomic_new 0 )
    : Atomic fpeak ( atomic_new 0 )
    : Atomic fok ( atomic_new 0 )
    : ( Pool Res PoolErr ) fp ( make_pool fmade inuse fpeak 3 -1 )
    : ~ i f 0
    ~ < f 64 {
        ( spawn \ → v {
            : ~ i k 0
            ~ < k 200 { ( use_one fp fok T ) = k + k 1 }
        } )
        = f + f 1
    }
    ( runtime_run )
    ( say `fibers: served` ( atomic_load fok ) )
    ( say `fibers: at most 3 at once` ? <= ( atomic_load fpeak ) 3 1 0 )
    ( say `fibers: at most 3 made` ? <= ( atomic_load fmade ) 3 1 0 )

    // A fiber holds the only resource for 100 ms: a fiber waiting 20 ms
    // times out; one waiting 2 s gets it when it comes back.
    : Atomic made2 ( atomic_new 0 )
    : ( Pool Res PoolErr ) solo ( make_pool made2 inuse peak 1 -1 )
    : Atomic timed_out ( atomic_new 0 )
    : Atomic served ( atomic_new 0 )
    ( spawn \ → v {
        ?? ( pool_get [Res PoolErr] solo ) { T g → { ( sleep_ms 100 ) } F _ → {} }
    } )
    ( spawn \ → v {
        ( sleep_ms 10 )
        ?? ( pool_get_ms [Res PoolErr] solo 20 ) {
            T g → {}
            F e → { ?? e { PoolTimeout → { : i _t ( atomic_add timed_out 1 ) } _ → {} } }
        }
    } )
    ( spawn \ → v {
        ( sleep_ms 10 )
        ?? ( pool_get_ms [Res PoolErr] solo 2000 ) { T g → { : i _s ( atomic_add served 1 ) } F _ → {} }
    } )
    ( runtime_run )
    ( say `fiber wait: timed out` ( atomic_load timed_out ) )
    ( say `fiber wait: served after the return` ( atomic_load served ) )

    // Deadlines racing returns: many short waits on one resource.
    : Atomic races ( atomic_new 0 )
    = f 0
    ~ < f 96 {
        ( spawn \ → v {
            ?? ( pool_get_ms [Res PoolErr] solo 1 ) { T g → { ( yield ) } F _ → {} }
            : i _r ( atomic_add races 1 )
        } )
        = f + f 1
    }
    ( runtime_run )
    ( say `racing waits: all returned` ( atomic_load races ) )
    ( say `racing waits: nobody left waiting` ( pool_waiting [Res PoolErr] solo ) )

    // ── threads and fibers on one pool ──
    : Atomic mmade ( atomic_new 0 )
    : Atomic mpeak ( atomic_new 0 )
    : Atomic mok ( atomic_new 0 )
    : ( Pool Res PoolErr ) mp ( make_pool mmade inuse mpeak 2 -1 )
    = f 0
    ~ < f 16 {
        ( spawn \ → v { : ~ i k 0 ~ < k 100 { ( use_one mp mok T ) = k + k 1 } } )
        = f + f 1
    }
    : ( Vec Thread ) ts2 ( vec_new [Thread] )
    = t 0
    ~ < t 4 {
        ?? ( thread_spawn \ → v { : ~ i k 0 ~ < k 400 { ( use_one mp mok F ) = k + k 1 } } ) { T th → { ( vec_push [Thread] ts2 th ) } F _ → {} }
        = t + t 1
    }
    ~ th ts2 { ( thread_join th ) }
    ( runtime_run )
    ( say `mixed: served` ( atomic_load mok ) )
    ( say `mixed: at most 2 at once` ? <= ( atomic_load mpeak ) 2 1 0 )
    ( runtime_shutdown )
    ^ 0
}
