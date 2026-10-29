// H638: as h618, with the function that clears the Vec defined after its
// caller: when `( wipe . k d )` is compiled, nothing is known yet of what
// `wipe` does with its argument, and it emptied the sealed RsaKey's limbs.
// Closed: the call is parked and decided at module end by `wipe`'s final
// summary — it clears its argument, so the call is a write to the sealed
// field (resolve_sealed_handoffs; agora #159).
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
    ( wipe . k d )
    : ( Vec u ) msg ( vec_zeroed [u] 4 )
    ( nurl_println_int ( vec_len [u] ( _rsa_sign_raw k msg ) ) )
    ^ 0
}

@ wipe ( Vec i ) v → v { ( vec_clear [i] v ) ( vec_shrink_to_fit [i] v ) }
