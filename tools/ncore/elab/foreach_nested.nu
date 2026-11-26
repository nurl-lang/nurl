// A foreach inside a foreach, over two Vecs.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    : ~ ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] a 1 )
    ( vec_push [i] a 2 )
    ( vec_push [i] b 3 )
    : ~ i acc 0
    ~ x a {
        ~ y b { = acc + acc * x y }
    }
    ^ acc
}
