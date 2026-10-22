// pool_basic.nu — std/pool.nu on one thread: when a resource is made,
// reused, waited for, refused, discarded, evicted, and what a closed pool
// says. A checkout is a guard: it gives its resource back when it goes —
// at the end of the block that holds it — and nothing is returned by hand.
//
// A resource carries an id the factory hands out from a counter; `made`
// counts the factory's calls and `drops` the resources' drops (a % Drop),
// so every way a resource ends is seen to happen exactly once. The second
// pool holds Strings: a payload that owns memory, which the guard must
// still give back (a generic instance only the pool's functions name).

$ `stdlib/core/io.nu`
$ `stdlib/std/pool.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`

: Res { i id Atomic drops }

% Drop Res {
    @ drop Res r → v { : i _d ( atomic_add . r drops 1 ) }
}

: | ResErr { ResTimeout ResClosed ResRefused }

@ err_name ResErr e → s {
    ^ ?? e { ResTimeout → `ResTimeout` ResClosed → `ResClosed` ResRefused → `ResRefused` }
}

@ say s label i n → v {
    ( nurl_print label ) ( nurl_print ` ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
}

@ make_pool Atomic made Atomic drops Atomic refuse Atomic poison PoolCfg cfg → ( Pool Res ResErr ) {
    ^ ( pool_new [Res ResErr]
    \ → !Res ResErr {
        ? != 0 ( atomic_load refuse ) { ^ @ !Res ResErr { F # ResErr ResRefused } } {}
        : i n ( atomic_add made 1 )
        ^ @ !Res ResErr { T @ Res { + n 1 drops } }
    }
    \ Res r → b { ^ != . r id ( atomic_load poison ) }
    cfg
    # ResErr ResTimeout
    # ResErr ResClosed )
}

// The id a checkout got (given straight back), or -1 with the error's name.
@ take ( Pool Res ResErr ) p i ms → i {
    ?? ( pool_get_ms [Res ResErr] p ms ) {
        T g → { ^ . ( pooled_get [Res ResErr] g ) id }
        F e → { ( nurl_print `  error ` ) ( nurl_print ( err_name e ) ) ( nurl_print `\n` ) ^ -1 }
    }
}

@ main → i {
    : Atomic made ( atomic_new 0 )
    : Atomic drops ( atomic_new 0 )
    : Atomic refuse ( atomic_new 0 )
    : Atomic poison ( atomic_new 0 )
    : ( Pool Res ResErr ) p ( make_pool made drops refuse poison @ PoolCfg { 1 2 0 0 } )

    // Made lazily; one given back is lent again.
    ( say `first` ( take p 0 ) )
    ( say `again` ( take p 0 ) )
    ( say `made` ( atomic_load made ) )
    ( say `live` ( pool_live [Res ResErr] p ) )
    ( say `idle` ( pool_idle [Res ResErr] p ) )

    {
        // Two lent at once: the second is made; a third waits 0 ms and is
        // refused, then 30 ms, and is refused again.
        : !( Pooled Res ResErr ) ResErr ga ( pool_get [Res ResErr] p )
        : !( Pooled Res ResErr ) ResErr gb ( pool_get [Res ResErr] p )
        ( say `made` ( atomic_load made ) )
        ( say `third` ( take p 0 ) )
        : i t0 / ( monotonic_ns ) 1000000
        ( say `third-30ms` ( take p 30 ) )
        : i waited - / ( monotonic_ns ) 1000000 t0
        ( say `waited-at-least-30` ? >= waited 30 1 0 )
        ( say `live` ( pool_live [Res ResErr] p ) )
    }
    ( say `idle-after-block` ( pool_idle [Res ResErr] p ) )

    // Discarded: dropped now, its place free for a new one.
    ?? ( pool_get [Res ResErr] p ) {
        T g → { ( pool_discard [Res ResErr] g ) }
        F _ → {}
    }
    ( say `dropped` ( atomic_load drops ) )
    ( say `live` ( pool_live [Res ResErr] p ) )

    // The factory fails: its own error comes back, nothing counts as live.
    ( atomic_store refuse 1 )
    {
        : !( Pooled Res ResErr ) ResErr h1 ( pool_get [Res ResErr] p )
        ( say `refused` ( take p 0 ) )
        ( say `live` ( pool_live [Res ResErr] p ) )
    }
    ( atomic_store refuse 0 )

    // The check refuses a resource coming back (its id is poisoned): it is
    // dropped, and its place freed.
    : i before ( atomic_load drops )
    ?? ( pool_get [Res ResErr] p ) {
        T g → {
            : i id . ( pooled_get [Res ResErr] g ) id
            ( atomic_store poison id )
        }
        F _ → {}
    }
    ( say `dropped-on-return` - ( atomic_load drops ) before )
    ( say `live` ( pool_live [Res ResErr] p ) )
    ( atomic_store poison 0 )

    // Idle eviction: idle 20 ms, kept down to min = 1.
    : Atomic made2 ( atomic_new 0 )
    : Atomic drops2 ( atomic_new 0 )
    : ( Pool Res ResErr ) q ( make_pool made2 drops2 refuse poison @ PoolCfg { 1 3 0 20 } )
    ( say `fill` ?? ( pool_fill [Res ResErr] q ) { T _ → 1 F _ → 0 } )
    ( say `filled` ( pool_idle [Res ResErr] q ) )
    {
        : !( Pooled Res ResErr ) ResErr q1 ( pool_get [Res ResErr] q )
        : !( Pooled Res ResErr ) ResErr q2 ( pool_get [Res ResErr] q )
        : !( Pooled Res ResErr ) ResErr q3 ( pool_get [Res ResErr] q )
    }
    ( say `idle-before` ( pool_idle [Res ResErr] q ) )
    ( sleep_ms 60 )
    ( say `evicted` ( pool_evict_idle [Res ResErr] q ) )
    ( say `idle-after` ( pool_idle [Res ResErr] q ) )
    ( say `dropped2` ( atomic_load drops2 ) )

    // Closed: no checkout; the idle ones are dropped now, a lent one when
    // it comes back.
    {
        : !( Pooled Res ResErr ) ResErr lent ( pool_get [Res ResErr] q )
        ( pool_close [Res ResErr] q )
        ( say `closed-get` ( take q 0 ) )
        ( say `live-closed` ( pool_live [Res ResErr] q ) )
    }
    ( say `live-returned` ( pool_live [Res ResErr] q ) )
    ( say `dropped2` ( atomic_load drops2 ) )
    ( say `made2` ( atomic_load made2 ) )

    // A pool of Strings: the guard hands back a payload that owns memory.
    : Atomic smade ( atomic_new 0 )
    : ( Pool String PoolErr ) sp ( pool_new [String PoolErr]
    \ → !String PoolErr {
        : String t ( string_from `conn-` )
        ( string_push_int t ( atomic_add smade 1 ) )
        ^ @ !String PoolErr { T t }
    }
    \ String t → b { ^ T }
    @ PoolCfg { 0 2 0 0 }
    # PoolErr PoolTimeout
    # PoolErr PoolClosed )
    ?? ( pool_get [String PoolErr] sp ) {
        T g → { ( nurl_print `string ` ) ( nurl_print ( string_data ( pooled_get [String PoolErr] g ) ) ) ( nurl_print `\n` ) }
        F e → { ( nurl_print ( pool_err_name e ) ) }
    }
    ( say `string-idle` ( pool_idle [String PoolErr] sp ) )
    ?? ( pool_get [String PoolErr] sp ) {
        T g → { ( nurl_print `string again ` ) ( nurl_print ( string_data ( pooled_get [String PoolErr] g ) ) ) ( nurl_print `\n` ) }
        F e → {}
    }
    ( say `string-made` ( atomic_load smade ) )
    ^ 0
}
