// hmac_mac_in_offset_wraps_its_range_check: `( hmac_sha256_mac_in k msg out at )` with `at` near 2^63: the
// range check `at + 32 > len` wrapped to a negative sum and passed, and
// the MAC was written 2^63 bytes past `out`'s buffer.
// Closed: the check is `at > len - 32`, which cannot wrap; the call
// returns F and writes nothing.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | runs-clean | h447 | `( hmac_sha256_mac_in k msg out at )` with `at` near 2^63: the range check `at + 32 > len` wrapped to a negative sum and passed, and the MAC was written 2^63 bytes past `out`'s buffer.
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha256.nu`

@ main → i {
    : ( Vec u ) key ( vec_new [u] )
    : HmacSha256 k ( hmac_sha256_key key )
    : ( Vec u ) m ( vec_new [u] )
    : ( Vec u ) o ( vec_zeroed [u] 64 )
    : b r ( hmac_sha256_mac_in k m o 9223372036854775800 )
    ( nurl_println ? r `written` `refused` )
    ^ 0
}
