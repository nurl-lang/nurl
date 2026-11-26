// A Vec parameter pushed to without `inout`: the change is the summary's.
$ `stdlib/core/vec.nu`

@ grow ( Vec i ) v → v { ( vec_push [i] v 9 ) }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( grow v )
    ^ ( vec_len [i] v )
}
