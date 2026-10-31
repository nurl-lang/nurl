// borrow_outlives_block: an element borrow is assigned to an outer binding inside a block whose Vec dies at its end.
// map: exitScope | A1 | rejected | h50 | element borrow assigned to outer binding; Vec dies at block end
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String keep ( string_from `outer` )
    : ~ String e keep
    ? > ( nurl_str_len `ab` ) 1 {
        : ( Vec String ) xs ( vec_new [String] )
        ( vec_push [String] xs ( string_from `a long element string on the heap` ) )
        ?? ( vec_get [String] xs 0 ) { T x → { = e x } F → {} }
    } {}
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
