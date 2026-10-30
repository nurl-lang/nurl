// field_borrow_whole_to_mutator: an element borrowed through `. b items`; the whole struct goes to a helper that clears that field; the borrow is read.
// map: §2.12 | A2 | rejected | h88 | element borrowed via field; whole struct to helper that clears field
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec String ) items }

@ clear_bag Bag b → v { ( vec_clear [String] . b items ) }

@ main → i {
    : Bag b @ Bag { ( vec_new [String] ) }
    ( vec_push [String] . b items ( string_from `a long element string on the heap` ) )
    : String e ( vec_at [String] . b items 0 )
    ( clear_bag b )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
