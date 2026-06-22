// membership.nu — offline test for stdlib/net/membership.nu. Deterministic,
// time-injected: SWIM merge precedence, Lifeguard suspect→sweep (confirmation
// + local-health scaling), round-robin probe pick, and the gossip codec.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/membership.nu`

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

    // ── SWIM merge precedence ────────────────────────────────────
    : *PkMemberTable t ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t b ( pk_alive ) 1 0 )
    ( pb `new member alive: ` == ( pktable_state_of t b ) ( pk_alive ) )
    ( pktable_apply t b ( pk_suspect ) 1 0 )
    ( pb `suspect overrides alive @ same inc: ` == ( pktable_state_of t b ) ( pk_suspect ) )
    ( pktable_apply t b ( pk_alive ) 2 0 )
    ( pb `higher inc alive refutes suspect: ` == ( pktable_state_of t b ) ( pk_alive ) )
    ( pktable_apply t b ( pk_dead ) 2 0 )
    ( pb `dead overrides @ same inc: ` == ( pktable_state_of t b ) ( pk_dead ) )
    ( pktable_apply t b ( pk_alive ) 2 0 )
    ( pb `alive does NOT revive dead @ same inc: ` == ( pktable_state_of t b ) ( pk_dead ) )
    ( pktable_apply t b ( pk_alive ) 3 0 )
    ( pb `higher inc revives: ` == ( pktable_state_of t b ) ( pk_alive ) )
    ( pb `self facts ignored: ` ! ( pktable_apply t me ( pk_suspect ) 9 0 ) )
    ( pktable_free t )

    // ── lone suspicion: waits the full ceiling ───────────────────
    : *PkMemberTable t2 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t2 b ( pk_alive ) 1 0 )
    ( pktable_suspect t2 b 0 )
    : ( Vec s ) d1 ( pktable_sweep t2 4000 )
    ( pb `lone suspect alive before ceiling (t=4000): ` == ( vec_len [s] d1 ) 0 )
    ( __pk_dead_free d1 )
    : ( Vec s ) d2 ( pktable_sweep t2 6000 )
    ( pb `lone suspect dead after ceiling (t=6000): ` & == ( vec_len [s] d2 ) 1 == ( pktable_state_of t2 b ) ( pk_dead ) )
    ( __pk_dead_free d2 )
    ( pktable_free t2 )

    // ── corroborated suspicion: converges to the floor ───────────
    : *PkMemberTable t3 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t3 b ( pk_alive ) 1 0 )
    ( pktable_suspect t3 b 0 )
    ( pktable_confirm_suspect t3 b )
    ( pktable_confirm_suspect t3 b )
    ( pktable_confirm_suspect t3 b )
    : ( Vec s ) d3 ( pktable_sweep t3 1500 )
    ( pb `corroborated dead by t=1500 (floor 1000): ` == ( vec_len [s] d3 ) 1 )
    ( __pk_dead_free d3 )
    ( pktable_free t3 )

    // ── unhealthy node (high LHM) is slower to accuse ────────────
    : *PkMemberTable t4 ( pktable_new me 1000 5000 3 8 )
    ( pktable_on_probe_fail t4 )  // LHM 0→1 → timeouts ×2 (ceiling 10000)
    ( pb `LHM bumped to 1: ` == ( lh_value_of t4 ) 1 )
    ( pktable_apply t4 b ( pk_alive ) 1 0 )
    ( pktable_suspect t4 b 0 )
    : ( Vec s ) d4 ( pktable_sweep t4 6000 )
    ( pb `unhealthy node holds off at t=6000 (scaled ceiling 10000): ` == ( vec_len [s] d4 ) 0 )
    ( __pk_dead_free d4 )
    ( pktable_on_probe_ok t4 )  // LHM back to 0
    ( pb `probe ok restores health: ` == ( lh_value_of t4 ) 0 )
    ( pktable_free t4 )

    // ── round-robin probe pick over alive members ────────────────
    : *PkMemberTable t5 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t5 b ( pk_alive ) 1 0 )
    ( pktable_apply t5 c ( pk_alive ) 1 0 )
    : ?( Vec u ) p1 ( pktable_pick_probe t5 )
    : ?( Vec u ) p2 ( pktable_pick_probe t5 )
    ?? p1 { T x1 → {
            ?? p2 { T x2 → {
                    ( pb `two picks cover both members: ` | & ( veq x1 b ) ( veq x2 c ) & ( veq x1 c ) ( veq x2 b ) )
                    ( vec_free [u] x2 )
                } F → ( nurl_print `pick2 none\n` ) }
            ( vec_free [u] x1 )
        } F → ( nurl_print `pick1 none\n` ) }
    ( pktable_free t5 )

    // ── gossip message codec ─────────────────────────────────────
    : *PkMemberTable t6 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply t6 b ( pk_suspect ) 7 0 )
    ( pktable_apply t6 c ( pk_alive ) 4 0 )
    : ( Vec s ) g ( pktable_gossip t6 8 )
    : PkMsg msg @ PkMsg { ( pk_ping ) 12345 ( mkpk 200 ) g }
    : ( Vec u ) wire ( pkmsg_encode msg )
    : PkMsg dec ( pkmsg_decode wire )
    : ( Vec u ) want_target ( mkpk 200 )
    ( pb `msg type ping: ` == . dec mtype ( pk_ping ) )
    ( pb `msg seq: ` == . dec seq 12345 )
    ( pb `msg target preserved: ` ( veq . dec target want_target ) )
    ( vec_free [u] want_target )
    ( pb `gossip count 2: ` == ( vec_len [s] . dec gossip ) 2 )
    // apply the decoded gossip into a fresh table → states/incarnations land
    : *PkMemberTable t7 ( pktable_new me 1000 5000 3 8 )
    ( pktable_apply_gossip t7 dec 0 )
    ( pb `gossip applied: b suspect: ` == ( pktable_state_of t7 b ) ( pk_suspect ) )
    ( pb `gossip applied: c alive: ` == ( pktable_state_of t7 c ) ( pk_alive ) )
    ( pkmsg_free msg ) ( pkmsg_free dec ) ( vec_free [u] wire )
    ( pktable_free t6 ) ( pktable_free t7 )

    ( vec_free [u] me ) ( vec_free [u] b ) ( vec_free [u] c )
    ^ 0
}
