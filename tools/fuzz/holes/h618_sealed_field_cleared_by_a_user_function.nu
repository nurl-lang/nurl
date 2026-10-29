// H618: a function of the program that clears the Vec it is given, handed
// a sealed RsaKey's field: `( wipe . k d )` changed the key in place, the
// same as the container mutator in h459 does.
// Closed: a callee whose summary says it changes the argument is refused
// a sealed representation's field outside `unsafe` (agora #159; h638 for
// one defined after the call).
// v0.80.0: accepted; _rsa_sign_raw checks the limb counts since h459.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rsa_mont.nu`

@ wipe ( Vec i ) v → v { ( vec_clear [i] v ) ( vec_shrink_to_fit [i] v ) }

@ main → i {
    : ( Vec u ) m ( vec_zeroed [u] 128 )
    ( vec_put [u] m 127 # u 1 )
    ( vec_put [u] m 0 # u 1 )
    : ( Vec u ) e ( vec_zeroed [u] 1 )
    : ( Vec u ) dd ( vec_zeroed [u] 1 )
    : RsaKey k ( _rsa_key_plain m e dd )
    ( wipe . k d )
    : ( Vec u ) msg ( vec_zeroed [u] 4 )
    ( nurl_println_int ( vec_len [u] ( _rsa_sign_raw k msg ) ) )
    ^ 0
}
