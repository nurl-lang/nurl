// diag_borrow_elem_lend_grow_same_vec_element.nu — in a Vec of Vecs, growing
// the element a view points into ends that view, though a view of another
// element stays (elem_lend_grow_keeps_other_views' other_vec_element): the
// push through `( vec_at vv 1 )` moves element 1's buffer (AGORA-1037).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ( vec_push [i] ( vec_at [( Vec i )] vv 1 ) 7 )
    : ( Slice i ) d1 ( slice_from_vec [i] ( vec_at [( Vec i )] vv 1 ) )
    : ~ i k 0
    ~ < k 64 {
        ( vec_push [i] ( vec_at [( Vec i )] vv 1 ) k )
        = k + k 1
    }
    ( nurl_println_int ( slice_at [i] d1 0 ) )
    ^ 0
}
