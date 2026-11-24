$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    : ~ ( Vec i ) b ( vec_new [i] )
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ~ i k 0
    : ~ i n 0
    ~ < k 3 {
        = n + n ( vec_len [i] t )
        = t a
        = a b
        = b t
        = k + k 1
    }
    ^ + n ( vec_len [i] a )
}
