// dist_job.nu — offline test for stdlib/dist/job.nu (§7.5 Phase 11 keystone).
// Deterministic, no sockets (transport handle is 0; the owned-key path and all
// pure logic never touch it): JobMsg codec, in-process submit→execute→await,
// idempotent result recording, and owner recomputation across a ring change
// (the re-home target).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/job.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }

@ bytes4 i a i b i c i d → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) ( vec_push [u] v # u a ) ( vec_push [u] v # u b ) ( vec_push [u] v # u c ) ( vec_push [u] v # u d ) ^ v }

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T t → # i t F → -1 } ?? ( vec_get [u] b k ) { T t → # i t F → -2 } { = e F } {} = k + k 1 }
    ^ e
}

// task kind 0: result = (sum of payload bytes) & 255, as a 1-byte vector
@ sum_handler → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : ~ i s 0
        : i nn ( vec_len [u] p )
        : ~ i k 0
        ~ < k nn { = s + s ?? ( vec_get [u] p k ) { T x → # i x F → 0 } = k + k 1 }
        : ( Vec u ) r ( vec_new [u] )
        ( vec_push [u] r # u & s 255 )
        ^ r
    }
}

@ main → i {
    : ( Vec u ) a ( mkpk 10 )

    // ── JobMsg codec ─────────────────────────────────────────────
    : ( Vec u ) sub ( mkpk 99 )
    : ( Vec u ) key ( bytes4 7 7 7 7 )
    : ( Vec u ) pl ( bytes4 1 2 3 4 )
    : ( Vec u ) sm ( job_build_submit 4242 0 sub key pl )
    : JobMsg dm ( jobmsg_decode sm )
    ( pb `submit type/id/kind: ` & & == . dm mtype ( job_submit_t ) == . dm task_id 4242 == . dm kind 0 )
    ( pb `submit submitter/key/payload: ` & & ( veq . dm submitter sub ) ( veq . dm key key ) ( veq . dm payload pl ) )
    ( jobmsg_free dm ) ( vec_free [u] sm )

    : ( Vec u ) rp ( bytes4 9 9 0 0 )
    : ( Vec u ) rm ( job_build_result 4242 rp )
    : JobMsg drm ( jobmsg_decode rm )
    ( pb `result type/id/payload: ` & & == . drm mtype ( job_result_t ) == . drm task_id 4242 ( veq . drm payload rp ) )
    ( jobmsg_free drm ) ( vec_free [u] rm )
    ( vec_free [u] sub ) ( vec_free [u] rp )

    // ── in-process submit → execute → await (node owns the key) ──
    : *Ring ring ( ring_new )
    ( ring_add_member ring a 32 )  // single member ⇒ owns every key
    : *JobNode n ( job_node_new # s 0 # s ring a 0 )
    ( job_register n 0 ( sum_handler ) )
    ( pb `owns key (single-member ring): ` ( job_owns n key ) )
    : i tid ( job_submit n 0 key pl )  // sum(1,2,3,4)=10
    ( pb `result recorded after submit: ` ( job_has n tid ) )
    : ( Vec u ) want ( bytes4 10 0 0 0 )  // 1-byte [10]; compare just elem 0
    ( pb `awaited result is sum=10: ` ?? ( job_await n tid ) { T r → { : b ok == ?? ( vec_get [u] r 0 ) { T x → # i x F → -1 } 10 ( vec_free [u] r ) ok } F → F } )
    ( pb `await unknown task → None: ` ?? ( job_await n 999999 ) { T r → { ( vec_free [u] r ) F } F → T } )
    ( vec_free [u] want )

    // ── idempotent result recording (at-least-once safe) ─────────
    : ( Vec u ) p1 ( bytes4 1 0 0 0 )
    : ( Vec u ) r1 ( job_build_result 555 p1 )
    : JobMsg m1 ( jobmsg_decode r1 )
    ( job_on_result n m1 )
    ( jobmsg_free m1 ) ( vec_free [u] r1 ) ( vec_free [u] p1 )
    : ( Vec u ) p2 ( bytes4 2 0 0 0 )  // duplicate task_id, different bytes
    : ( Vec u ) r2 ( job_build_result 555 p2 )
    : JobMsg m2 ( jobmsg_decode r2 )
    ( job_on_result n m2 )
    ( jobmsg_free m2 ) ( vec_free [u] r2 ) ( vec_free [u] p2 )
    ( pb `duplicate delivery is idempotent (keeps first): ` ?? ( job_await n 555 ) { T r → { : b ok == ?? ( vec_get [u] r 0 ) { T x → # i x F → -1 } 1 ( vec_free [u] r ) ok } F → F } )

    ( job_node_free n )
    ( ring_free ring )

    // ── owner recompute across a ring change (re-home target) ────
    : ( Vec u ) b ( mkpk 80 )
    : ( Vec u ) c ( mkpk 150 )
    : *Ring r3 ( ring_new )
    ( ring_add_member r3 a 32 ) ( ring_add_member r3 b 32 ) ( ring_add_member r3 c 32 )
    : *JobNode n2 ( job_node_new # s 0 # s r3 a 1 )
    : ( Vec u ) k2 ( bytes4 200 13 13 13 )
    : ~ ( Vec u ) owner1 ( vec_new [u] )
    ?? ( job_owner_pk n2 k2 ) { T o → { ( vec_free [u] owner1 ) = owner1 o } F → {} }
    ( pb `key has an owner in 3-node ring: ` > ( vec_len [u] owner1 ) 0 )
    ( ring_remove_member r3 owner1 )  // the owner leaves
    : ~ ( Vec u ) owner2 ( vec_new [u] )
    ?? ( job_owner_pk n2 k2 ) { T o → { ( vec_free [u] owner2 ) = owner2 o } F → {} }
    ( pb `owner recomputes after removal (re-home): ` ! ( veq owner1 owner2 ) )
    ( pb `new owner is a surviving member: ` > ( vec_len [u] owner2 ) 0 )
    ( vec_free [u] owner1 ) ( vec_free [u] owner2 ) ( vec_free [u] k2 )
    ( job_node_free n2 ) ( ring_free r3 )
    ( vec_free [u] b ) ( vec_free [u] c )

    ( vec_free [u] a ) ( vec_free [u] key ) ( vec_free [u] pl )
    ^ 0
}
