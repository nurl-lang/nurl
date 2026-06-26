// ecdsa_p256_sign.nu — ECDSA P-256 signing with RFC 6979 deterministic
// nonces. KAT against the RFC 6979 A.2.5 (P-256, SHA-256) "sample"
// vector — r and s must match byte-for-byte — then a sign→verify
// round-trip and a tamper-rejection check.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ __hexeq ( Vec u ) v s want → b {
    : String h ( bytes_to_hex v )
    : b ok ( nurl_str_eq ( string_data h ) want )
    ( string_free h )
    ^ ok
}

@ main → i {
    : ~ i fails 0
    : ( Vec u ) priv ( hx `c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721` )
    : ( Vec u ) msg ( bytes_from_str `sample` )
    : ( Vec u ) h ( sha256_pure msg )
    : ( Vec u ) sig ( ecdsa_p256_sign priv h )
    : ( Vec u ) r ( bytes_slice sig 0 32 )
    : ( Vec u ) s ( bytes_slice sig 32 64 )

    ? ( __hexeq r `efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716` )
    { ( nurl_print `rfc6979_r: PASS\n` ) } { ( nurl_print `rfc6979_r: FAIL\n` ) = fails + fails 1 }
    ? ( __hexeq s `f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8` )
    { ( nurl_print `rfc6979_s: PASS\n` ) } { ( nurl_print `rfc6979_s: FAIL\n` ) = fails + fails 1 }

    // Sign → verify round-trip against the RFC public key.
    : ( Vec u ) pk ( hx `0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299` )
    ? ( ecdsa_p256_verify pk r s h ) { ( nurl_print `roundtrip: PASS\n` ) } { ( nurl_print `roundtrip: FAIL\n` ) = fails + fails 1 }

    // Tamper: a different digest must not verify.
    : ( Vec u ) m2 ( bytes_from_str `not the message` )
    : ( Vec u ) h2 ( sha256_pure m2 )
    ( vec_free [u] m2 )
    ? ( ecdsa_p256_verify pk r s h2 ) { ( nurl_print `tamper: FAIL\n` ) = fails + fails 1 } { ( nurl_print `tamper: PASS\n` ) }

    ( nurl_print ? == fails 0 `ALL PASS\n` `SOME FAILED\n` )

    ( vec_free [u] priv ) ( vec_free [u] msg ) ( vec_free [u] h ) ( vec_free [u] sig )
    ( vec_free [u] r ) ( vec_free [u] s ) ( vec_free [u] pk ) ( vec_free [u] h2 )
    ^ 0
}
