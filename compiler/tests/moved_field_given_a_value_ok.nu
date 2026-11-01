// moved_field_given_a_value_ok.nu — the uses agora #280's rule keeps. A
// field a `sink` parameter took has a value again once it is assigned, and
// the struct's other fields stay usable; returning one of them is fine. An
// `inout` callee may take a field of its parameter too, as long as it gives
// the field a value before the caller gets the parameter back.
//
// Expected output:
//   1
//   1
//   2
//   1

$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder2 { ( Vec u ) buf ( Vec u ) other }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ other_of → ( Vec u ) {
    : Holder2 h @ Holder2 { ( vec_new [u] ) ( vec_new [u] ) }
    ( vec_push [u] . h other # u 1 )
    ( vec_push [u] . h other # u 2 )
    : i n ( take . h buf )
    ^ . h other
}

@ refill inout Holder2 h → v {
    : i n ( take . h buf )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder2 h @ Holder2 { ( vec_new [u] ) ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : i n ( take . h buf )
    = . h buf ( vec_new [u] )
    ( vec_push [u] . h buf # u 65 )
    ( nurl_println_int ( vec_len [u] . h buf ) )
    ( vec_push [u] . h other # u 7 )
    ( nurl_println_int ( vec_len [u] . h other ) )
    ( nurl_println_int ( vec_len [u] ( other_of ) ) )
    ( refill h )
    ( vec_push [u] . h buf # u 67 )
    ( nurl_println_int ( vec_len [u] . h buf ) )
    ^ 0
}
