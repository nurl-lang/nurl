// A closure that captures a slice, called while the slice is live: its
// body pushes through `( vec_at loc 0 )` of a local it made (Agora #909).
// The push reaches only blocks the call owns, so it changes nothing the
// slice views. formal/A2/FreshClosureWitness.lean types this program,
// memory safe and leak-free.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : ( @ i ) f \ → i {
        : ( Vec ( Vec i ) ) loc ( vec_new [( Vec i )] )
        ( vec_push [( Vec i )] loc ( vec_new [i] ) )
        ( vec_push [i] ( vec_at [( Vec i )] loc 0 ) 7 )
        ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] loc 0 ) ) )
        ^ ( slice_at [i] s 0 )
    }
    ( nurl_println_int ( f ) )
    ^ 0
}
