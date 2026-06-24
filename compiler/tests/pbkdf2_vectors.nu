// pbkdf2_vectors.nu — known-answer tests for PBKDF2-HMAC-SHA-256
// (the SHA-256 analogues of RFC 6070, cross-checked against Python's
// hashlib.pbkdf2_hmac). Validates the iteration/XOR accumulation used by
// SCRAM-SHA-256.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/pbkdf2.nu`

@ sv s raw → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : i n ( nurl_str_len raw )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( nurl_str_get raw k ) ) = k + k 1 }
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
    : ( Vec u ) p ( sv `password` )
    : ( Vec u ) s ( sv `salt` )

    = fails + fails ( check `c1` ( pbkdf2_hmac_sha256 p s 1 32 ) `120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b` )
    = fails + fails ( check `c2` ( pbkdf2_hmac_sha256 p s 2 32 ) `ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43` )
    = fails + fails ( check `c4096` ( pbkdf2_hmac_sha256 p s 4096 32 ) `c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a` )

    // dkLen spanning two HMAC blocks (40 bytes)
    = fails + fails ( check `c2_dk40` ( pbkdf2_hmac_sha256 p s 2 40 ) `ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43830651afcb5c862f` )

    ? == fails 0 { ( nurl_print `pbkdf2: all vectors PASS\n` ) } { ( nurl_print `pbkdf2: FAILURES\n` ) }
    ^ fails
}
