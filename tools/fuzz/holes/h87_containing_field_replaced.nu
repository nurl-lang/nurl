// H87: an element borrowed through `. . o b items`; the field holding it (`. o b`) is replaced; the borrow is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }
: Outer { Bag b }

@ fresh → Bag {
    : Bag b @ Bag { ( vec_new [String] ) }
    ( vec_push [String] . b items ( string_from `a long element string on the heap` ) )
    ^ b
}

@ main → i {
    : ~ Outer o @ Outer { ( fresh ) }
    : String e ( vec_at [String] . . o b items 0 )
    = . o b ( fresh )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
