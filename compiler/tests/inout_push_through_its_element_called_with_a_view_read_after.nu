// github#2041's direct-call form (AGORA-909): a function that changes the
// elements of its `inout` parameter through `( vec_at vv 0 )`, called with an
// argument that holds a view of another value, which is read after the call.
// The view does not reach `vv`, so the call changes nothing it views.
// formal/A2 types this program (A2/InoutViewArgWitness.lean, memory safe and
// leak-free): the borrow is rooted at an `inout` parameter, a binding of the
// frame's own, so the push is an `edit false` and `g` is not
// through-changing.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g inout ( Vec ( Vec i ) ) vv ( Slice i ) s → i {
    ( vec_push [i] ( vec_at [( Vec i )] vv 0 ) 7 )
    ^ ( slice_at [i] s 0 )
}

@ main → i {
    : ~ ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 5 )
    : ( Slice i ) s ( slice_from_vec [i] src )
    ( nurl_println_int ( g vv s ) )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] vv 0 ) ) )
    ^ 0
}
