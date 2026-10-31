// sealed_field_viewed_by_a_binding_then_cleared: `: ( Vec i ) d . k d` and then `( vec_clear [i] d )`: a binding
// read out of a sealed RsaKey's field is a view of the same buffer, and
// clearing it emptied the key's limbs in place — as `( vec_clear [i]
// . k d )` did (h459).
// Closed: a handle bound from a sealed representation's field views it,
// and handing the view to a callee that may change it is a write to that
// field (agora #159).
// v0.80.0: accepted; _rsa_sign_raw checks the limb counts since h459, so
// it signs nothing instead of reading past the buffer.
// map: §3.3d | B | rejected | h617 | `: ( Vec i ) d . k d` then `( vec_clear [i] d )`: a binding read out of a sealed RsaKey's field views its buffer; handing the view to a mutator is a write to the field (agora #159).
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
    ( vec_clear [i] d ) ( vec_shrink_to_fit [i] d )
    : ( Vec u ) msg ( vec_zeroed [u] 4 )
    ( nurl_println_int ( vec_len [u] ( _rsa_sign_raw k msg ) ) )
    ^ 0
}
