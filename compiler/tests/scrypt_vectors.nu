// scrypt_vectors.nu — pure-NURL scrypt against the RFC 7914 §12 test vectors,
// plus PBKDF2-HMAC-SHA-512 against reference vectors.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/scrypt.nu`
$ `stdlib/std/pbkdf2.nu`

@ sv s raw → ( Vec u ) {
    : i n ( nurl_str_len raw )
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get raw k ) ) = k + k 1 }
    ^ v
}

@ check s label ( Vec u ) got s want → i {
    : String gh ( bytes_to_hex got )
    ? ( nurl_str_eq ( string_data gh ) want ) { ( nurl_print label ) ( nurl_print `: PASS\n` ) ( string_free gh ) ^ 0 }
    { ( nurl_print label ) ( nurl_print `: FAIL got ` ) ( nurl_print ( string_data gh ) ) ( nurl_print `\n` ) ( string_free gh ) ^ 1 }
}

@ main → i {
    : ~ i fails 0

    // RFC 7914 §12, vector 1: scrypt("", "", 16, 1, 1, 64)
    : ( Vec u ) e ( sv `` )
    : ( Vec u ) s1 ( scrypt_pure e e 16 1 1 64 )
    = fails + fails ( check `scrypt N=16,r=1,p=1` s1 `77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906` )
    ( vec_free [u] s1 )

    // RFC 7914 §12, vector 2: scrypt("password", "NaCl", 1024, 8, 16, 64)
    : ( Vec u ) pw ( sv `password` )
    : ( Vec u ) na ( sv `NaCl` )
    : ( Vec u ) s2 ( scrypt_pure pw na 1024 8 16 64 )
    = fails + fails ( check `scrypt N=1024,r=8,p=16` s2 `fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640` )
    ( vec_free [u] s2 )

    // PBKDF2-HMAC-SHA-512
    : ( Vec u ) sa ( sv `salt` )
    : ( Vec u ) k1 ( pbkdf2_hmac_sha512 pw sa 1 64 )
    = fails + fails ( check `pbkdf2-sha512 c=1` k1 `867f70cf1ade02cff3752599a3a53dc4af34c7a669815ae5d513554e1c8cf252c02d470a285a0501bad999bfe943c08f050235d7d68b1da55e63f73b60a57fce` )
    ( vec_free [u] k1 )
    : ( Vec u ) k2 ( pbkdf2_hmac_sha512 pw sa 4096 32 )
    = fails + fails ( check `pbkdf2-sha512 c=4096` k2 `d197b1b33db0143e018b12f3d1d1479e6cdebdcc97c5c0f87f6902e072f457b5` )
    ( vec_free [u] k2 )

    ( vec_free [u] e ) ( vec_free [u] pw ) ( vec_free [u] na ) ( vec_free [u] sa )

    ? == fails 0 { ( nurl_print `scrypt/pbkdf2: all vectors PASS\n` ) } { ( nurl_print `scrypt/pbkdf2: FAILURES\n` ) }
    ^ fails
}
