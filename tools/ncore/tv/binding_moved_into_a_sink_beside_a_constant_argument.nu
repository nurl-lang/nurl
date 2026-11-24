$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v i z → i { ^ + ( vec_len [i] v ) z }

@ f i n → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v n )
    : i k ( vec_len [i] v )
    ? > n 2 { ^ + ( eat v 0 ) k } {}
    ^ + k n
}

@ main → i { ^ + ( f 1 ) ( f 5 ) }
