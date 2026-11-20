// sink_vec_of_slices_grown_by_its_callee_keeps_the_callers_view_of_the_outer_buffer_runs_clean: agora #949 guard — `@ f sink ( Vec ( Slice ( Vec i ) ) ) vv` grows `( slice_at ( vec_at vv 0 ) 0 )`; the caller reads sw, a view of w's own buffer, after `( f vv )`
// Accepted: f may move the buffer of an element of w, not w's own, so sw still points into a live buffer (the element handle it reads is updated in place).
// map: §2.10 | A2 | runs-clean | - | agora #949 guard: a Vec of slices handed to a sink callee that grows its element's element, the caller's view of the outer Vec's buffer read after
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
    : ( Slice ( Vec i ) ) sw ( slice_from_vec [( Vec i )] w )
    ( nurl_println_int ( f vv ) )
    ( nurl_println_int ( vec_len [i] ( slice_at [( Vec i )] sw 0 ) ) )
    ^ 0
}
