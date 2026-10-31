// borrow_of_temporary_container: an element borrowed out of a temporary Vec (a call's fresh result) — the temporary leaks.
// map: §7.1 | A2 | runs-clean | h96 | element borrowed from temporary Vec call result; temporary leaks
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ mk → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long string element on the heap` ) )
    ^ v
}

@ main → i {
    ?? ( vec_get [String] ( mk ) 0 ) { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    ^ 0
}
