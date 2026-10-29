// H619: `( vec_clear [i] . . k cn m )`: the Vec two fields down a sealed
// RsaKey (the modulus of its Montgomery context), cleared in place.
// Closed: the field chain is a sealed representation's field at any depth
// (agora #159).
// v0.80.0: accepted; _rsa_sign_raw checks the context since h459.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rsa_mont.nu`

@ main → i {
    : ( Vec u ) m ( vec_zeroed [u] 128 )
    ( vec_put [u] m 127 # u 1 )
    ( vec_put [u] m 0 # u 1 )
    : ( Vec u ) e ( vec_zeroed [u] 1 )
    : ( Vec u ) dd ( vec_zeroed [u] 1 )
    : RsaKey k ( _rsa_key_plain m e dd )
    ( vec_clear [i] . . k cn m )
    : ( Vec u ) msg ( vec_zeroed [u] 4 )
    ( nurl_println_int ( vec_len [u] ( _rsa_sign_raw k msg ) ) )
    ^ 0
}
