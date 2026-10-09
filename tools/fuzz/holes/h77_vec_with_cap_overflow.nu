// H77: vec_with_cap with a capacity whose byte size wraps; pushes write past the buffer.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_with_cap [i] 2305843009213693953 )
    ( vec_push [i] xs 1 ) ( vec_push [i] xs 2 ) ( vec_push [i] xs 3 )
    ( nurl_println_int ( vec_len [i] xs ) )
    ^ 0
}
