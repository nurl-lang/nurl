// dist_identity.nu — offline test for stdlib/dist/identity.nu (§7.5 Phase 9.1).
// Deterministic: monotonic never-reused replica ids, rejoin resumes the same
// slot, a new pubkey never inherits a retired id, and — the headline — feeding
// dist/crdt from the registry survives churn with ZERO slot corruption.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/dist/identity.nu`
$ `stdlib/dist/crdt.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }
@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }
@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T t → # i t F → -1 } ?? ( vec_get [u] b k ) { T t → # i t F → -2 } { = e F } {} = k + k 1 }
    ^ e
}

@ main → i {
    : ( Vec u ) a ( mkpk 10 )
    : ( Vec u ) b ( mkpk 80 )
    : ( Vec u ) c ( mkpk 150 )

    : *IdRegistry reg ( identity_new )

    // ── monotonic, stable, never-reused ──────────────────────────
    : i ida ( identity_of reg a )
    : i idb ( identity_of reg b )
    ( pb `first ids are 0,1: ` & == ida 0 == idb 1 )
    ( pb `identity_of is stable: ` == ( identity_of reg a ) ida )
    ( pb `reverse lookup resolves: ` ?? ( identity_pubkey reg ida ) { T pk → { : b ok ( veq pk a ) ( vec_free [u] pk ) ok } F → F } )
    ( pb `known reports true: ` ( identity_known reg a ) )
    ( pb `unknown C reports false: ` ! ( identity_known reg c ) )

    // ── retire A, then a NEW pubkey must NOT inherit A's id ───────
    ( identity_retire reg a )
    ( pb `retired id not live: ` ! ( identity_is_live reg ida ) )
    : i idc ( identity_of reg c )
    ( pb `new pubkey gets fresh id (2, not 0): ` == idc 2 )
    ( pb `retired id still resolves (tombstone): ` ?? ( identity_pubkey reg ida ) { T pk → { : b ok ( veq pk a ) ( vec_free [u] pk ) ok } F → F } )

    // ── A rejoins → resumes its OWN slot, revived ────────────────
    : i ida2 ( identity_of reg a )
    ( pb `rejoin resumes same id: ` == ida2 ida )
    ( pb `rejoin revives liveness: ` ( identity_is_live reg ida ) )
    ( pb `three distinct entries: ` == ( identity_count reg ) 3 )

    // ── headline: CRDT fed from the registry survives churn ──────
    // A and B both increment via their registry ids; merge; value correct.
    : *PNCounter ca ( pncounter_new )
    ( pncounter_inc ca ( identity_of reg a ) 5 )
    : *PNCounter cb ( pncounter_new )
    ( pncounter_inc cb ( identity_of reg b ) 7 )
    ( pncounter_merge ca cb )
    ( pb `crdt via stable ids merges to 12: ` == ( pncounter_value ca ) 12 )

    // Now B leaves and a NEW node D joins. With naive id reuse D would inherit
    // B's slot 1 and clobber B's 7. With the registry, D gets a fresh id, so a
    // late merge of B's old counter does NOT corrupt D's contribution.
    ( identity_retire reg b )
    : ( Vec u ) d ( mkpk 200 )
    : i idd ( identity_of reg d )
    ( pb `D does NOT inherit B slot: ` & != idd idb == idd 3 )
    : *PNCounter cd ( pncounter_new )
    ( pncounter_inc cd idd 4 )
    ( pncounter_merge ca cd )          // ca now has A=5, B=7, D=4
    ( pncounter_merge ca cb )          // re-merge B's old state: idempotent, no clobber
    ( pb `no slot corruption after churn (16): ` == ( pncounter_value ca ) 16 )

    ( pncounter_free ca ) ( pncounter_free cb ) ( pncounter_free cd )
    ( identity_free reg )
    ( vec_free [u] a ) ( vec_free [u] b ) ( vec_free [u] c ) ( vec_free [u] d )
    ^ 0
}
