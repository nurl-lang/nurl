// sim_membership.nu — first §7.5 Phase 13 chaos-harness scenario. Drives the
// REAL net/membership tables + gossip codec over dist/sim's deterministic bus:
//   (1) a death fact converges to every node despite 30% packet loss + reorder;
//   (2) a partition isolates a node from the fact, and healing reconverges it.
// Seeded → byte-reproducible; the assertions can genuinely fail.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/dist/sim.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ pk i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + id k ) = k + k 1 } ^ v }

@ node ( Vec s ) tables i i → *PkMemberTable { ^ # *PkMemberTable ?? ( vec_get [s] tables i ) { T x → x F → # s 0 } }

// build a node's gossip snapshot and submit it to a peer over the bus
@ send_gossip * SimNet net i src * PkMemberTable t i peer i now → v {
    : ( Vec s ) g ( pktable_gossip t 16 )
    : PkMsg m @ PkMsg { ( pk_ping ) 0 ( vec_new [u] ) g }
    : ( Vec u ) bytes ( pkmsg_encode m )
    ( sim_send net src peer bytes now )
    ( pkmsg_free m ) ( vec_free [u] bytes )
}

// deliver every due message, applying its gossip to the destination table
@ deliver_due * SimNet net ( Vec s ) tables i now → v {
    : ( Vec s ) due ( sim_due net now )
    : i dn ( vec_len [s] due )
    : ~ i k 0
    ~ < k dn {
        : s mp ?? ( vec_get [s] due k ) { T x → x F → # s 0 }
        ? != # i mp 0 {
            : *SimMsg msg # *SimMsg mp
            : PkMsg pm ( pkmsg_decode . msg bytes )
            ( pktable_apply_gossip ( node tables . msg dst ) pm now )
            ( pkmsg_free pm )
            ( sim_msg_free msg )
        } {}
        = k + k 1
    }
    ( vec_free [s] due )
}

// run `rounds` gossip ticks; node `dead_idx` is gone (never gossips)
@ run_rounds * SimNet net ( Vec s ) tables i rounds i dead_idx i now0 → i {
    : ~ i now now0
    : ~ i r 0
    ~ < r rounds {
        = now + now 1
        : ~ i i 0
        ~ < i 4 {
            ? != i dead_idx {
                : i peer % ( _sim_rand net ) 4
                ? != peer i { ( send_gossip net i ( node tables i ) peer now ) } {}
            } {}
            = i + i 1
        }
        ( deliver_due net tables now )
        = r + r 1
    }
    ^ now
}

@ knows_dead ( Vec s ) tables i idx ( Vec u ) deadpk → b { ^ == ( pktable_state_of ( node tables idx ) deadpk ) ( pk_dead ) }

@ make_tables → ( Vec s ) {
    : ( Vec s ) tables ( vec_new [s] )
    : ~ i i 0
    ~ < i 4 {
        : ( Vec u ) selfpk ( pk i )
        : *PkMemberTable t ( pktable_new selfpk 1000 5000 3 8 )
        ( vec_free [u] selfpk )
        // bootstrap: every node knows the other three, alive @ incarnation 1
        : ~ i j 0
        ~ < j 4 { ? != j i { : ( Vec u ) p ( pk j ) ( pktable_apply t p ( pk_alive ) 1 0 ) ( vec_free [u] p ) } {} = j + j 1 }
        ( vec_push [s] tables # s t )
        = i + i 1
    }
    ^ tables
}

@ free_tables ( Vec s ) tables → v {
    : ~ i i 0 ~ < i 4 { ( pktable_free ( node tables i ) ) = i + i 1 }
    ( vec_free [s] tables )
}

@ main → i {
    : ( Vec u ) dead3 ( pk 3 )

    // ── (1) convergence under 30% loss + reorder ─────────────────
    : *SimNet net ( sim_net_new 4 12345 30 1 3 )
    : ( Vec s ) tables ( make_tables )
    // node 0 detects node 3 dead (incarnation 2 outranks the bootstrap alive)
    ( pktable_apply ( node tables 0 ) dead3 ( pk_dead ) 2 0 )
    ( pb `before gossip only node 0 knows 3 dead: ` & ( knows_dead tables 0 dead3 ) ! ( knows_dead tables 1 dead3 ) )
    : i now1 ( run_rounds net tables 60 3 0 )
    ( pb `lossy gossip converged 3-dead on node 1: ` ( knows_dead tables 1 dead3 ) )
    ( pb `lossy gossip converged 3-dead on node 2: ` ( knows_dead tables 2 dead3 ) )
    ( pb `some messages were actually dropped: ` > ( sim_dropped net ) 0 )
    ( free_tables tables ) ( sim_net_free net )

    // ── (2) partition isolates node 2, heal reconverges ──────────
    : *SimNet net2 ( sim_net_new 4 777 0 1 0 )  // no random drop; clean partition
    ( sim_partition net2 2 0 ) ( sim_partition net2 2 1 ) ( sim_partition net2 2 3 )
    : ( Vec s ) tb ( make_tables )
    ( pktable_apply ( node tb 0 ) dead3 ( pk_dead ) 2 0 )
    : i now2 ( run_rounds net2 tb 25 3 0 )
    ( pb `partition: nodes 0,1 learn 3 dead: ` & ( knows_dead tb 0 dead3 ) ( knows_dead tb 1 dead3 ) )
    ( pb `partition: isolated node 2 does NOT: ` ! ( knows_dead tb 2 dead3 ) )
    ( sim_heal_all net2 )
    : i now3 ( run_rounds net2 tb 25 3 now2 )
    ( pb `after heal node 2 reconverges 3 dead: ` ( knows_dead tb 2 dead3 ) )
    ( free_tables tb ) ( sim_net_free net2 )

    ( vec_free [u] dead3 )
    ^ 0
}
