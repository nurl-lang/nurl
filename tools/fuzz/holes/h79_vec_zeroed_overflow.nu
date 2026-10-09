// H79: vec_zeroed with a length whose byte size wraps; the length is set over a tiny buffer.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_zeroed [i] 2305843009213693953 )
    ( vec_put [i] xs 5 1 )
    ( nurl_println_int ( vec_len [i] xs ) )
    ^ 0
}
