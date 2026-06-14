// relay_codec.nu — offline test for stdlib/net/relay.nu frame codec.
// Deterministic, no sockets: builds REGISTER / FORWARD / DELIVER frames and
// parses them back, checks the pubkey/payload split, and that an incomplete
// or oversize buffer parses to None.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/relay.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ bytes i seed i n → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i k 0 ~ < k n { ( vec_push [u] v # u + seed k ) = k + k 1 }
    ^ v
}

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a )
    ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n {
        : i x ?? ( vec_get [u] a k ) { T t → # i t F → -1 }
        : i y ?? ( vec_get [u] b k ) { T t → # i t F → -2 }
        ? != x y { = e F } {}
        = k + k 1
    }
    ^ e
}

@ main → i {
    : ( Vec u ) pk   ( bytes 100 32 )    // a 32-byte pubkey
    : ( Vec u ) data ( bytes 1 40 )      // opaque payload

    // ── REGISTER ─────────────────────────────────────────────────
    : ( Vec u ) reg ( relay_build_register pk )
    ( nurl_print `register frame len: ` ) ( nurl_print_int ( vec_len [u] reg ) )   // 1+4+32 = 37
    : ?RelayFrame rf ( relay_parse reg )
    ?? rf {
        T f → {
            ( pb `register type: ` == . f ftype ( relay_reg ) )
            ( pb `register body == pubkey: ` ( veq . f body pk ) )
            ( relay_frame_free f )
        }
        F → ( nurl_print `register parse failed\n` )
    }

    // ── FORWARD ──────────────────────────────────────────────────
    : ( Vec u ) fwd ( relay_build_forward pk data )
    : ?RelayFrame ff ( relay_parse fwd )
    ?? ff {
        T f → {
            ( pb `forward type: ` == . f ftype ( relay_fwd ) )
            : ( Vec u ) dpk ( relay_body_pk . f body )
            : ( Vec u ) dpl ( relay_body_payload . f body )
            ( pb `forward dest pk split: ` ( veq dpk pk ) )
            ( pb `forward payload split: ` ( veq dpl data ) )
            ( vec_free [u] dpk ) ( vec_free [u] dpl )
            ( relay_frame_free f )
        }
        F → ( nurl_print `forward parse failed\n` )
    }

    // ── DELIVER ──────────────────────────────────────────────────
    : ( Vec u ) del ( relay_build_deliver pk data )
    : ?RelayFrame fd ( relay_parse del )
    ?? fd {
        T f → {
            ( pb `deliver type: ` == . f ftype ( relay_del ) )
            : ( Vec u ) spk ( relay_body_pk . f body )
            ( pb `deliver src pk split: ` ( veq spk pk ) )
            ( vec_free [u] spk )
            ( relay_frame_free f )
        }
        F → ( nurl_print `deliver parse failed\n` )
    }

    // ── GROUP JOIN / SEND ────────────────────────────────────────
    : ( Vec u ) gid ( bytes 200 32 )      // a 32-byte group id
    : ( Vec u ) gj ( relay_build_group_join gid )
    : ?RelayFrame fj ( relay_parse gj )
    ?? fj {
        T f → {
            ( pb `gjoin type: ` == . f ftype ( relay_gjoin ) )
            ( pb `gjoin body == gid: ` ( veq . f body gid ) )
            ( relay_frame_free f )
        }
        F → ( nurl_print `gjoin parse failed\n` )
    }

    : ( Vec u ) gs ( relay_build_group_send gid data )
    : ?RelayFrame fg ( relay_parse gs )
    ?? fg {
        T f → {
            ( pb `gsend type: ` == . f ftype ( relay_gsend ) )
            : ( Vec u ) ggid ( relay_body_pk . f body )
            : ( Vec u ) gpl ( relay_body_payload . f body )
            ( pb `gsend gid split: ` ( veq ggid gid ) )
            ( pb `gsend payload split: ` ( veq gpl data ) )
            ( vec_free [u] ggid ) ( vec_free [u] gpl )
            ( relay_frame_free f )
        }
        F → ( nurl_print `gsend parse failed\n` )
    }

    // ── incomplete buffer ────────────────────────────────────────
    : ( Vec u ) partial ( vec_new [u] )
    ( vec_push [u] partial # u 2 )                    // type
    ( bytes_push_u32_be partial # u32 999 )          // claims 999 bytes, none follow
    ( pb `incomplete → None: ` ?? ( relay_parse partial ) { T f → { ( relay_frame_free f ) F } F → T } )

    // ── oversize length rejected ─────────────────────────────────
    : ( Vec u ) huge ( vec_new [u] )
    ( vec_push [u] huge # u 2 )
    ( bytes_push_u32_be huge # u32 2000000 )         // > __relay_max
    ( pb `oversize → None: ` ?? ( relay_parse huge ) { T f → { ( relay_frame_free f ) F } F → T } )

    ( vec_free [u] pk ) ( vec_free [u] data )
    ( vec_free [u] reg ) ( vec_free [u] fwd ) ( vec_free [u] del )
    ( vec_free [u] gid ) ( vec_free [u] gj ) ( vec_free [u] gs )
    ( vec_free [u] partial ) ( vec_free [u] huge )
    ^ 0
}
