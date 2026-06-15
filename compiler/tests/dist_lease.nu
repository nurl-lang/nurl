// dist_lease.nu — offline test for stdlib/dist/lease.nu (§7.5 Phase 12).
// Deterministic: the fence (epoch monotonicity) + idempotency key give
// at-most-once for a side effect across a split-ownership window in BOTH
// orderings, while distinct effects and pure tasks are unaffected.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/lease.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }
@ mkkey i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) ( vec_push [u] v # u id ) ( vec_push [u] v # u 9 ) ^ v }

// run the effect iff admitted; bump the shared effect counter via a *i cell
@ effect *LeaseTable t ( Vec u ) key i epoch i idem *i log → v {
    ? ( lease_admit t key epoch idem ) { = . log 0 + . log 0 1 } {}
}

@ main → i {
    : ( Vec u ) k ( mkkey 1 )

    // ── split ownership, NEW owner acts first (token 2 then stale 1) ──
    : *LeaseTable t1 ( lease_new )
    : *i log1 # *i ( nurl_alloc 8 ) = . log1 0 0
    // task idem=100. B (new owner, epoch 2) acts; then A (old owner, epoch 1)
    ( effect t1 k 2 100 log1 )    // B: admitted → effect
    ( effect t1 k 1 100 log1 )    // A: epoch 1 < 2 → fenced out
    ( pb `new-first: effect ran exactly once: ` == . log1 0 1 )
    ( vec_free [u] k ) ( nurl_free # s log1 ) ( lease_free t1 )

    // ── split ownership, OLD owner acts first (token 1 then 2) ──────
    : ( Vec u ) k2 ( mkkey 1 )
    : *LeaseTable t2 ( lease_new )
    : *i log2 # *i ( nurl_alloc 8 ) = . log2 0 0
    ( effect t2 k2 1 100 log2 )   // A: admitted (first) → effect
    ( effect t2 k2 2 100 log2 )   // B: epoch 2 >= 1 advances, but idem 100 already applied → deduped
    ( pb `old-first: effect ran exactly once: ` == . log2 0 1 )
    // the fence advanced to the higher epoch even though the effect was deduped
    ( pb `fence advanced to epoch 2: ` == ( lease_token t2 k2 ) 2 )

    // a genuinely DIFFERENT task (idem 200) under the current epoch still runs
    ( effect t2 k2 2 200 log2 )
    ( pb `distinct effect still admitted: ` == . log2 0 2 )
    // a stale-epoch execution is refused even for a new idem (fenced owner)
    ( effect t2 k2 1 300 log2 )
    ( pb `stale-epoch refused even for new idem: ` == . log2 0 2 )
    ( vec_free [u] k2 ) ( nurl_free # s log2 ) ( lease_free t2 )

    // ── pure path is unaffected: never touches the lease table ──────
    : *LeaseTable t3 ( lease_new )
    // (a pure handler simply does not call lease_admit — the table stays empty)
    : ( Vec u ) k7 ( mkkey 7 )
    ( pb `pure tasks leave the lease table empty: ` == ( lease_token t3 k7 ) 0 )
    ( vec_free [u] k7 ) ( lease_free t3 )

    ^ 0
}
