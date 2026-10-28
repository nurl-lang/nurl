// H451: `( p256ct_scalarmult k bx by )` with empty coordinate Vecs: the
// point was converted into Montgomery form four limbs at a time from
// whatever `bx` and `by` held.
// Closed: a coordinate that is not four limbs gives an empty result.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/p256_field.nu`

@ main → i {
    : ( Vec u ) k ( vec_zeroed [u] 32 )
    ( vec_put [u] k 31 # u 7 )
    : ( Vec i ) bx ( vec_new [i] )
    : ( Vec i ) by ( vec_new [i] )
    : ( Vec u ) r ( p256ct_scalarmult k bx by )
    ( nurl_println_int ( vec_len [u] r ) )
    ^ 0
}
