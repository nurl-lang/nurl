// H564: agora #157 — a move-only value (a user `% Drop` type, a trait object) stored into an owner (dyn_value_used_after_its_vec_freed).
// Closed: the store row covers move-only values (agora #157).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Shape [T] {
    @ area T self → i
}

: Sq { ( Vec i ) side }

% Shape Sq { @ area Sq s → i { ^ ( vec_len [i] . s side ) } }

@ mksq → Sq {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 3 )
    ^ @ Sq { b }
}

@ main → i {
    : ( Vec % Shape ) v ( vec_new [% Shape] )
    : %Shape d ( dyn Shape ( mksq ) )
    ( vec_push [% Shape] v d )
    ( vec_free [% Shape] v )
    ( nurl_println_int ( area d ) )
    ^ 0
}
