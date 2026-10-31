// field_arg_borrow_then_set: an element borrowed through a field argument (vec_at of `. b items`); vec_set replaces it; the borrow is read.
// map: §2.12 | A2 | rejected | h82 | element borrowed via struct field (vec_at); vec_set replaces; borrow read
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }

@ main → i {
    : Bag b @ Bag { ( vec_new [String] ) }
    ( vec_push [String] . b items ( string_from `a long element string on the heap` ) )
    : String e ( vec_at [String] . b items 0 )
    ( vec_set [String] . b items 0 ( string_from `replacement` ) )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
