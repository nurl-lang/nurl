// sim_crdt.nu — §7.5 Phase 13 chaos-harness scenario for CRDT gossip. Drives
// the REAL dist/crdt + dist/replicator codecs over dist/sim's bus, with each
// node deriving its replica id INDEPENDENTLY (no coordination — the whole point
// of CRDTs). This is the scenario that exposes cross-node replica-id
// consistency: if two nodes can disagree on which id names which replica, a
// positional/colliding merge silently corrupts the value.
//
//   3 nodes, each increments its OWN PNCounter once, then they anti-entropy
//   their encoded state over a lossy + partitioned + healed bus. The cluster
//   must converge to value 3 (three distinct +1s) on every node. It can only do
//   so if every node names its replica by a GLOBALLY STABLE id — here the
//   pubkey-derived identity_stable_id — so distinct replicas land in distinct
//   slots and the merge sums them instead of max-colliding.
//
// Seeded → byte-reproducible; "converged to 3 everywhere" can genuinely fail.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/crdt.nu`
$ `stdlib/dist/replicator.nu`
$ `stdlib/dist/identity.nu`
$ `stdlib/dist/sim.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ pi s label i v → v { ( nurl_print label ) ( nurl_println_int v ) }

@ pk i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + id k ) = k + k 1 } ^ v }

@ ctr ( Vec s ) cs i i → *PNCounter { ^ # *PNCounter ?? ( vec_get [s] cs i ) { T x → x F → # s 0 } }

// each node broadcasts its encoded counter to every other node
@ gossip_all * SimNet net ( Vec s ) cs i n i now → v {
    : ~ i i 0
    ~ < i n {
        : ( Vec u ) bytes ( pncounter_encode ( ctr cs i ) )
        : ~ i j 0
        ~ < j n { ? != j i { ( sim_send net i j bytes now ) } {} = j + j 1 }
        ( vec_free [u] bytes )
        = i + i 1
    }
}
// deliver due deltas, merging each into the destination node's counter
@ deliver_all * SimNet net ( Vec s ) cs i now → v {
    : ( Vec s ) due ( sim_due net now )
    : i dn ( vec_len [s] due )
    : ~ i k 0
    ~ < k dn {
        : s mp ?? ( vec_get [s] due k ) { T x → x F → # s 0 }
        ? != # i mp 0 {
            : *SimMsg sm # *SimMsg mp
            ( pncounter_merge_bytes ( ctr cs . sm dst ) . sm bytes )
            ( sim_msg_free sm )
        } {}
        = k + k 1
    }
    ( vec_free [s] due )
}

@ main → i {
    : i n 3

    // Each node has its OWN identity registry and sees the peers in a DIFFERENT
    // order (its own pubkey first). With a local-first-seen id every node would
    // call itself replica 0 — a universal collision. identity_stable_id derives
    // the id from the pubkey, so the registries agree without coordination.
    : ( Vec s ) cs ( vec_new [s] )
    : ~ i i 0
    ~ < i n {
        : *PNCounter c ( pncounter_new )
        : *IdRegistry reg ( identity_new )
        // register peers in rotated order (self first) to provoke divergence
        : ~ i d 0
        ~ < d n {
            : i who % + i d n
            : ( Vec u ) ppk ( pk who )
            ( identity_of reg ppk )  // would hand out 0,1,2 in THIS order
            ( vec_free [u] ppk )
            = d + d 1
        }
        : ( Vec u ) selfpk ( pk i )
        : i rid ( identity_stable_id selfpk )  // GLOBALLY stable id for this node
        ( pncounter_inc c rid 1 )  // each node does exactly one +1
        ( vec_free [u] selfpk )
        ( identity_free reg )
        ( vec_push [s] cs # s c )
        = i + i 1
    }

    ( pi `each node's own count before gossip (=1): ` ( pncounter_value ( ctr cs 0 ) ) )

    // ── anti-entropy over a lossy bus, with a partition then a heal ──
    : *SimNet net ( sim_net_new n 9001 25 1 2 )
    : ~ i now 0
    // phase 1: node 2 partitioned away from 0 and 1
    ( sim_partition net 2 0 ) ( sim_partition net 2 1 )
    : ~ i r 0
    ~ < r 20 { = now + now 1 ( gossip_all net cs n now ) ( deliver_all net cs now ) = r + r 1 }
    ( pi `during partition, node 0 value (sees 0+1 only, =2): ` ( pncounter_value ( ctr cs 0 ) ) )
    ( pb `during partition, node 2 is isolated (value 1): ` == ( pncounter_value ( ctr cs 2 ) ) 1 )
    // phase 2: heal — everyone must reach 3
    ( sim_heal_all net )
    : ~ i r2 0
    ~ < r2 30 { = now + now 1 ( gossip_all net cs n now ) ( deliver_all net cs now ) = r2 + r2 1 }

    ( pi `after heal node 0 value: ` ( pncounter_value ( ctr cs 0 ) ) )
    ( pi `after heal node 1 value: ` ( pncounter_value ( ctr cs 1 ) ) )
    ( pi `after heal node 2 value: ` ( pncounter_value ( ctr cs 2 ) ) )
    ( pb `CONVERGED to 3 on every node (no id collision): ` & & == ( pncounter_value ( ctr cs 0 ) ) 3 == ( pncounter_value ( ctr cs 1 ) ) 3 == ( pncounter_value ( ctr cs 2 ) ) 3 )
    ( pb `messages were actually dropped: ` > ( sim_dropped net ) 0 )

    : ~ i fi 0
    ~ < fi n { ( pncounter_free ( ctr cs fi ) ) = fi + fi 1 }
    ( vec_free [s] cs )
    ( sim_net_free net )
    ^ 0
}
