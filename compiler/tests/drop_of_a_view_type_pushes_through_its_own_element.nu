// A `% Drop` of a struct that holds a slice, whose code pushes through
// `( vec_at loc 0 )` of a local it made (Agora #909): the push reaches only
// memory the destructor owns, so it changes nothing the slice views.
// formal/A2/FreshWitness.lean types this program, memory safe and leak-free.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: V { ( Slice i ) s i k }

% Drop V { @ drop V d → v {
    : ( Vec ( Vec i ) ) loc ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] loc ( vec_new [i] ) )
    ( vec_push [i] ( vec_at [( Vec i )] loc 0 ) 7 )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] loc 0 ) ) )
    ( nurl_println_int ( slice_at [i] . d s 0 ) )
} }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : k 3
    : x @ V { s k }
    ^ 0
}
