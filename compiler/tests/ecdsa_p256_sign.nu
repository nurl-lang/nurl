// ecdsa_p256_sign.nu — ECDSA P-256 signing with RFC 6979 deterministic
// nonces. KAT against the RFC 6979 A.2.5 (P-256, SHA-256) "sample" and
// "test" vectors — r and s must match byte-for-byte — then a sign→verify
// round-trip and a tamper-rejection check.
//
// Digests of other lengths: the nonce generator is HMAC-SHA-256 whatever
// the digest (the API takes the digest, not the hash function), so the
// SHA-224/384/512 rows are that variant's exact output, cross-checked
// with an independent RFC 6979 implementation and verified by OpenSSL as
// ECDSA-with-SHA-224/384/512 over "sample". Each must also verify here:
// a digest longer than the order is TRUNCATED to its leftmost 256 bits
// (FIPS 186-5 §6.4.1) on both sides — signing once reduced the whole
// digest mod n instead, which verify (and every other implementation)
// rejects. The prepared-key HMAC behind the nonce is checked against RFC
// 4231 test cases 1, 2 and 6, and reused across MACs.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ __hexeq ( Vec u ) v s want → b {
    : String h ( bytes_to_hex v )
    : b ok ( nurl_str_eq ( string_data h ) want )
    ( string_free h )
    ^ ok
}

@ filled i val i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u val ) = k + k 1 }
    ^ v
}

// Sign `h` (a digest of "sample") and check r‖s and that it verifies.
@ other s label ( Vec u ) h ( Vec u ) priv ( Vec u ) pk s wr s ws → i {
    : ( Vec u ) sig ( ecdsa_p256_sign priv h )
    : ( Vec u ) r ( bytes_slice sig 0 32 )
    : ( Vec u ) s ( bytes_slice sig 32 64 )
    : b ok & & ( __hexeq r wr ) ( __hexeq s ws ) ( ecdsa_p256_verify pk r s h )
    ( nurl_print label ) ( nurl_print ? ok `: PASS\n` `: FAIL\n` )
    ^ ? ok 0 1
}

// HMAC under a prepared key, twice (the second MAC starts from the
// midstates the first left alone) and against the one-shot form.
@ mac s label ( Vec u ) key ( Vec u ) msg s want → i {
    : HmacSha256 k ( hmac_sha256_key key )
    : ( Vec u ) m1 ( hmac_sha256_mac k msg )
    : ( Vec u ) m2 ( hmac_sha256_mac k msg )
    : b ok & & ( __hexeq m1 want ) ( __hexeq m2 want ) ( __hexeq ( hmac_sha256_pure key msg ) want )
    ( nurl_print label ) ( nurl_print ? ok `: PASS\n` `: FAIL\n` )
    ^ ? ok 0 1
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

    // RFC 6979 A.2.5, SHA-256, message "test".
    : ( Vec u ) ht ( sha256_pure ( bytes_from_str `test` ) )
    : ( Vec u ) st ( ecdsa_p256_sign priv ht )
    ? & ( __hexeq ( bytes_slice st 0 32 ) `f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367` ) ( __hexeq ( bytes_slice st 32 64 ) `019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083` )
    { ( nurl_print `rfc6979_test: PASS\n` ) } { ( nurl_print `rfc6979_test: FAIL\n` ) = fails + fails 1 }

    // Other digest lengths (HMAC-SHA-256 nonce): exact, and they verify.
    = fails + fails ( other `sha224` ( sha224_pure msg ) priv pk `41aac2925693c03ac1b034771ca0435582b420528ecf86ce51322b6d6f82c788` `28f850d0a21284f2cdfd3c2dd86fe9ba789283a56c9a59cdf81fa6fa051cbe64` )
    = fails + fails ( other `sha384` ( sha384_pure msg ) priv pk `ca1c84b1d0ad078c0ffe667645edc136034f462cee69a0fdbd8860fe1465d813` `403ad192be74fff02854c4efcd388d67c710cb2df0391295ecda96acf52e330e` )
    = fails + fails ( other `sha512` ( sha512_pure msg ) priv pk `962705d612647b04822c6060f31270f4b4cd703f6ba8fc1308c2a562ee600fc0` `af713dc0b1a1423422198a0edbce3b096f25c8e47d80988880ff472e579ab61f` )

    // The prepared HMAC key (RFC 4231), each key used for two MACs.
    = fails + fails ( mac `rfc4231_1` ( filled 11 20 ) ( bytes_from_str `Hi There` ) `b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7` )
    = fails + fails ( mac `rfc4231_2` ( bytes_from_str `Jefe` ) ( bytes_from_str `what do ya want for nothing?` ) `5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843` )
    = fails + fails ( mac `rfc4231_6` ( filled 170 131 ) ( bytes_from_str `Test Using Larger Than Block-Size Key - Hash Key First` ) `60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54` )

    ( nurl_print ? == fails 0 `ALL PASS\n` `SOME FAILED\n` )

    ( vec_free [u] priv ) ( vec_free [u] msg ) ( vec_free [u] h ) ( vec_free [u] sig )
    ( vec_free [u] r ) ( vec_free [u] s ) ( vec_free [u] pk ) ( vec_free [u] h2 )
    ^ 0
}
