// A borrowed Vec parameter assigned to an `inout` one: a copy.
$ `stdlib/core/vec.nu`

@ take_copy ( Vec i ) a inout ( Vec i ) b → v { = b a }

@ main → i {
    : ~ ( Vec i ) x ( vec_new [i] )
    ( vec_push [i] x 3 )
    : ~ ( Vec i ) y ( vec_new [i] )
    ( take_copy x y )
    ^ + ( vec_len [i] x ) ( vec_len [i] y )
}
