// closure_param_clears_vec: a closure that clears a Vec is run by a callee while a borrow of its element is live.
// map: §2.11 | A2 | rejected | h71 | callee runs closure that clears Vec while element borrow is live
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a long element string on the heap` ) )
    ?? ( vec_get [String] xs 0 ) { T e → { ( run \ → v { ( vec_clear [String] xs ) } ) ( nurl_println_int ( string_len e ) ) } F → {} }
    ^ 0
}
