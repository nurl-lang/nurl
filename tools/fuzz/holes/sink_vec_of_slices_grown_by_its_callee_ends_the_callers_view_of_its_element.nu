// sink_vec_of_slices_grown_by_its_callee_ends_the_callers_view_of_its_element: agora #949 — `@ f sink ( Vec ( Slice ( Vec i ) ) ) vv` grows `( slice_at ( vec_at vv 0 ) 0 )`; the caller reads s2, a view of that element, after `( f vv )`
// Closed (agora #949): a binding handed to a `sink` parameter, of a type that may hold views, gets a `pendsink` row, and the walk's after-call sweep reads it as it reads a lent argument: what points into the buffers of the elements of each source it holds a view of (`vds_`) ends where the callee may move one (`ireallocs`).
// main b4cdbac1: accepted; the read after the call is a heap-use-after-free (ASan).
// map: §2.10 | A2 | rejected | - | agora #949: a Vec of slices handed to a sink callee that grows its element's element, the caller's view of that element read after
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f sink ( Vec ( Slice ( Vec i ) ) ) vv → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_reserve [i] b 4096 )
    ^ 0
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : ( Slice i ) s2 ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) )
    ( nurl_println_int ( f vv ) )
    ( nurl_println_int ( slice_at [i] s2 0 ) )
    ^ 0
}
