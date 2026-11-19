// map: §2.10 | A2 | rejected | - | agora #844: a `( Vec ( Vec i ) )` parameter's element bound out of a local Slice of it, then grown
// AGORA-844: refused - a slice of a parameter's Vec reaches the parameter's elements: what changes through it is in the function's drop summary (__pd_holds_storage; main f9356928: accepted, heap-use-after-free)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ ext ( Vec ( Vec i ) ) v → v {
    : ( Slice ( Vec i ) ) sl ( slice_from_vec [( Vec i )] v )
    : ( Vec i ) e ( slice_at [( Vec i )] sl 0 )
    : ~ i k 0
    ~ < k 4096 { ( vec_push [i] e k ) = k + k 1 }
}

@ main → i {
    : ( Vec ( Vec i ) ) v ( vec_new [( Vec i )] )
    : ( Vec i ) row ( vec_new [i] )
    ( vec_push [i] row 7 )
    ( vec_push [( Vec i )] v row )
    : ( Slice i ) view ( slice_from_vec [i] ( vec_at [( Vec i )] v 0 ) )
    ( ext v )
    ( nurl_println_int ( slice_at [i] view 0 ) )
    ^ 0
}
