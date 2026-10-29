// H448: `( hkdf_expand_in prk info out at length )` and
// `hkdf_expand_label_in` with `at` near 2^63: their shared range check
// (`at + length <= len`) wrapped and passed, and the output key material
// was written far past `out`'s buffer.
// Closed: the check is `length <= len - at`, which cannot wrap; both
// return F and write nothing.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/hkdf.nu`

@ main → i {
    : ( Vec u ) key ( vec_new [u] )
    : HmacSha256 k ( hmac_sha256_key key )
    : ( Vec u ) m ( vec_new [u] )
    : ( Vec u ) o ( vec_zeroed [u] 64 )
    : b r1 ( hkdf_expand_in k m o 9223372036854775800 100 )
    : b r2 ( hkdf_expand_label_in k `x` m o 9223372036854775800 100 )
    ( nurl_println ? | r1 r2 `written` `refused` )
    ^ 0
}
