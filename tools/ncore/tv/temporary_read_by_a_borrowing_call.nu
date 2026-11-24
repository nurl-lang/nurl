$ `stdlib/core/vec.nu`

@ look ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ mk i n → ( Vec i ) {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v n )
    ^ v
}

@ f i n → i { ^ + ( look ( mk n ) ) ( eat ( mk n ) ) }

@ main → i { ^ ( f 3 ) }
