// two_source_lending_call_over_four_lines_then_one_source_cleared_is_refused: `: S e ( two` / `a` / `b` / `0 )`, `two` handing back an element of either Vec, then `( vec_clear [S] a )` and `. e name` read
// Closed: the lends a call's arguments note on its later lines are one statement's, kept together for its binding (agora #678).
// main 0b3f239a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #678: a call lending two arguments over four lines binds both borrows
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ two ( Vec S ) a ( Vec S ) b i k → S { ? == k 0 { ^ ( vec_at [S] a 0 ) } {} ^ ( vec_at [S] b 0 ) }

@ main → i {
    : ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a-long-enough-name-to-live-on-the-heap-000` ) 1 } )
    : ( Vec S ) b ( vec_new [S] )
    ( vec_push [S] b @ S { ( string_from `b-long-enough-name-to-live-on-the-heap-000` ) 2 } )
    : S e ( two
    a
    b
    0 )
    ( vec_clear [S] a )
    ( nurl_print ( string_data . e name ) )
    ^ 0
}
