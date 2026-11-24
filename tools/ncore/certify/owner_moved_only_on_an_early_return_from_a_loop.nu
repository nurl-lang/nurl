$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ f i n → i {
    : ~ ( Vec i ) acc ( vec_new [i] )
    : ~ i k 0
    ~ < k n {
        ? == k 3 { ^ ( eat acc ) } {}
        ( vec_push [i] acc k )
        = k + k 1
    }
    ^ ( vec_len [i] acc )
}

@ main → i { ^ + ( f 5 ) ( f 2 ) }
