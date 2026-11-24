$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    : ~ ( Vec i ) b ( vec_new [i] )
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ~ i k 0
    ~ < k 3 {
        = t a
        = a b
        = b t
        = k + k 1
    }
    ^ + ( vec_len [i] a ) ( vec_len [i] b )
}
