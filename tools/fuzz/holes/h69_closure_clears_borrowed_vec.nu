// H69: a closure that clears a Vec runs while a borrow of its element is live.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long element string on the heap` ) )
    : ( @ v ) wipe \ → v { ( vec_clear [String] v ) }
    ?? ( vec_get [String] v 0 ) { T e → { ( wipe ) ( nurl_println_int ( string_len e ) ) } F → {} }
    ^ 0
}
