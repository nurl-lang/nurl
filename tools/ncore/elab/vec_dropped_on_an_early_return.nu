// A Vec left behind by an early return from inside an if.
$ `stdlib/core/vec.nu`

@ f i n → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v n )
    ? > n 2 { ^ 0 } {}
    ( vec_push [i] v n )
    ^ ( vec_len [i] v )
}

@ main → i { ^ + ( f 1 ) ( f 5 ) }
