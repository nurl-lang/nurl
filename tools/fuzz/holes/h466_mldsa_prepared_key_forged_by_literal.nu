// H466: `@ MldsaKey { 65 … }` in safe code: a prepared ML-DSA-65 key with
// empty s1, s2, t0 and Â, which `mldsa_sign_mu_key` read at the level's
// sizes.
// Closed: MldsaKey is sealed (`raw :`); a literal of it is raw memory,
// which only an `unsafe` function may build.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/mldsa.nu`

@ main → i {
    : MldsaKey k @ MldsaKey { 65 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [i32] ) ( vec_new [i32] ) ( vec_new [i32] ) ( vec_new [i32] ) }
    : ( Vec u ) mu ( vec_zeroed [u] 64 )
    : ( Vec u ) r ( vec_zeroed [u] 32 )
    : ( Vec u ) s ( mldsa_sign_mu_key k mu r )
    ( nurl_println_int ( vec_len [u] s ) )
    ^ 0
}
