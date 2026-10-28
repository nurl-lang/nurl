// H449: `@ RsaKey { … }` in safe code: a key whose plain exponent `d`
// was empty against a 16-limb context, and the signing path
// (`_rsa_sign_raw`) read 16 limbs of it. `@ RsaMont { 64 … }` forged a
// context the same way.
// Closed: RsaKey, RsaMont and RsaTmp are sealed (`raw :`); a literal of
// one is raw memory, which only an `unsafe` function may build.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rsa_mont.nu`

@ main → i {
    : ( Vec u ) m ( vec_zeroed [u] 128 )
    ( vec_put [u] m 127 # u 1 )
    ( vec_put [u] m 0 # u 1 )
    : ( Vec u ) e ( vec_zeroed [u] 1 )
    : RsaKey k @ RsaKey { m e F ( _rm_ctx m ) ( vec_new [i] ) ( _rm_ctx m ) ( _rm_ctx m ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) }
    : ( Vec u ) msg ( vec_zeroed [u] 4 )
    : ( Vec u ) s ( _rsa_sign_raw k msg )
    ( nurl_println_int ( vec_len [u] s ) )
    ^ 0
}
