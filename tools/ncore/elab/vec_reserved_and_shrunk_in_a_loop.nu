// A Vec's room reserved and given back in each round of a loop.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec u8 ) v ( vec_new [u8] )
    : ~ i n 0
    ~ < n 3 {
        ( vec_reserve [u8] v n )
        ( vec_push [u8] v 7 )
        ( vec_shrink_to_fit [u8] v )
        = n + n 1
    }
    ^ ( vec_len [u8] v )
}
