// H56: safe code copies one Vec's ctl field into another: two owners of one block.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    : ~ ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] a 1 )
    = . b ctl . a ctl
    ( nurl_println_int ( vec_len [i] b ) )
    ^ 0
}
