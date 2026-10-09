// H61: vec_borrow_raw over another Vec's buffer outlives it.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : ( Vec i ) ys ( vec_borrow_raw [i] ( vec_data [i] xs ) 1 )
    ( vec_free [i] xs )
    ?? ( vec_get [i] ys 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
