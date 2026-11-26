// A Vec filled in a loop, its length read after it.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k 5 {
        ( vec_push [i] v k )
        = k + k 1
    }
    ^ ( vec_len [i] v )
}
