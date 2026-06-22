// dist_liveness.nu — offline test for §7.5 Phase 10 self-refutation. A node
// suspected while busy (it missed pings) bumps its incarnation on hearing the
// suspicion, and the Alive heartbeat it then gossips — carrying the higher
// incarnation — reinstates it on its peers. Deterministic, no sockets.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/membership.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }

@ cpy ( Vec u ) v → ( Vec u ) { : ( Vec u ) o ( vec_new [u] ) ( vec_extend [u] o v ) ^ o }

// a one-member gossip message: {pk, state, inc}
@ gossip1 ( Vec u ) pk i st i inc → PkMsg {
    : ( Vec s ) g ( vec_new [s] )
    : *PkMember m # *PkMember ( nurl_alloc Z PkMember )
    = . m pubkey ( cpy pk )
    = . m state st = . m incarnation inc
    = . m last_ns 0 = . m susp_start_ns 0 = . m susp_confirms 0
    ( vec_push [s] g # s m )
    ^ @ PkMsg { ( pk_ping ) 0 ( vec_new [u] ) g }
}
// gossip carrying a node's self-heartbeat fact
@ heartbeat_of * PkMemberTable t → PkMsg {
    : ( Vec s ) g ( vec_new [s] )
    ( vec_push [s] g # s ( pktable_self_fact t ) )
    ^ @ PkMsg { ( pk_ping ) 0 ( vec_new [u] ) g }
}

@ main → i {
    : ( Vec u ) bpk ( mkpk 50 )
    : ( Vec u ) apk ( mkpk 10 )

    // ── B refutes a suspicion of itself ──────────────────────────
    : *PkMemberTable bt ( pktable_new bpk 1000 5000 3 8 )
    ( pb `B starts at incarnation 0: ` == ( pktable_self_incarnation bt ) 0 )
    // a peer's gossip says B is SUSPECT at inc 0 → B must refute
    : PkMsg sus ( gossip1 bpk ( pk_suspect ) 0 )
    ( pktable_apply_gossip bt sus 0 )
    ( pkmsg_free sus )
    ( pb `B bumped incarnation on self-suspicion: ` == ( pktable_self_incarnation bt ) 1 )
    // gossip that B is alive at inc 0 does NOT bump (no false escalation)
    : PkMsg ok ( gossip1 bpk ( pk_alive ) 9 )
    ( pktable_apply_gossip bt ok 0 )
    ( pkmsg_free ok )
    ( pb `alive-self gossip does not bump: ` == ( pktable_self_incarnation bt ) 1 )
    // refute is monotonic: a lower observed inc is ignored, a higher bumps past
    ( pb `refute ignores stale inc: ` ! ( pktable_refute bt 0 ) )
    ( pb `refute bumps past higher inc: ` ( pktable_refute bt 7 ) )
    ( pb `incarnation now 8: ` == ( pktable_self_incarnation bt ) 8 )

    // ── A had B suspected; B's heartbeat reinstates it ───────────
    : *PkMemberTable at ( pktable_new apk 1000 5000 3 8 )
    ( pktable_apply at bpk ( pk_alive ) 0 0 )
    ( pktable_suspect at bpk 0 )
    ( pb `A locally suspects B: ` == ( pktable_state_of at bpk ) ( pk_suspect ) )
    // B (now at a high incarnation) gossips its alive heartbeat to A
    : PkMsg hb ( heartbeat_of bt )
    ( pktable_apply_gossip at hb 100 )
    ( pkmsg_free hb )
    ( pb `B's heartbeat reinstates B as alive on A: ` == ( pktable_state_of at bpk ) ( pk_alive ) )
    // a STALE suspicion at the old incarnation can't re-suspect the reinstated B
    : PkMsg stale ( gossip1 bpk ( pk_suspect ) 0 )
    ( pktable_apply_gossip at stale 200 )
    ( pkmsg_free stale )
    ( pb `stale suspicion (old inc) is ignored: ` == ( pktable_state_of at bpk ) ( pk_alive ) )

    ( pktable_free bt ) ( pktable_free at )
    ( vec_free [u] bpk ) ( vec_free [u] apk )
    ^ 0
}
