// H85: an element borrowed through `. b items`; the field itself is replaced (its old Vec dropped); the borrow is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }

@ main → i {
    : ~ Bag b @ Bag { ( vec_new [String] ) }
    ( vec_push [String] . b items ( string_from `a long element string on the heap` ) )
    : String e ( vec_at [String] . b items 0 )
    = . b items ( vec_new [String] )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
