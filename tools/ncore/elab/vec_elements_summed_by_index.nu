// A Vec's elements read by index in a loop, one bound to a name.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    ( vec_push [i] v 4 )
    : ~ i k 0
    : ~ i acc 0
    ~ < k ( vec_len [i] v ) {
        = acc + acc ( vec_at [i] v k )
        = k + k 1
    }
    : i first ( vec_at [i] v 0 )
    ^ + acc first
}
