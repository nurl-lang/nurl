// dist_heartbeat.nu — offline test for stdlib/dist/heartbeat.nu payload
// construction (§7.5 Phase 10 Tier 1). The dedicated-thread firing is
// live-verified separately; here we check the payload a heartbeat sends: a
// gossip message carrying just this node's Alive self-fact at its current
// (possibly refuted) incarnation.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/dist/heartbeat.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T t → # i t F → -1 } ?? ( vec_get [u] b k ) { T t → # i t F → -2 } { = e F } {} = k + k 1 }
    ^ e
}

@ main → i {
    : ( Vec u ) b ( mkpk 50 )
    : *PkMemberTable t ( pktable_new b 1000 5000 3 8 )

    : ( Vec u ) p0 ( heartbeat_payload t )
    : PkMsg m0 ( pkmsg_decode p0 )
    ( pb `heartbeat is one gossip fact: ` == ( vec_len [s] . m0 gossip ) 1 )
    : s gp ?? ( vec_get [s] . m0 gossip 0 ) { T x → x F → # s 0 }
    : *PkMember gm # *PkMember gp
    ( pb `heartbeat = self alive @ inc 0: ` & & ( veq . gm pubkey b ) == . gm state ( pk_alive ) == . gm incarnation 0 )
    ( pkmsg_free m0 ) ( vec_free [u] p0 )

    // after refuting a suspicion, the heartbeat carries the bumped incarnation
    ( pktable_refute t 5 )
    : ( Vec u ) p1 ( heartbeat_payload t )
    : PkMsg m1 ( pkmsg_decode p1 )
    : s gp1 ?? ( vec_get [s] . m1 gossip 0 ) { T x → x F → # s 0 }
    : *PkMember gm1 # *PkMember gp1
    ( pb `heartbeat carries refuted incarnation 6: ` == . gm1 incarnation 6 )
    ( pkmsg_free m1 ) ( vec_free [u] p1 )

    ( pktable_free t ) ( vec_free [u] b )
    ^ 0
}
