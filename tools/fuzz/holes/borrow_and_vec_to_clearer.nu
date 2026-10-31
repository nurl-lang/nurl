// borrow_and_vec_to_clearer: an element borrow and its Vec handed to one function that clears the Vec, then reads the borrow.
// map: CallT.args | A1 | rejected | h64 | element borrow and its Vec passed to fn that clears Vec then reads borrow
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clear_then_read ( Vec String ) v String e → i {
    ( vec_clear [String] v )
    ^ ( string_len e )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long element string on the heap` ) )
    ?? ( vec_get [String] v 0 ) { T e → { ( nurl_println_int ( clear_then_read v e ) ) } F → {} }
    ^ 0
}
