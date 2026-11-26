// A Vec cleared inside a foreach over it (the checker refuses it).
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ~ i acc 0
    ~ x v {
        ( vec_clear [i] v )
        = acc + acc x
    }
    ^ acc
}
