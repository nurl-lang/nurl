// H66: an inout struct and a borrow of an element of its Vec in one call; the callee clears the Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }

@ clear_then_read inout Bag b String e → i {
    ( vec_clear [String] . b items )
    ^ ( string_len e )
}

@ main → i {
    : ~ Bag b @ Bag { ( vec_new [String] ) }
    ( vec_push [String] . b items ( string_from `a long element string on the heap` ) )
    ?? ( vec_get [String] . b items 0 ) { T e → { ( nurl_println_int ( clear_then_read b e ) ) } F → {} }
    ^ 0
}
