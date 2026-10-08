// H81: a slice of a Vec; a helper calls a helper that pushes (the buffer moves); the slice is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow2 ( Vec i ) v → v { : ~ i k 0 ~ < k 1000 { ( vec_push [i] v k ) = k + k 1 } }

@ grow1 ( Vec i ) v → v { ( grow2 v ) }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) sl ( slice_from_vec [i] v )
    ( grow1 v )
    ?? ( slice_get [i] sl 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
