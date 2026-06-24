// p256_ecdh_vectors.nu — known-answer tests for the NIST P-256 (secp256r1)
// ECDH used by the TLS client. keygen(k) must equal k·G (cross-checked
// against a pure-Python P-256), and the exchange must be symmetric:
// a·(b·G) == b·(a·G).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`

// 32-byte big-endian scalar with low byte `lo` and second-low byte `hi`.
@ scalar i hi i lo → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : ~ i k 0
    ~ < k 30 { ( vec_push [u] v # u 0 ) = k + k 1 }
    ( vec_push [u] v # u hi )
    ( vec_push [u] v # u lo )
    ^ v
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

    // keygen(1) = the generator G (uncompressed)
    = fails + fails ( check `keygen1` ( p256_ecdh_keygen ( scalar 0 1 ) )
    `046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5` )

    // keygen(2) = 2G
    = fails + fails ( check `keygen2` ( p256_ecdh_keygen ( scalar 0 2 ) )
    `047cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1` )

    // keygen(256) = 256G — exercises multi-byte (big-endian) scalars
    = fails + fails ( check `keygen256` ( p256_ecdh_keygen ( scalar 1 0 ) )
    `0434a2d4a3b009165987ffd1528603ed61190d0b710d6a564c2db2e35f12d0441bbeaaed6a53a1e3c22bca71046e777fc0e7d766b9deddd81db424e7845e93b146` )

    // ECDH symmetry: a·(b·G) == b·(a·G)
    : ( Vec u ) a ( scalar 3 7 )
    : ( Vec u ) b ( scalar 9 11 )
    : ( Vec u ) A ( p256_ecdh_keygen a )
    : ( Vec u ) B ( p256_ecdh_keygen b )
    : ( Vec u ) sab ( p256_ecdh_shared a B )
    : ( Vec u ) sba ( p256_ecdh_shared b A )
    : String sab_h ( bytes_to_hex sab )
    = fails + fails ( check `ecdh_symmetry` sba ( string_data sab_h ) )

    ? == fails 0 { ( nurl_print `p256_ecdh: all vectors PASS\n` ) } { ( nurl_print `p256_ecdh: FAILURES\n` ) }
    ^ fails
}
