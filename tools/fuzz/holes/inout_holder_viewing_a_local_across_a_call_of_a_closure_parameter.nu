// inout_holder_viewing_a_local_across_a_call_of_a_closure_parameter: AGORA-382 (CodeRabbit on github#2047) — `= w @ W { ( string_data b ) }`, then `( f )` of a closure parameter whose body panics, then the repoint: the unwind frees b and the `recover` caller reads w
// AGORA-382: refused - a closure's body is not known where it is called, so the call may unwind
// map: §2.14 | A2 | rejected | - | AGORA-382: an inout holder viewing a local across a call of a closure parameter
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

@ fill inout W w ( @ v ) f → v {
    : String b ( string_from `the callee's local string, freed by the unwind, long enough` )
    = w @ W { ( string_data b ) }
    ( f )
    = w @ W { `literal again` }
}

@ main → i {
    : ~ W w @ W { `literal` }
    : !v PanicInfo r ( recover \ → v { ( fill w \ → v { ( panic `unwind` ) } ) } )
    ( nurl_println . w v )
    ^ 0
}
