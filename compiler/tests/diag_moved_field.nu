// diag_moved_field.nu — a field a `sink` parameter took is empty where it
// lives (agora #280): reading it, binding it, or handing its struct on
// whole before the field has a value again is refused, as a moved binding
// is. On main each of these compiled, and the next vec_push on the null
// handle faulted.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }
: Named { String s }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ eat sink String v → i { ^ ( string_len v ) }

@ grow Holder h → v { ( vec_push [u] . h buf # u 65 ) }

@ read_after_take → v {
    : Holder h @ Holder { ( vec_new [u] ) }
    : i n ( take . h buf )
    ( vec_push [u] . h buf # u 65 )
}

@ string_after_eat → v {
    : Named h @ Named { ( string_from `abc` ) }
    : i n ( eat . h s )
    ( string_push_str . h s `x` )
}

@ bind_after_take → v {
    : Holder h @ Holder { ( vec_new [u] ) }
    : i n ( take . h buf )
    : ( Vec u ) x . h buf
    ( vec_push [u] x # u 65 )
}

@ whole_after_take → v {
    : Holder h @ Holder { ( vec_new [u] ) }
    : i n ( take . h buf )
    ( grow h )
}

@ returned_after_take → Holder {
    : Holder h @ Holder { ( vec_new [u] ) }
    : i n ( take . h buf )
    ^ h
}

@ taken_in_one_arm i k → v {
    : Holder h @ Holder { ( vec_new [u] ) }
    ? == k 1 { ( take . h buf ) } {}
    ( vec_push [u] . h buf # u 65 )
}

@ main → i { ^ 0 }
