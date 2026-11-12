// field_of_a_borrow_handed_to_a_sink_in_a_returned_call_is_refused: `: Col c ( vec_at [Col] cs 0 )` then `^ ( keep . c name )`, `keep` taking its String
// Closed: the rows of the calls in a returned expression are walked before its `ret` row (__bck_ret_flush_ppends), as a statement's are (agora #680).
// main 0b3f239a: accepted; AddressSanitizer: heap-use-after-free, then the Vec frees the String again.
// map: §2.10 | A2 | rejected | - | agora #680: a field of a borrow handed to a sink inside a returned call is refused as the bound call is
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Col { String name i ty }

@ keep sink String x → i { ^ ( string_len x ) }

@ f ( Vec Col ) cs → i {
    : Col c ( vec_at [Col] cs 0 )
    ^ ( keep . c name )
}

@ main → i {
    : ( Vec Col ) cs ( vec_new [Col] )
    ( vec_push [Col] cs @ Col { ( string_from `a column name long enough to be on the heap` ) 1 } )
    : i n ( f cs )
    ^ - ( string_len . ( vec_at [Col] cs 0 ) name ) n
}
