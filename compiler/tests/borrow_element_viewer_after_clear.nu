// borrow_element_viewer_after_clear.nu — agora #267. `f` views a field of
// `e`, a copy of the vector's first element: the String handle it holds
// is the element's. `vec_clear` drops the element and that String, so `f`
// ends with it. It was accepted, the one field viewer that survived
// elements changing, and read freed memory. The value borrows that do
// survive such a change are in elems_changed_value_borrows.nu.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ( Vec S ) vs ( vec_new [S] )
    ( vec_push [S] vs @ S { ( string_from `an element long enough for the heap` ) 1 } )
    : S e ( vec_at [S] vs 0 )
    : String f . e name
    ( vec_clear [S] vs )
    ^ ( string_len f )
}
