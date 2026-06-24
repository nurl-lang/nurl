// hkdf_vectors.nu — RFC 5869 HKDF-SHA-256 + RFC 8448 TLS 1.3 key
// schedule known-answer tests for the pure-NURL HKDF.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hkdf.nu`

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

    // RFC 5869 Test Case 1 (SHA-256).
    : ( Vec u ) ikm ( hx `0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b` )
    : ( Vec u ) salt ( hx `000102030405060708090a0b0c` )
    : ( Vec u ) info ( hx `f0f1f2f3f4f5f6f7f8f9` )
    : ( Vec u ) prk ( hkdf_extract salt ikm )
    = fails + fails ( check `rfc5869_prk` prk `077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5` )
    : ( Vec u ) okm ( hkdf_expand prk info 42 )
    = fails + fails ( check `rfc5869_okm` okm `3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865` )

    // RFC 8448 — TLS 1.3 key schedule head.
    // early_secret = HKDF-Extract(salt=0^0?  -> 0, IKM=PSK=0^32)
    : ( Vec u ) zero32 ( hx `0000000000000000000000000000000000000000000000000000000000000000` )
    : ( Vec u ) zerosalt ( hx `00` )
    : ( Vec u ) early ( hkdf_extract zerosalt zero32 )
    = fails + fails ( check `tls13_early_secret` early `33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a` )

    // derived = Derive-Secret(early, "derived", "")  (transcript hash of empty)
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) ehash ( sha256_pure empty )
    = fails + fails ( check `sha256_empty` ehash `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` )
    : ( Vec u ) derived ( derive_secret early `derived` ehash )
    = fails + fails ( check `tls13_derived` derived `6f2615a108c702c5678f54fc9dbab69716c076189c48250cebeac3576c3611ba` )

    ? == fails 0 { ( nurl_print `hkdf: all vectors PASS\n` ) } { ( nurl_print `hkdf: FAILURES\n` ) }
    ^ fails
}
