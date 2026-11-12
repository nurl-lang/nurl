// option_parameter_kept_on_one_path_handed_back_as_a_lend_on_the_other: agora #743 — as string_parameter_kept_on_one_path_handed_back_as_a_lend_on_the_other, a `?String` parameter
// Closed: a return that hands back what a call may lend out of a parameter the function takes over on another path is refused at module end, where whether it takes it over is known (__pfo_lend_note, resolve_pfo_lends; agora #743).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #743: as string_parameter_kept_on_one_path_handed_back_as_a_lend_on_the_other, a `?String` parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f0 ? String p → ?String { ^ p }

@ f1 inout ( Vec ? String ) log ? String p b c → ?String { ? c { ( vec_push [? String] log p ) ^ @ ?String { T ( string_from `fresh one, long enough for the heap, really` ) } } {} ^ ( f0 p ) }

@ run b c → v {
    : ~ ( Vec ? String ) log ( vec_new [? String] )
    : ?String x @ ?String { T ( string_from `a string long enough to live on the heap for sure` ) }
    : ?String s ( f1 log x c )
    ?? s { T v → { ( nurl_println ( string_data v ) ) } F _ → {} }
    ( nurl_println_int ( vec_len [? String] log ) )
}

@ main → i {
    ( run T )
    ( run F )
    ^ 0
}
