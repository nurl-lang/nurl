// A closure pushes onto a Vec it captured: its copy of the handle reaches the binding's buffer, which grows; the binding is read after.
$ `stdlib/core/vec.nu`
@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ( @ v i ) add \ i k → v { ( vec_push [i] v k ) }
    ( add 3 )
    ( add 4 )
    ( nurl_println_int ( vec_len [i] v ) )
    ^ 0
}
