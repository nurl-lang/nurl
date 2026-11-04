// rc_get_payload_handed_to_a_sink_in_a_return: agora #463 — `?? ( rc_get [?String] r ) { T s → { ^ ( eat s ) } F → … }`
// Closed: a payload of what a call lends, handed in a return to a callee that takes it, is a borrow released as if owned: refused as the statement form is (the walk now reads the return's move rows) (agora #463).
// main: failed to build (use of an undefined value in the IR) (base 8a2afbc3).
// map: §7.5 | A2 | rejected | - | agora #463: `?? ( rc_get [?String] r ) { T s → { ^ ( eat s ) } F → … }`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ go ( Rc ? String ) r → i {
    ?? ( rc_get [? String] r ) { T s → { ^ ( eat s ) } F → { ^ 0 } }
}

@ main → i {
    : ( Rc ? String ) r ( rc_new [? String] @ ?String { T ( string_from `an rc option long enough for the heap` ) } )
    ( nurl_println_int ( go r ) )
    ( nurl_println_int ( go r ) )
    ^ 0
}
