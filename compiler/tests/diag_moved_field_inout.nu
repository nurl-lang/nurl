// diag_moved_field_inout.nu — a field of an `inout` parameter that a
// `sink` took goes back to the caller empty (agora #280). Each exit hands
// the parameter back whole, so the field must have a value again by then:
// the body's end and a `^` are both refused while it is taken, definitely
// or on some paths. On main these compiled, and the caller's next
// vec_push on the field faulted on the null handle.

$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ empty_it inout Holder h → v {
    : i n ( take . h buf )
}

@ empty_on_one_path inout Holder h i k → i {
    ? == k 1 { ( take . h buf ) } {}
    ^ k
}

// (Given a value again before it goes back: accepted.)
@ refill inout Holder h → v {
    : i n ( take . h buf )
    = . h buf ( vec_new [u] )
}

@ main → i { ^ 0 }
