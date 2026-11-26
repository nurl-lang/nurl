// A Vec built in a function and handed back to its caller.
$ `stdlib/core/vec.nu`

@ make i n → ( Vec i ) {
    : ~ ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k n {
        ( vec_push [i] v k )
        = k + k 1
    }
    ^ v
}

@ main → i {
    : ( Vec i ) v ( make 3 )
    ^ ( vec_len [i] v )
}
