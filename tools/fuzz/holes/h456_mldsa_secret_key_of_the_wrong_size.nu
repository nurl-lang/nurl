// H456: `( mldsa_sign_deterministic 65 sk msg ctx )` with a 4-byte secret
// key: mldsa_sign_key unpacked s1, s2 and t0 from their fixed offsets,
// past the end of the Vec. Every signing form (mldsa_sign*,
// mldsa_sign_key) reached it.
// Closed: a secret key that is not mldsa_sk_len bytes gives a key that
// signs nothing — every signature under it is an empty Vec, as verify
// returns F for a key or signature of the wrong size.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/mldsa.nu`

@ main → i {
    : ( Vec u ) sk ( vec_zeroed [u] 4 )
    : ( Vec u ) m ( vec_zeroed [u] 4 )
    : ( Vec u ) c ( vec_new [u] )
    : ( Vec u ) s ( mldsa_sign_deterministic 65 sk m c )
    ( nurl_println_int ( vec_len [u] s ) )
    ^ 0
}
