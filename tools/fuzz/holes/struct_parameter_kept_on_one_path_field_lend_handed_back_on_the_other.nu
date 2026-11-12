// struct_parameter_kept_on_one_path_field_lend_handed_back_on_the_other: agora #743 — a struct parameter pushed on one path, `^ ( f0 . h a )` on the other
// Closed: a return that hands back what a call may lend out of a parameter the function takes over on another path is refused at module end, where whether it takes it over is known (__pfo_lend_note, resolve_pfo_lends; agora #743).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #743: a struct parameter pushed on one path, `^ ( f0 . h a )` on the other
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String a i n }

@ f0 String p → String { ^ p }

@ f1 inout ( Vec H ) log H h b c → String { ? c { ( vec_push [H] log h ) ^ ( string_from `fresh one, long enough for the heap, really` ) } {} ^ ( f0 . h a ) }

@ run b c → v {
    : ~ ( Vec H ) log ( vec_new [H] )
    : H x @ H { ( string_from `a string long enough to live on the heap for sure` ) 1 }
    : String s ( f1 log x c )
    ( nurl_println ( string_data s ) )
    ( nurl_println_int ( vec_len [H] log ) )
}

@ main → i {
    ( run T )
    ( run F )
    ^ 0
}
