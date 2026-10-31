// field_viewer_of_an_element_after_clear_through_a_borrow: agora #267 — the same field viewer of a vector element, with the clear going through another borrow of the vector (`: ( Vec S ) w ( id vs )`, `( vec_clear [S] w )`): its other borrows ended, the field viewer did not (field_viewer_of_an_element_after_clear_through_a_borrow).
// Closed: bck_br_survives — the element copy `e` is not part of what `w` is a copy of (the vector's own handle), so it and its field viewer end.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A1 | rejected | - | agora #267: a field viewer of a vector element read after a clear through another borrow of the vector
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ id ( Vec S ) x → ( Vec S ) { ^ x }

@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : S e ( vec_at [S] vs 0 )
    : String f . e name
    : ( Vec S ) w ( id vs )
    ( vec_clear [S] w )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
