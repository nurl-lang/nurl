// A closure over a Vec the function names no more after the literal: the literal moves it into the environment.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( @ i i ) f \ i x → i { ^ + x ( vec_len [i] v ) }
    : i a ( f 1 )
    ^ + a ( f 2 )
}
