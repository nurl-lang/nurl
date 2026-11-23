$ `stdlib/core/vec.nu`

@ keep ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ f i n → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v n )
    : ~ ( Vec i ) w ( vec_new [i] )
    ? > n 2 { = w v } {}
    ^ + ( keep w ) n
}

@ main → i { ^ + ( f 1 ) ( f 5 ) }
