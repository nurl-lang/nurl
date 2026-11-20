// sink_vec_of_slices_read_by_its_callee_keeps_the_callers_view_of_its_element_runs_clean: agora #949 guard — `@ f sink ( Vec ( Slice ( Vec i ) ) ) vv` only reads `( slice_at ( vec_at vv 0 ) 0 )`; the caller reads s2, a view of that element, after `( f vv )`
// Accepted: f may move no element's buffer (its `ireallocs` is empty), so s2 still points into a live buffer.
// map: §2.10 | A2 | runs-clean | - | agora #949 guard: a Vec of slices handed to a sink callee that only reads its element's element, the caller's view of that element read after
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f sink ( Vec ( Slice ( Vec i ) ) ) vv → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    ^ ( vec_len [i] ( slice_at [( Vec i )] e 0 ) )
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
