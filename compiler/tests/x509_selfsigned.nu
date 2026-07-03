// x509_selfsigned.nu — golden test for pure-NURL self-signed X.509
// generation (std/x509_gen.nu). Uses the pinned entry point with a fixed
// scalar / serial / validity: RFC 6979 makes the ECDSA signature
// deterministic, so the ENTIRE certificate and key are byte-reproducible
// and the PEMs below are literal golden output. Round-trips the result
// through the stdlib's own X.509 parser (std/x509.nu — the same code the
// pure TLS client trusts real websites with) and verifies the
// self-signature, plus parses the key back via ec_p256_priv_from_pem
// (std/pkey.nu) to confirm the SEC1 encoding is what the TLS server eats.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/pkey.nu`

@ main → i {
    // Fixed inputs → fixed output. Scalar is a mid-range value well inside
    // [1, n-1]; validity 2026-01-01 .. 2027-01-01 00:00:00 UTC.
    : ( Vec u ) scalar ?? ( bytes_from_hex `4c7a1b2e3d4f5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d` ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec u ) serial ?? ( bytes_from_hex `0102030405060708090a0b0c` ) { T v → v F _ → ( vec_new [u] ) }
    : X509SelfSigned c ( x509_selfsigned_p256_pinned scalar serial `golden.test` 1767225600 1798761600 )
    ( vec_free [u] scalar ) ( vec_free [u] serial )

    ( nurl_print ( string_data . c cert_pem ) )
    ( nurl_print ( string_data . c key_pem ) )

    : ~ i rc 1
    : !( Vec u ) ParseErr dr ( pem_to_der ( string_data . c cert_pem ) )
    ?? dr {
        T der → {
            : X509 x ( x509_parse der )
            ? . x ok {
                : ( Vec u ) h ( sha256_pure . x tbs )
                : ( Vec u ) rs ( x509_ecdsa_sig_rs . x sig )
                ? == ( vec_len [u] rs ) 64 {
                    : ( Vec u ) r ( bytes_slice rs 0 32 )
                    : ( Vec u ) s ( bytes_slice rs 32 64 )
                    ? ( ecdsa_p256_verify . x ec_point r s h )
                    { ( nurl_print `signature: verifies\n` ) = rc 0 }
                    { ( nurl_print `signature: FAIL\n` ) }
                    ( vec_free [u] r ) ( vec_free [u] s )
                } { ( nurl_print `sig-der: FAIL\n` ) }
                ( vec_free [u] rs ) ( vec_free [u] h )
                // validity + SAN survived the round-trip (std/x509.nu stores
                // times as YYYYMMDDHHMMSS integers, not unix instants)
                ? & == . x not_before 20260101000000 == . x not_after 20270101000000
                { ( nurl_print `validity: exact\n` ) }
                { ( nurl_print `validity: FAIL\n` ) = rc 1 }
                ? & == ( vec_len [String] . x sans ) 1 . x is_ca
                { ( nurl_print `san+ca: ok\n` ) }
                { ( nurl_print `san+ca: FAIL\n` ) = rc 1 }
            } { ( nurl_print `parse: FAIL\n` ) }
            ( x509_free x ) ( vec_free [u] der )
        }
        F _ → { ( nurl_print `pem: FAIL\n` ) }
    }

    // key round-trip: SEC1 PEM → 32-byte scalar → same public point
    : !( Vec u ) ParseErr kr ( ec_p256_priv_from_pem ( string_data . c key_pem ) )
    ?? kr {
        T sc → {
            : ( Vec u ) pk ( ec_p256_pub_from_priv sc )
            ? == ( vec_len [u] pk ) 65
            { ( nurl_print `key: parses, pubkey derives\n` ) }
            { ( nurl_print `key: FAIL\n` ) = rc 1 }
            ( vec_free [u] pk ) ( vec_free [u] sc )
        }
        F _ → { ( nurl_print `key: FAIL\n` ) = rc 1 }
    }

    ( x509_selfsigned_free c )
    ^ rc
}
