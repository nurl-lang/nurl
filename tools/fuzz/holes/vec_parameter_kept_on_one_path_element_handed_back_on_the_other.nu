// vec_parameter_kept_on_one_path_element_handed_back_on_the_other: agora #743 — a `( Vec String )` parameter pushed into a Vec of Vecs on one path, `^ ( vec_at [String] p 0 )` on the other
// Closed: a return that hands back what a call may lend out of a parameter the function takes over on another path is refused at module end, where whether it takes it over is known (__pfo_lend_note, resolve_pfo_lends; agora #743).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #743: a `( Vec String )` parameter pushed into a Vec of Vecs on one path, `^ ( vec_at [String] p 0 )` on the other
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f1 inout ( Vec ( Vec String ) ) log ( Vec String ) p b c → String { ? c { ( vec_push [( Vec String )] log p ) ^ ( string_from `fresh one, long enough for the heap, really` ) } {} ^ ( vec_at [String] p 0 ) }

@ run b c → v {
    : ~ ( Vec ( Vec String ) ) log ( vec_new [( Vec String )] )
    : ~ ( Vec String ) x ( vec_new [String] )
    ( vec_push [String] x ( string_from `a string long enough to live on the heap for sure` ) )
    : String s ( f1 log x c )
    ( nurl_println ( string_data s ) )
    ( nurl_println_int ( vec_len [( Vec String )] log ) )
}

@ main → i {
    ( run T )
    ( run F )
    ^ 0
}
