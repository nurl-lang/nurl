// diag_struct_lit_option_field.nu — an option value in a struct literal's
// plain `i` field (agora #129). It used to reach clang as an insertvalue of
// `{ i1, i64 }` into an i64 slot, with a .ll line number and no source
// location; the literal now applies the binding's shape rule.
$ `stdlib/core/vec.nu`

: P { i x }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : P p @ P { ( vec_get [i] v 0 ) }
    ( nurl_println_int . p x )
    ^ 0
}
