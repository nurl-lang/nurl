// AGORA-909: a function that pushes through `( slice_at sl 0 )`, an element
// of a view of its `inout` parameter, called with an argument that holds a
// view of another value, which is read after the call. formal/A2 types this
// program (A2/FreshSatWitness.lean, memory safe and leak-free): the view of
// the frame's own binding is fresh, so is the element read through it, and
// the push is an `edit false`: `g` is not through-changing.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g inout ( Vec ( Vec i ) ) vv ( Slice i ) s → i {
    : ( Slice ( Vec i ) ) sl ( slice_from_vec [( Vec i )] vv )
    ( vec_push [i] ( slice_at [( Vec i )] sl 0 ) ( slice_at [i] s 0 ) )
    ^ ( vec_len [i] ( vec_at [( Vec i )] vv 0 ) )
}

@ main → i {
    : ~ ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 5 )
    : ( Slice i ) s ( slice_from_vec [i] src )
    ( nurl_println_int ( g vv s ) )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ^ 0
}
