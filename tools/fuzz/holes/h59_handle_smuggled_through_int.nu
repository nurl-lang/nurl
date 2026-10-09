// H59: a Vec handle cast to an int, the Vec freed, the int cast back to a Vec.
$ `stdlib/core/vec.nu`

: ~ i g_h 0

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    = g_h # i xs
    ( vec_free [i] xs )
    : ( Vec i ) ys # ( Vec i ) g_h
    ( nurl_println_int ( vec_len [i] ys ) )
    ^ 0
}
