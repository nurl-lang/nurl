// H620: `: ( Vec i ) d . k d`, `: ( Vec i ) d2 d`, then `( vec_clear [i]
// d2 )`: a copy of a view of a sealed RsaKey's field is the same buffer.
// Closed: a binding from a view views it too (agora #159).
// v0.80.0: accepted; _rsa_sign_raw checks the limb counts since h459.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rsa_mont.nu`

@ main → i {
    : ( Vec u ) m ( vec_zeroed [u] 128 )
    ( vec_put [u] m 127 # u 1 )
    ( vec_put [u] m 0 # u 1 )
    : ( Vec u ) e ( vec_zeroed [u] 1 )
    : ( Vec u ) dd ( vec_zeroed [u] 1 )
    : RsaKey k ( _rsa_key_plain m e dd )
    : ( Vec i ) d . k d
    : ( Vec i ) d2 d
    ( vec_clear [i] d2 )
    : ( Vec u ) msg ( vec_zeroed [u] 4 )
    ( nurl_println_int ( vec_len [u] ( _rsa_sign_raw k msg ) ) )
    ^ 0
}
