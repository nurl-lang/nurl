// x25519_vectors.nu — RFC 7748 §5.2 / §6.1 known-answer tests for the
// pure-NURL X25519. Validates the field arithmetic + Montgomery ladder.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/x25519.nu`

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
}

@ check s label ( Vec u ) got s want → i {
    : String gh ( bytes_to_hex got )
    ? ( nurl_str_eq ( string_data gh ) want ) {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ( string_free gh )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL got ` )
        ( nurl_print ( string_data gh ) ) ( nurl_print ` want ` )
        ( nurl_print want ) ( nurl_print `\n` )
        ( string_free gh )
        ^ 1
    }
}

@ main → i {
    : ~ i fails 0

    // RFC 7748 §5.2 vector 1
    : ( Vec u ) s1 ( hx `a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4` )
    : ( Vec u ) u1 ( hx `e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c` )
    : ( Vec u ) r1 ( x25519 s1 u1 )
    = fails + fails ( check `vector1` r1 `c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552` )

    // RFC 7748 §5.2 vector 2
    : ( Vec u ) s2 ( hx `4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d` )
    : ( Vec u ) u2 ( hx `e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493` )
    : ( Vec u ) r2 ( x25519 s2 u2 )
    = fails + fails ( check `vector2` r2 `95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957` )

    // RFC 7748 §6.1 — Alice's keypair: pub = scalar·basepoint.
    : ( Vec u ) ask ( hx `77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a` )
    : ( Vec u ) apk ( x25519_base ask )
    = fails + fails ( check `alice_pub` apk `8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a` )

    // RFC 7748 §6.1 — Bob's keypair.
    : ( Vec u ) bsk ( hx `5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb` )
    : ( Vec u ) bpk ( x25519_base bsk )
    = fails + fails ( check `bob_pub` bpk `de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f` )

    // RFC 7748 §6.1 — both sides derive the same shared secret.
    : ( Vec u ) ss_a ( x25519 ask bpk )
    = fails + fails ( check `shared_a` ss_a `4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742` )
    : ( Vec u ) ss_b ( x25519 bsk apk )
    = fails + fails ( check `shared_b` ss_b `4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742` )

    ? == fails 0 { ( nurl_print `x25519: all vectors PASS\n` ) } { ( nurl_print `x25519: FAILURES\n` ) }
    ^ fails
}
