// lending_call_wrapped_over_several_lines_then_its_source_cleared_is_refused: `: S e ( vec_at [S]` / `a` / `0 )`, then `( vec_clear [S] a )` and `. e name` read
// Closed: a pending lend is keyed by its statement's line, not the argument's (__bck_pend_line, __bck_pl_line), so a call over several lines lends to the binding as a one-line call does (agora #678).
// main 0b3f239a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #678: a lending call written over several lines binds its borrow; `vec_clear` of the source then refused
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a-long-enough-name-to-live-on-the-heap-000` ) 1 } )
    : S e ( vec_at [S]
    a
    0 )
    ( vec_clear [S] a )
    ( nurl_print ( string_data . e name ) )
    ^ 0
}
