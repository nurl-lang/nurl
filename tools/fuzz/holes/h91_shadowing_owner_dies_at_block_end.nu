// H91: an inner binding shadows an outer one of the same name; a borrow of the inner one outlives its block.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `outer element string on the heap` ) )
    : String keep ( string_from `keep` )
    : ~ String e keep
    ? > ( nurl_str_len `ab` ) 1 {
        : ( Vec String ) xs ( vec_new [String] )
        ( vec_push [String] xs ( string_from `inner element string on the heap` ) )
        ?? ( vec_get [String] xs 0 ) { T x → { = e x } F → {} }
    } {}
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
