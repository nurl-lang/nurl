// A view a call through a closure value hands back holds every argument
// (h220): growing the Vec it was handed ends it, as for a function.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( @ ( Slice i ) ( Vec i ) ) f \ ( Vec i ) w → ( Slice i ) { ( slice_from_vec [i] w ) }
    : ( Slice i ) sl ( f v )
    : ~ i k 0
    ~ < k 100 { ( vec_push [i] v k ) = k + k 1 }
    ?? ( slice_first [i] sl ) { T x → { ( nurl_println_int x ) } F _ → {} }
    ^ 0
}
