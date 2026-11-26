// Two Vecs exchanged by moves, each read after.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    : ~ ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ( Vec i ) t a
    = a b
    = b t
    ^ - ( vec_len [i] b ) ( vec_len [i] a )
}
