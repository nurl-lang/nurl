// field_of_a_borrow_handed_to_a_sink_as_the_implicit_tail_is_refused: `( keep . c name )` as a function's last expression, its value the result
// Closed: agora #680, the implicit tail is a return; its calls are judged before its `ret` row.
// main 0b3f239a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #680: a sink call as the implicit tail value is judged as the bound call is
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Col { String name i ty }

@ keep sink String x → i { ^ ( string_len x ) }

@ f ( Vec Col ) cs → i {
    : Col c ( vec_at [Col] cs 0 )
    ( keep . c name )
}

@ main → i {
    : ( Vec Col ) cs ( vec_new [Col] )
    ( vec_push [Col] cs @ Col { ( string_from `a column name long enough to be on the heap` ) 1 } )
    : i n ( f cs )
    ^ - ( string_len . ( vec_at [Col] cs 0 ) name ) n
}
