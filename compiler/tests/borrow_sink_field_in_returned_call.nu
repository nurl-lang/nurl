// borrow_sink_field_in_returned_call.nu — a field of a borrow handed to a
// `sink` inside a RETURNED call (`: Col c ( vec_at [Col] cs 0 )` then
// `^ ( keep . c name )`) is refused as the same call bound first is (Agora
// #680). The call's row was stashed for the walk and recorded behind the
// `ret` row, which ends the path: never judged, the field was freed while
// the Vec still held it.
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
