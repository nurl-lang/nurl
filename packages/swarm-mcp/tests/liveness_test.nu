// packages/swarm-mcp/tests/liveness_test.nu — offline tests for membership
// liveness: the HELLO heartbeat stamp, eviction of a silent worker from the
// roster AND the ring, the self-exemption every node depends on, and the
// failed-chunk reason suffix workers append to a result frame. Run from the
// package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/liveness_test.nu /tmp/lt && /tmp/lt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/random.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/dist/ring.nu`
$ `src/census.nu`
$ `src/blob.nu`
$ `src/token.nu`
$ `src/wasmkernel.nu`

: ~ i g_fail 0

@ pb s label b ok → v {
    ( nurl_print label ) ( nurl_print ? ok ` PASS\n` ` FAIL\n` )
    ? ok {} { = g_fail + g_fail 1 }
}

@ mkpk i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] v # u & + * seed 31 k 255 ) = k + k 1 }
    ^ v
}

@ main → i {
    : ( Vec u ) a ( mkpk 1 )
    : ( Vec u ) b ( mkpk 2 )
    : ( Vec u ) self ( mkpk 3 )
    : ( Vec u ) none ( vec_new [u] )
    : *Roster r ( roster_new )
    : *Ring ring ( ring_new )

    // Three workers join at t=1000.
    ( roster_add r ring a 1 8 0 1000 )
    ( roster_add r ring b 2 8 ( cap_gpu ) 1000 )
    ( roster_add r ring self 3 8 0 1000 )
    ( pb `three members joined:            ` == ( roster_count r ) 3 )
    ( pb `ring carries every member:       ` == ( ring_point_count ring ) 24 )

    // `a` keeps heartbeating; `b` goes silent.
    ( roster_touch r a 50000 )
    ( roster_touch r self 50000 )

    // Nothing expires before the TTL.
    : ( Vec ( Vec u ) ) g0 ( roster_expire r 51000 90000 self )
    ( pb `no eviction inside the TTL:      ` == ( vec_len [( Vec u )] g0 ) 0 )
    ( vec_free [( Vec u )] g0 )

    // `a` heartbeats again just before the sweep; `b` has now been silent for
    // 99 s. Past the TTL only the silent one goes — and the exempt self never
    // does, even though it is just as silent (a node hears no HELLO of its own).
    ( roster_touch r a 99000 )
    : ( Vec ( Vec u ) ) g1 ( roster_expire r 100000 45000 self )
    ( pb `silent member evicted:           ` == ( vec_len [( Vec u )] g1 ) 1 )
    ( pb `the evicted one is b:            ` ?? ( vec_get [( Vec u )] g1 0 ) { T pk → ( bytes_eq pk b ) F → F } )
    ( pb `roster is down to two:           ` == ( roster_count r ) 2 )
    ( pb `heartbeating member survives:    ` ( roster_is_live r a ) )
    ( pb `self is exempt from expiry:      ` ( roster_is_live r self ) )
    ( pb `evicted member is not live:      ` ? ( roster_is_live r b ) F T )

    // The caller applies the removals to its rings — the roster is the source
    // of truth, so this is what keeps routing off a dead node.
    : ~ i gi 0
    ~ < gi ( vec_len [( Vec u )] g1 ) {
        ?? ( vec_get [( Vec u )] g1 gi ) { T pk → { ( ring_remove_member ring pk ) ( vec_free [u] pk ) } F → {} }
        = gi + gi 1
    }
    ( vec_free [( Vec u )] g1 )
    ( pb `ring loses the evicted points:   ` == ( ring_point_count ring ) 16 )
    ( pb `gpu count drops with the member: ` == ( roster_count_caps r ( cap_gpu ) ) 0 )

    // A re-heard HELLO brings a worker back (eviction is self-healing).
    ( pb `evicted worker can rejoin:       ` ( roster_add r ring b 2 8 ( cap_gpu ) 120000 ) )
    ( pb `rejoin restores the ring:        ` == ( ring_point_count ring ) 24 )

    // roster_view is what swarm_status reports.
    : MemberView mv ( roster_view r 0 )
    ( pb `roster_view reports the node id: ` != . mv id 0 )
    : MemberView oob ( roster_view r 99 )
    ( pb `roster_view out of range is 0:   ` == . oob id 0 )

    ( roster_free r ) ( ring_free ring )
    ( vec_free [u] a ) ( vec_free [u] b ) ( vec_free [u] self ) ( vec_free [u] none )

    // ── failed-chunk reason suffix ────────────────────────────────
    // A worker appends WHY a chunk failed after the existing frame, so an old
    // reader (fixed leading offsets) is unaffected and a new one recovers it.
    : ( Vec u ) frame ( vec_new [u] )
    ( vec_push [u] frame 0 )
    ( bytes_push_u64_be frame # u64 0 )
    : i base ( vec_len [u] frame )
    ( chunk_err_push frame `wasmtime: bad section size` )
    : String got ( chunk_err_read frame )
    ( pb `reason survives the round trip:  ` != 0 ( nurl_str_eq ( string_data got ) `wasmtime: bad section size` ) )
    ( pb `the frame prefix is untouched:   ` & == base 9 == ?? ( vec_get [u] frame 0 ) { T x → # i x F → 9 } 0 )
    ( string_free got )
    ( vec_free [u] frame )

    // A frame with no suffix reads back as empty, not as garbage.
    : ( Vec u ) plain ( vec_new [u] )
    ( vec_push [u] plain 1 )
    ( bytes_push_u64_be plain # u64 12345 )
    : String nothing ( chunk_err_read plain )
    ( pb `no suffix → empty reason:        ` == ( string_len nothing ) 0 )
    ( string_free nothing )
    ( vec_free [u] plain )

    ( nurl_print ? == g_fail 0 `ALL PASS\n` `FAILURES\n` )
    ^ ? == g_fail 0 0 1
}
