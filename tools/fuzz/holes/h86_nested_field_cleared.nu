// H86: an element borrowed through a nested field path (`. . o b items`); that field is cleared; the borrow is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }
: Outer { Bag b }

@ main → i {
    : Bag inner @ Bag { ( vec_new [String] ) }
    ( vec_push [String] . inner items ( string_from `a long element string on the heap` ) )
    : Outer o @ Outer { inner }
    : String e ( vec_at [String] . . o b items 0 )
    ( vec_clear [String] . . o b items )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
