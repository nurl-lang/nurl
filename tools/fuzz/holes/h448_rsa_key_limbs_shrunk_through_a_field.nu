// H448: a sealed RsaKey's limb vectors are still readable fields, and
// `vec_clear` + `vec_shrink_to_fit` on `. ( . k cn ) m` and `. k d`
// released their storage in place; `_rsa_sign_raw` then ran the
// Montgomery kernels over the freed limbs.
// Closed: `_rsa_sign_raw` checks the key's limb counts against its
// contexts once a signature (__rm_key_ok) and signs nothing (an empty
// Vec) for a key that no longer matches.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rsa_mont.nu`

@ main → i {
    : ( Vec u ) m ( vec_zeroed [u] 128 )
    ( vec_put [u] m 127 # u 1 )
    ( vec_put [u] m 0 # u 1 )
    : ( Vec u ) e ( vec_zeroed [u] 1 )
    : ( Vec u ) d ( vec_zeroed [u] 1 )
    : RsaKey k ( _rsa_key_plain m e d )
    : RsaMont c . k cn
    ( vec_clear [i] . c m ) ( vec_shrink_to_fit [i] . c m )
    ( vec_clear [i] . k d ) ( vec_shrink_to_fit [i] . k d )
    : ( Vec u ) msg ( vec_zeroed [u] 4 )
    : ( Vec u ) s ( _rsa_sign_raw k msg )
    ( nurl_println_int ( vec_len [u] s ) )
    ^ 0
}
