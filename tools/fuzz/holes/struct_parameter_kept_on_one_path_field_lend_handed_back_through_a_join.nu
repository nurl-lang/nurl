// struct_parameter_kept_on_one_path_field_lend_handed_back_through_a_join: agora #743 — `^ ? d ( f0s . p a ) ( fresh )`, p a struct parameter kept on another path
// Closed: a return that hands back what a call may lend out of a parameter the function takes over on another path is refused at module end, where whether it takes it over is known (__pfo_lend_note, resolve_pfo_lends; agora #743).
// main 3a71bef7: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #743: `^ ? d ( f0s . p a ) ( fresh )`, p a struct parameter kept on another path
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`

: H { String a i n }

@ f0s String p → String { ^ p }

@ fk inout ( Vec H ) log H p b c b d → String { ? c { ( vec_push [H] log p ) ^ ( string_from `fresh one, long enough for the heap, really` ) } {} ^ ? d ( f0s . p a ) ( string_from `other` ) }

@ run b c b d → v {
    : ~ ( Vec H ) log ( vec_new [H] )
    : H x @ H { ( string_from `a string long enough to live on the heap for sure` ) 1 }
    : String s ( fk log x c d )
    ( nurl_println ( string_data s ) )
}

@ main → i { ( run F T ) ^ 0 }
