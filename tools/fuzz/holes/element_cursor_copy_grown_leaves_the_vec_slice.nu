// element_cursor_copy_grown_leaves_the_vec_slice: agora #411 — a `: ~` copy of a Vec element grown in place while a slice of the Vec is read (the shape the fix must keep: the element's buffer moves, not the Vec's)
// Closed: a copy of an element borrow is the element's, not the Vec's handle (__bck_hc_srcs, agora #411).
// main: accepted, ran clean.
// map: §2.10 | A1 | runs-clean | - | agora #411: a `: ~` copy of a Vec element grown in place while a slice of the Vec is read (the shape the fix must keep: the element's buffer moves, not the Vec's)
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
