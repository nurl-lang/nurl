// sink_vec_of_slices_forwarded_to_a_grower_ends_the_callers_view_of_its_element: agora #949 — `@ g sink ( Vec ( Slice ( Vec i ) ) ) vv` calls `( f vv )`, and f grows `( slice_at ( vec_at vv 0 ) 0 )`; the caller reads s2, a view of that element, after `( g vv )`
// Closed (agora #949): g's `ireallocs` already has its parameter (it hands it to f, which grows through it); the caller's `pendsink` row lets the after-call sweep end what points into the buffers of the elements `vv` views.
// main b4cdbac1: accepted; the read after the call is a heap-use-after-free (ASan).
// map: §2.10 | A2 | rejected | - | agora #949: a Vec of slices handed to a sink forwarder whose callee grows its element's element, the caller's view of that element read after
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( Vec ( Slice ( Vec i ) ) ) vv → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_reserve [i] b 4096 )
    ^ 0
}

@ g sink ( Vec ( Slice ( Vec i ) ) ) vv → i {
    ^ ( f vv )
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : ( Slice i ) s2 ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) )
    ( nurl_println_int ( g vv ) )
    ( nurl_println_int ( slice_at [i] s2 0 ) )
    ^ 0
}
