// rc_get_payload_handed_to_a_sink_in_a_closure_return: agora #463 — `: ( @ i ) c \ → i { ?? ( rc_get [?String] r ) { T s → { ^ ( eat s ) } F → … } }`
// Closed: the same inside a closure body (agora #463).
// main: failed to build (use of an undefined value in the IR) (base 8a2afbc3).
// map: §7.5 | A2 | rejected | - | agora #463: `: ( @ i ) c \ → i { ?? ( rc_get [?String] r ) { T s → { ^ ( eat s ) } F → … } }`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ( Rc ? String ) r ( rc_new [? String] @ ?String { T ( string_from `an rc option long enough for the heap` ) } )
    : ( @ i ) c \ → i { ?? ( rc_get [? String] r ) { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ( nurl_println_int ( c ) )
    ^ 0
}
