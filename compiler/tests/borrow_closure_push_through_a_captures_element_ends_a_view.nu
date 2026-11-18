// The counterpart of closure_over_a_slice_pushes_through_its_own_element
// (Agora #909): a closure that pushes through an element of a binding it
// captures by name reaches the caller's memory, so running it ends a view
// of that element. In the calculus that push is an `edit true`.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ( vec_push [i] ( vec_at [( Vec i )] vv 0 ) 5 )
    : ( @ v ) f \ → v { ( vec_push [i] ( vec_at [( Vec i )] vv 0 ) 7 ) }
    : ( Slice i ) s ( slice_from_vec [i] ( vec_at [( Vec i )] vv 0 ) )
    ( f )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ^ 0
}
