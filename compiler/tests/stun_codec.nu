// stun_codec.nu — offline test for stdlib/net/stun.nu. Deterministic: a
// Binding request is built with a fixed transaction id, and a hand-crafted
// XOR-MAPPED-ADDRESS response for 203.0.113.5:54321 is parsed back. Also
// checks that a wrong transaction id is rejected.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/net/stun.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `YES\n` `NO\n` ) }
@ push ( Vec u ) v i b → v { ( vec_push [u] v # u b ) }

@ fixed_txid → ( Vec u ) {
    : ( Vec u ) t ( vec_new [u] )
    : ~ i k 0 ~ < k 12 { ( push t 171 ) = k + k 1 }   // 0xAB ×12
    ^ t
}

// Binding success response with XOR-MAPPED-ADDRESS = 203.0.113.5:54321.
// xport = 54321 ^ 0x2112 = 0xF523; xaddr bytes = (203^0x21, 0^0x12, 113^0xA4, 5^0x42).
@ crafted_response ( Vec u ) txid → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    ( push m 1 ) ( push m 1 )           // type 0x0101 (success)
    ( push m 0 ) ( push m 12 )          // length = 12 (one attr incl header)
    ( push m 33 ) ( push m 18 ) ( push m 164 ) ( push m 66 )   // cookie 0x2112A442
    ( vec_extend [u] m txid )           // transaction id
    ( push m 0 ) ( push m 32 )          // attr type 0x0020 (XOR-MAPPED-ADDRESS)
    ( push m 0 ) ( push m 8 )           // attr length 8
    ( push m 0 ) ( push m 1 )           // reserved, family=IPv4
    ( push m 245 ) ( push m 35 )        // x-port 0xF523
    ( push m 234 ) ( push m 18 ) ( push m 213 ) ( push m 71 )  // x-address
    ^ m
}

@ main → i {
    // ── request build ────────────────────────────────────────────
    : ( Vec u ) txid ( fixed_txid )
    : ( Vec u ) req ( stun_build_request_with txid )
    ( nurl_print `req len: ` ) ( nurl_print_int ( vec_len [u] req ) ) ( nurl_print `\n` )
    ( pb `req type is Binding: ` & == ?? ( vec_get [u] req 0 ) { T x → # i x F → -1 } 0
    == ?? ( vec_get [u] req 1 ) { T x → # i x F → -1 } 1 )
    ( pb `req has magic cookie: ` & & & == ?? ( vec_get [u] req 4 ) { T x → # i x F → -1 } 33
    == ?? ( vec_get [u] req 5 ) { T x → # i x F → -1 } 18
    == ?? ( vec_get [u] req 6 ) { T x → # i x F → -1 } 164
    == ?? ( vec_get [u] req 7 ) { T x → # i x F → -1 } 66 )

    // ── parse a crafted reflexive response ───────────────────────
    : ( Vec u ) resp ( crafted_response txid )
    : ?StunAddr a ( stun_parse resp txid )
    ?? a {
        T sa → {
            ( nurl_print `reflexive: ` ) ( nurl_print ( string_data . sa host ) )
            ( nurl_print `:` ) ( nurl_print_int . sa port ) ( nurl_print `\n` )
            ( pb `decode correct: ` & != 0 ( nurl_str_eq ( string_data . sa host ) `203.0.113.5` ) == . sa port 54321 )
            ( stun_addr_free sa )
        }
        F → ( nurl_print `parse failed\n` )
    }

    // ── wrong transaction id is rejected ─────────────────────────
    : ( Vec u ) wrong ( vec_new [u] )
    : ~ i w 0 ~ < w 12 { ( push wrong 1 ) = w + w 1 }   // all 0x01, != 0xAB
    : ?StunAddr a2 ( stun_parse resp wrong )
    ( pb `wrong txid rejected: ` ?? a2 { T sa → { ( stun_addr_free sa ) F } F → T } )

    ( vec_free [u] txid ) ( vec_free [u] req ) ( vec_free [u] resp ) ( vec_free [u] wrong )
    ^ 0
}
