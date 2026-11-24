$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ f i n → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v n )
    : ~ i k 0
    ? > n 2 { = k ( eat v ) } { = k 7 }
    ^ + k n
}

@ main → i { ^ + ( f 1 ) ( f 5 ) }
