// membership_fd.nu — offline scenario test for stdlib/net/failuredetector.nu.
// Deterministic, time-injected, no sockets: drives the probe state machine
// through a healthy probe, an escalation to ping-req → suspect → dead, and
// the key mobile case — a LATE direct ack (a wifi↔cellular roam) keeps a
// member alive instead of letting it be declared dead.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/net/failuredetector.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T t → # i t F → -1 } ?? ( vec_get [u] b k ) { T t → # i t F → -2 } { = e F } {} = k + k 1 }
    ^ e
}

@ main → i {
    : ( Vec u ) me ( mkpk 0 )
    : ( Vec u ) b ( mkpk 50 )
    : ( Vec u ) c ( mkpk 90 )

    // ── healthy probe: ping then ack ─────────────────────────────
    : *PkMemberTable t1 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t1 b ( pk_alive ) 1 0 )
    ( pktable_apply t1 c ( pk_alive ) 1 0 )
    // fd: period 1000, direct-timeout 300, total-timeout 600, k 2
    : *FdState fd1 ( fd_new # s t1 1000 300 600 2 )
    : FdAction a1 ( fd_tick fd1 0 )
    ( pb `t=0 emits ping: ` == . a1 kind ( fd_do_ping ) )
    ( pb `ping target is a member: ` | ( veq . a1 target b ) ( veq . a1 target c ) )
    : i probed_seq . a1 seq
    ( pb `probing in flight: ` == ( fd_probing fd1 ) 1 )
    ( fd_action_free a1 )
    ( pb `direct ack clears probe: ` ( fd_on_ack fd1 probed_seq 50 ) )
    ( pb `probe cleared: ` == ( fd_probing fd1 ) 0 )
    ( fd_free fd1 ) ( pktable_free t1 )

    // ── escalate ping → ping-req → suspect → dead ────────────────
    : *PkMemberTable t2 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t2 b ( pk_alive ) 1 0 )
    ( pktable_apply t2 c ( pk_alive ) 1 0 )
    : *FdState fd2 ( fd_new # s t2 1000 300 600 2 )
    : FdAction p0 ( fd_tick fd2 0 )  // ping target X
    : ( Vec u ) tgt ( vec_with_cap [u] 32 ) ( vec_extend [u] tgt . p0 target )
    ( fd_action_free p0 )
    // no ack; at direct-timeout → ping-req
    : FdAction p1 ( fd_tick fd2 300 )
    ( pb `direct-timeout escalates to ping-req: ` == . p1 kind ( fd_do_preq ) )
    ( pb `ping-req re-targets same member: ` ( veq . p1 target tgt ) )
    ( pb `ping-req picks a relay: ` == ( vec_len [s] . p1 relays ) 1 )
    ( fd_action_free p1 )
    // still no ack; at total-timeout → suspect (no action)
    : FdAction p2 ( fd_tick fd2 600 )
    ( pb `total-timeout emits no action: ` == . p2 kind ( fd_none ) )
    ( fd_action_free p2 )
    ( pb `member now suspected: ` == ( pktable_state_of t2 tgt ) ( pk_suspect ) )
    ( pb `failed probe bumped LHM: ` == ( lh_value_of t2 ) 1 )
    // sweep: lone suspicion, LHM 1 → ceiling 5000*2 = 10000 from t=600
    : ( Vec s ) sd0 ( fd_sweep fd2 5000 )
    ( pb `not dead before scaled ceiling: ` == ( vec_len [s] sd0 ) 0 )
    ( _pk_dead_free sd0 )
    : ( Vec s ) sd1 ( fd_sweep fd2 11000 )
    ( pb `dead after scaled ceiling: ` & == ( vec_len [s] sd1 ) 1 == ( pktable_state_of t2 tgt ) ( pk_dead ) )
    ( _pk_dead_free sd1 )
    ( vec_free [u] tgt )
    ( fd_free fd2 ) ( pktable_free t2 )

    // ── forced network change: a LATE ack keeps the member alive ─
    : *PkMemberTable t3 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t3 b ( pk_alive ) 1 0 )
    : *FdState fd3 ( fd_new # s t3 1000 300 600 2 )
    : FdAction q0 ( fd_tick fd3 0 )  // ping b, seq known
    : i bseq . q0 seq
    ( fd_action_free q0 )
    : FdAction q1 ( fd_tick fd3 300 )  // escalate to ping-req (b slow)
    ( pb `roam: escalated to ping-req: ` == . q1 kind ( fd_do_preq ) )
    ( fd_action_free q1 )
    // ack finally arrives at t=500 (< total-timeout 600): roam recovered
    ( pb `late ack accepted: ` ( fd_on_ack fd3 bseq 500 ) )
    : FdAction q2 ( fd_tick fd3 600 )  // would-be suspect time
    ( fd_action_free q2 )
    : ( Vec s ) sd2 ( fd_sweep fd3 50000 )
    ( pb `member stayed ALIVE across the roam: ` & == ( vec_len [s] sd2 ) 0 == ( pktable_state_of t3 b ) ( pk_alive ) )
    ( _pk_dead_free sd2 )
    ( fd_free fd3 ) ( pktable_free t3 )

    ( vec_free [u] me ) ( vec_free [u] b ) ( vec_free [u] c )
    ^ 0
}
