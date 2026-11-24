$ `stdlib/core/vec.nu`

: Two { ( Vec i ) a ( Vec i ) b }

@ mk ( Vec ( Vec i ) ) vv → Two { ^ @ Two { ( vec_at [( Vec i )] vv 0 ) ( vec_at [( Vec i )] vv 1 ) } }

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    : Two t ( mk vv )
    ^ 0
}
