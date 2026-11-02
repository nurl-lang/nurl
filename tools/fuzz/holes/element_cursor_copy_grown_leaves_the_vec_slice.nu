// element_cursor_copy_grown_leaves_the_vec_slice: agora #411 — a `: ~` copy of a Vec element grown in place while a slice of the Vec is read (the shape the fix must keep: the element's buffer moves, not the Vec's)
// A SAFE program refused: since agora #439 a view of the Vec itself ends when an element's buffer moves, because a view taken through an element a call lends (`( string_data ( vec_at vs 0 ) )`) is recorded as one. The element copy is still the element's, not the Vec's handle (agora #411). Back to runs-clean once such views are marked as element views (#430).
// main: accepted, ran clean.
// map: §2.10 | A1 | rejected | - | agora #411, #439: a `: ~` copy of a Vec element grown in place while a slice of the Vec is read (safe; refused until #430)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }

@ main → i {
    : ( Vec H ) vs ( vec_new [H] )
    ( vec_push [H] vs @ H { ( string_from `an element's name, short` ) } )
    ( vec_push [H] vs @ H { ( string_from `another element's name, short` ) } )
    : ( Slice H ) sl ( slice_from_vec [H] vs )
    : H e ( vec_at [H] vs 0 )
    : ~ H c e
    ( string_push_str . c name ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println ( string_data . e name ) )
    ( nurl_println_int ( slice_len [H] sl ) )
    ^ 0
}
