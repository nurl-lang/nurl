// H459: `( slhdsa_keygen_derand 129 a b c )` with one-byte seeds: the
// hypertree's hashes read SK.seed and PK.seed as n = 16 bytes through
// `vec_data`, past the end of each Vec.
// Closed: a seed that is not n bytes gives keys with an empty pk and sk.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/slhdsa.nu`

@ main → i {
    : ( Vec u ) a ( vec_zeroed [u] 1 )
    : ( Vec u ) b ( vec_zeroed [u] 1 )
    : ( Vec u ) c ( vec_zeroed [u] 1 )
    : SlhKeys k ( slhdsa_keygen_derand 129 a b c )
    ( nurl_println_int ( vec_len [u] ( slhdsa_pk k ) ) )
    ^ 0
}
