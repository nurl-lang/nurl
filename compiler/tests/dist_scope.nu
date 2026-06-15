// dist_scope.nu — offline test for the ownership-scoped anti-entropy added to
// stdlib/dist/replicator.nu (§7.5 Phase 9.2). Deterministic: a key's delta
// fans out to exactly its R replicas (O(R), not the whole cluster), a
// non-replica is excluded, a digest detects divergence, anti-entropy
// converges, and the replica set adapts across a ring membership change.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/crdt.nu`
$ `stdlib/dist/replicator.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }
@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }
@ mkkey i x → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u & x 255 ) ( vec_push [u] v # u & >> x 8 255 )
    ( vec_push [u] v # u & >> x 16 255 ) ( vec_push [u] v # u & >> x 24 255 )
    ^ v
}
@ b2i b x → i { ^ ? x 1 0 }

@ main → i {
    : ( Vec u ) a ( mkpk 10 )
    : ( Vec u ) b ( mkpk 80 )
    : ( Vec u ) c ( mkpk 150 )
    : ( Vec u ) d ( mkpk 220 )

    : *Ring r ( ring_new )
    ( ring_add_member r a 32 ) ( ring_add_member r b 32 )
    ( ring_add_member r c 32 ) ( ring_add_member r d 32 )

    : ( Vec u ) key ( mkkey 1234567 )

    // ── O(R) fan-out, not O(N) ───────────────────────────────────
    ( pb `fan-out is R=2 (not N=4): ` == ( replica_fanout r key 2 ) 2 )

    // ── exactly R replicas; non-replicas excluded ────────────────
    : i nrep + + + ( b2i ( is_replica r key 2 a ) ) ( b2i ( is_replica r key 2 b ) ) ( b2i ( is_replica r key 2 c ) ) ( b2i ( is_replica r key 2 d ) )
    ( pb `exactly 2 members are replicas: ` == nrep 2 )
    ( pb `at least one non-replica excluded: ` == nrep 2 )   // 4 members, 2 replicas ⇒ 2 excluded

    // ── digest detects divergence; anti-entropy converges ────────
    : *PNCounter repA ( pncounter_new )
    ( pncounter_inc repA 0 5 )
    : *PNCounter repB ( pncounter_new )
    ( pncounter_inc repB 1 7 )
    : ( Vec u ) ea0 ( pncounter_encode repA )
    : ( Vec u ) eb0 ( pncounter_encode repB )
    ( pb `digest flags divergence: ` ! ( crdt_in_sync ea0 eb0 ) )
    ( pncounter_merge_bytes repA eb0 )
    ( pncounter_merge_bytes repB ea0 )
    ( vec_free [u] ea0 ) ( vec_free [u] eb0 )
    : ( Vec u ) ea1 ( pncounter_encode repA )
    : ( Vec u ) eb1 ( pncounter_encode repB )
    ( pb `anti-entropy converged (12 / in-sync): ` & & == ( pncounter_value repA ) 12 == ( pncounter_value repB ) 12 ( crdt_in_sync ea1 eb1 ) )
    ( vec_free [u] ea1 ) ( vec_free [u] eb1 )

    // ── replica set adapts across a ring membership change ───────
    // remove an actual replica of `key`; it must drop out, fan-out stays R
    // (a survivor backfills), and a freshly-promoted replica converges by pull.
    : ~ i pick - 0 1
    ? & < pick 0 ( is_replica r key 2 a ) { = pick 0 } {}
    ? & < pick 0 ( is_replica r key 2 b ) { = pick 1 } {}
    ? & < pick 0 ( is_replica r key 2 c ) { = pick 2 } {}
    ? & < pick 0 ( is_replica r key 2 d ) { = pick 3 } {}
    ? == pick 0 { ( ring_remove_member r a ) } {}
    ? == pick 1 { ( ring_remove_member r b ) } {}
    ? == pick 2 { ( ring_remove_member r c ) } {}
    ? == pick 3 { ( ring_remove_member r d ) } {}
    : b removed_still_rep ? == pick 0 ( is_replica r key 2 a ) ? == pick 1 ( is_replica r key 2 b ) ? == pick 2 ( is_replica r key 2 c ) ( is_replica r key 2 d )
    ( pb `removed replica drops out of the set: ` ! removed_still_rep )
    ( pb `fan-out still R after the change: ` == ( replica_fanout r key 2 ) 2 )

    // freshly-promoted replica starts empty, pulls the live state, converges
    : *PNCounter fresh ( pncounter_new )
    : ( Vec u ) live ( pncounter_encode repA )    // a surviving replica's state
    : ( Vec u ) fresh0 ( pncounter_encode fresh )
    ( pb `new replica empty diverges: ` ! ( crdt_in_sync fresh0 live ) )
    ( vec_free [u] fresh0 )
    ( pncounter_merge_bytes fresh live )
    : ( Vec u ) freshe ( pncounter_encode fresh )
    ( pb `new replica converges by pull (12): ` & == ( pncounter_value fresh ) 12 ( crdt_in_sync freshe live ) )
    ( vec_free [u] live ) ( vec_free [u] freshe )

    ( pncounter_free repA ) ( pncounter_free repB ) ( pncounter_free fresh )
    ( ring_free r )
    ( vec_free [u] a ) ( vec_free [u] b ) ( vec_free [u] c ) ( vec_free [u] d ) ( vec_free [u] key )
    ^ 0
}
