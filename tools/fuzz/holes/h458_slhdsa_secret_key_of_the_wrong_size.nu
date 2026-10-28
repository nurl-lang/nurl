// H458: `( slhdsa_sign_deterministic 129 sk msg ctx )` with a 4-byte
// secret key: slhdsa_sign_internal sliced the four n-byte parts out of it
// (short or empty) and the FORS and hypertree hashes read them as n bytes
// each. Every signing form reached it.
// Closed: a secret key that is not slhdsa_sk_len bytes gives an empty
// signature, as verify returns F for a key or signature of the wrong size.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/slhdsa.nu`

@ main → i {
    : ( Vec u ) sk ( vec_zeroed [u] 4 )
    : ( Vec u ) m ( vec_zeroed [u] 4 )
    : ( Vec u ) c ( vec_new [u] )
    : ( Vec u ) s ( slhdsa_sign_deterministic 129 sk m c )
    ( nurl_println_int ( vec_len [u] s ) )
    ^ 0
}
