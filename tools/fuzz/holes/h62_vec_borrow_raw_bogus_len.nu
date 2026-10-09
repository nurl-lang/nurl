// H62: vec_borrow_raw with a length the buffer does not have.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : ( Vec i ) ys ( vec_borrow_raw [i] ( vec_data [i] xs ) 100000 )
    ?? ( vec_get [i] ys 99999 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
