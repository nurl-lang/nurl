// The counterpart of drop_of_a_view_type_pushes_through_its_own_element
// (Agora #909): a push through `( vec_at p 0 )` of a PARAMETER reaches the
// caller's memory, so the call ends the caller's view of that element.
// In the calculus that push is an `edit true` (a borrowed parameter is no
// fresh source: A2/FreshWitness.lean's at_rootb_not_fresh).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g ( Vec ( Vec i ) ) p → v {
    ( vec_push [i] ( vec_at [( Vec i )] p 0 ) 7 )
}

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ( vec_push [i] ( vec_at [( Vec i )] vv 0 ) 5 )
    : ( Slice i ) s ( slice_from_vec [i] ( vec_at [( Vec i )] vv 0 ) )
    ( g vv )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ^ 0
}
