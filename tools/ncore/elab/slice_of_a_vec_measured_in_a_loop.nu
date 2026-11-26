// A slice of a Vec taken in each round of a loop, after the round's push.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    : ~ i n 0
    : ~ i acc 0
    ~ < n 4 {
        ( vec_push [i] v n )
        : ( Slice i ) s ( slice_from_vec [i] v )
        = acc + acc ( slice_len [i] s )
        = n + n 1
    }
    ^ acc
}
