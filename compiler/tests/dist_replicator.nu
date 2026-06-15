// dist_replicator.nu — offline test for stdlib/dist/replicator.nu. No sockets:
// round-trips each CRDT through its wire codec, then exercises anti-entropy —
// two divergent replicas that exchange ENCODED state converge (the gossip
// semantics, deterministically).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/crdt.nu`
$ `stdlib/dist/replicator.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ main → i {
    // ── PNCounter codec + anti-entropy ───────────────────────────
    : *PNCounter a ( pncounter_new )
    ( pncounter_inc a 0 5 ) ( pncounter_dec a 0 2 )   // value 3
    : ( Vec u ) ab ( pncounter_encode a )
    : *PNCounter a2 ( pncounter_decode ab )
    ( pb `pncounter round-trips (3): ` == ( pncounter_value a2 ) 3 )
    ( pncounter_free a2 ) ( vec_free [u] ab )

    : *PNCounter b ( pncounter_new )
    ( pncounter_inc b 1 10 )                           // value 10
    // A learns B and B learns A by exchanging encoded state
    : ( Vec u ) be ( pncounter_encode b )
    ( pncounter_merge_bytes a be )                    // a += b  → 13
    : ( Vec u ) ae ( pncounter_encode a )
    ( pncounter_merge_bytes b ae )                    // b += a  → 13
    ( pb `counter converged (a=13): ` == ( pncounter_value a ) 13 )
    ( pb `counter converged (b=13): ` == ( pncounter_value b ) 13 )
    ( vec_free [u] be ) ( vec_free [u] ae )
    ( pncounter_free a ) ( pncounter_free b )

    // ── LwwReg codec + merge-from-bytes ──────────────────────────
    : LwwReg r ( lww_set ( lww_new ) 42 1000 0 )
    : ( Vec u ) rb ( lww_encode r )
    : LwwReg r2 ( lww_decode rb )
    ( pb `lww round-trips (val 42, ts 1000): ` & == ( lww_value r2 ) 42 == ( lww_ts r2 ) 1000 )
    ( vec_free [u] rb )
    : LwwReg newer ( lww_set ( lww_new ) 99 2000 1 )
    : ( Vec u ) nb ( lww_encode newer )
    : LwwReg merged ( lww_merge_bytes r nb )
    ( pb `lww merge-from-bytes takes newer (99): ` == ( lww_value merged ) 99 )
    ( vec_free [u] nb )

    // ── OrSet codec + anti-entropy add-wins ──────────────────────
    : *OrSet sa ( orset_new )
    ( orset_add sa 0 7 ) ( orset_add sa 0 8 )
    : ( Vec u ) sab ( orset_encode sa )
    : *OrSet sa2 ( orset_decode sab )
    ( pb `orset round-trips (has 7): ` ( orset_contains sa2 7 ) )
    ( pb `orset round-trips (has 8): ` ( orset_contains sa2 8 ) )
    ( pb `orset round-trips (no 9): ` ! ( orset_contains sa2 9 ) )
    ( orset_free sa2 ) ( vec_free [u] sab )

    // anti-entropy add-wins: B observes A's 7, A removes 7, B re-adds 7
    : *OrSet sb ( orset_new )
    : ( Vec u ) e1 ( orset_encode sa )
    ( orset_merge_bytes sb e1 ) ( vec_free [u] e1 )    // B sees {7,8}
    ( orset_remove sa 7 )                               // A removes 7
    ( orset_add sb 1 7 )                                // B re-adds 7 (new tag)
    : ( Vec u ) e2 ( orset_encode sb )
    ( orset_merge_bytes sa e2 ) ( vec_free [u] e2 )    // A merges B
    : ( Vec u ) e3 ( orset_encode sa )
    ( orset_merge_bytes sb e3 ) ( vec_free [u] e3 )    // B merges A
    ( pb `add-wins over the wire (A has 7): ` ( orset_contains sa 7 ) )
    ( pb `add-wins over the wire (B has 7): ` ( orset_contains sb 7 ) )
    ( pb `converged on 8 too: ` & ( orset_contains sa 8 ) ( orset_contains sb 8 ) )
    ( orset_free sa ) ( orset_free sb )

    ^ 0
}
