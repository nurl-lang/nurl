// rendezvous_codec.nu — offline test for stdlib/net/rendezvous.nu. No
// sockets: builds a PeerRecord (pubkey + 2 candidate endpoints + relay),
// round-trips it through the record codec, and through REGISTER / LOOKUP /
// RECORD(found|notfound) frames.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/net/rendezvous.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }

@ mkpk i seed → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + seed k ) = k + k 1 } ^ v }

@ veq ( Vec u ) a ( Vec u ) b → b {
    : i n ( vec_len [u] a ) ? != n ( vec_len [u] b ) { ^ F } {}
    : ~ b e T : ~ i k 0
    ~ & e < k n { ? != ?? ( vec_get [u] a k ) { T t → # i t F → -1 } ?? ( vec_get [u] b k ) { T t → # i t F → -2 } { = e F } {} = k + k 1 }
    ^ e
}

@ ep_host s pp → s { : *Endpoint e # *Endpoint pp ^ ( string_data . e host ) }
@ ep_port s pp → i { : *Endpoint e # *Endpoint pp ^ . e port }

@ check_record s rp ( Vec u ) wantpk → v {
    : *PeerRecord r # *PeerRecord rp
    ( pb `  pubkey matches: ` ( veq . r pubkey wantpk ) )
    ( pb `  relay host: ` & != 0 ( nurl_str_eq ( string_data . r relay_host ) `relay.example` ) == . r relay_port 8443 )
    ( pb `  2 endpoints: ` == ( vec_len [s] . r endpoints ) 2 )
    : s e0 ?? ( vec_get [s] . r endpoints 0 ) { T x → x F → # s 0 }
    : s e1 ?? ( vec_get [s] . r endpoints 1 ) { T x → x F → # s 0 }
    ( pb `  ep0 = 192.0.2.1:5000: ` & != 0 ( nurl_str_eq ( ep_host e0 ) `192.0.2.1` ) == ( ep_port e0 ) 5000 )
    ( pb `  ep1 = 198.51.100.7:41000: ` & != 0 ( nurl_str_eq ( ep_host e1 ) `198.51.100.7` ) == ( ep_port e1 ) 41000 )
}

@ main → i {
    : ( Vec u ) pk ( mkpk 100 )
    : s rp ( peer_record_new pk `relay.example` 8443 )
    : *PeerRecord r # *PeerRecord rp
    ( peer_record_add_endpoint r `192.0.2.1` 5000 )
    ( peer_record_add_endpoint r `198.51.100.7` 41000 )

    // ── record codec round trip ──────────────────────────────────
    ( nurl_print `record codec:\n` )
    : ( Vec u ) enc ( rz_record_encode r )
    : s dp ( rz_record_decode enc )
    ( check_record dp pk )
    ( peer_record_free # *PeerRecord dp )
    ( vec_free [u] enc )

    // ── REGISTER frame carries the record ────────────────────────
    : ( Vec u ) reg ( rz_build_register r )
    ?? ( rz_parse reg ) {
        T f → {
            ( pb `register type: ` == . f ftype ( rz_register ) )
            : s d2 ( rz_record_decode . f body )
            ( nurl_print `register record:\n` ) ( check_record d2 pk )
            ( peer_record_free # *PeerRecord d2 )
            ( rz_frame_free f )
        }
        F → ( nurl_print `register parse failed\n` )
    }

    // ── LOOKUP frame carries the pubkey ──────────────────────────
    : ( Vec u ) lk ( rz_build_lookup pk )
    ?? ( rz_parse lk ) {
        T f → {
            ( pb `lookup type: ` == . f ftype ( rz_lookup ) )
            ( pb `lookup body == pubkey: ` ( veq . f body pk ) )
            ( rz_frame_free f )
        }
        F → ( nurl_print `lookup parse failed\n` )
    }

    // ── RECORD found / notfound ──────────────────────────────────
    : ( Vec u ) rf ( rz_build_record_found r )
    ?? ( rz_parse rf ) {
        T f → {
            ( pb `record(found) flag: ` == ?? ( vec_get [u] . f body 0 ) { T x → # i x F → -1 } 1 )
            ( rz_frame_free f )
        }
        F → ( nurl_print `record parse failed\n` )
    }
    : ( Vec u ) rn ( rz_build_record_notfound )
    ?? ( rz_parse rn ) {
        T f → {
            ( pb `record(notfound) flag: ` == ?? ( vec_get [u] . f body 0 ) { T x → # i x F → -1 } 0 )
            ( rz_frame_free f )
        }
        F → ( nurl_print `record parse failed\n` )
    }

    ( peer_record_free r )
    ( vec_free [u] pk ) ( vec_free [u] reg ) ( vec_free [u] lk )
    ( vec_free [u] rf ) ( vec_free [u] rn )
    ^ 0
}
