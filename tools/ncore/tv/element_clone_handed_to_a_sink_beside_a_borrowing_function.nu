$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ keep ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ f i n → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    : i k ( keep ( vec_at [( Vec i )] vv 0 ) )
    ^ + ( eat ( vec_at [( Vec i )] vv 0 ) ) k
}

@ main → i { ^ + ( f 1 ) ( f 5 ) }
