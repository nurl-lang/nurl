// A closure's caller cannot see what it captured, so a view it hands back
// may point into its arguments only (h220): a Slice of a captured Vec —
// here through a binding of the body — is rejected.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( @ ( Slice i ) ) f \ → ( Slice i ) { : ( Slice i ) s ( slice_from_vec [i] v ) s }
    : ( Slice i ) sl ( f )
    ( nurl_println_int ( slice_len [i] sl ) )
    ^ 0
}
