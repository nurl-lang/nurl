// dist_crdt.nu — offline test for stdlib/dist/crdt.nu. Deterministic: checks
// the CRDT laws — PNCounter convergence + idempotence + commutativity, LWW
// timestamp/replica tie-break, and the OR-Set add-wins property under a
// concurrent add/remove.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/crdt.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ main → i {
    // ── PNCounter ────────────────────────────────────────────────
    : *PNCounter a ( pncounter_new )
    ( pncounter_inc a 0 5 ) ( pncounter_dec a 0 2 )      // replica 0: +5 -2
    : *PNCounter b ( pncounter_new )
    ( pncounter_inc b 1 10 )                              // replica 1: +10
    ( pb `a value = 3: ` == ( pncounter_value a ) 3 )
    ( pb `b value = 10: ` == ( pncounter_value b ) 10 )
    ( pncounter_merge a b )
    ( pb `merged value = 13: ` == ( pncounter_value a ) 13 )
    ( pncounter_merge a b )
    ( pb `merge idempotent (still 13): ` == ( pncounter_value a ) 13 )
    // commutativity: merge the other direction from fresh copies
    : *PNCounter c ( pncounter_new )
    ( pncounter_inc c 1 10 )
    : *PNCounter d ( pncounter_new )
    ( pncounter_inc d 0 5 ) ( pncounter_dec d 0 2 )
    ( pncounter_merge c d )
    ( pb `merge commutative (= 13): ` == ( pncounter_value c ) 13 )
    ( pncounter_free a ) ( pncounter_free b ) ( pncounter_free c ) ( pncounter_free d )

    // ── LwwReg ───────────────────────────────────────────────────
    : LwwReg r1 ( lww_set ( lww_new ) 7 100 0 )
    : LwwReg r2 ( lww_set ( lww_new ) 9 200 1 )
    ( pb `higher ts wins (9): ` == ( lww_value ( lww_merge r1 r2 ) ) 9 )
    ( pb `lww merge commutative: ` == ( lww_value ( lww_merge r2 r1 ) ) 9 )
    : LwwReg t1 ( lww_set ( lww_new ) 7 100 0 )
    : LwwReg t2 ( lww_set ( lww_new ) 9 100 1 )    // same ts → higher replica wins
    ( pb `ts tie → higher replica (9): ` == ( lww_value ( lww_merge t1 t2 ) ) 9 )
    ( pb `tie-break commutative: ` == ( lww_value ( lww_merge t2 t1 ) ) 9 )

    // ── OrSet: plain add / remove ────────────────────────────────
    : *OrSet x ( orset_new )
    ( orset_add x 0 7 )
    ( pb `added → present: ` ( orset_contains x 7 ) )
    ( orset_remove x 7 )
    ( pb `removed → absent: ` ! ( orset_contains x 7 ) )
    ( orset_free x )

    // ── OrSet: concurrent add wins over remove ───────────────────
    : *OrSet sa ( orset_new )
    ( orset_add sa 0 5 )            // A adds 5  (tag 5,0,0)
    : *OrSet sb ( orset_new )
    ( orset_merge sb sa )           // B observes A's add
    ( orset_remove sa 5 )           // A removes 5 (tombstones 5,0,0)
    ( orset_add sb 1 5 )            // B concurrently re-adds 5 (tag 5,1,0)
    // bidirectional merge → converge
    ( orset_merge sa sb )
    ( orset_merge sb sa )
    ( pb `add-wins on A: ` ( orset_contains sa 5 ) )
    ( pb `add-wins on B: ` ( orset_contains sb 5 ) )
    ( pb `replicas converged: ` == ( orset_contains sa 5 ) ( orset_contains sb 5 ) )
    ( orset_free sa ) ( orset_free sb )

    ^ 0
}
