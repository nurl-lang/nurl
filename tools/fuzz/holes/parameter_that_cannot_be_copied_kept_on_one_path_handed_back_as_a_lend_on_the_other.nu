// parameter_that_cannot_be_copied_kept_on_one_path_handed_back_as_a_lend_on_the_other: agora #743 — a parameter of a struct with its own `% Drop` pushed on one path, `^ ( r0 p )` (r0 handing it back) on the other: nothing can stand in for the lend
// Closed: a return that hands back what a call may lend out of a parameter the function takes over on another path is refused at module end, where whether it takes it over is known (__pfo_lend_note, resolve_pfo_lends; agora #743).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #743: a parameter of a struct with its own `% Drop` pushed on one path, `^ ( r0 p )` (r0 handing it back) on the other: nothing can stand in for the lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R x → v { ( nurl_println `drop R` ) } }

@ r0 R p → R { ^ p }

@ f1 inout ( Vec R ) log R p b c → R { ? c { ( vec_push [R] log p ) ^ @ R { ( string_from `fresh one, long enough for the heap, really` ) 1 } } {} ^ ( r0 p ) }

@ run b c → v {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x @ R { ( string_from `a string long enough to live on the heap for sure` ) 2 }
    : R s ( f1 log x c )
    ( nurl_println ( string_data . s s ) )
    ( nurl_println_int ( vec_len [R] log ) )
}

@ main → i {
    ( run T )
    ( run F )
    ^ 0
}
