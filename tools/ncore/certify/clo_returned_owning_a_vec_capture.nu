// A function hands back a closure over a Vec it made: the closure is returned where it is made, so its env owns the Vec (CORE_VF_ENVOWN), and the caller runs it after the function's frame is gone.
$ `stdlib/core/vec.nu`

@ mk_tab i seed → ( @ i i ) {
    : ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t seed )
    ^ \ i x → i { ^ + x ( vec_len [i] t ) }
}

@ main → i {
    : ( @ i i ) g ( mk_tab 5 )
    ( nurl_println_int ( g 2 ) )
    ^ 0
}
