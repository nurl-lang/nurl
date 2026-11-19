// sink_vec_of_slices_grown_beside_a_view_of_its_element: agora #933 — `@ f sink ( Vec ( Slice ( Vec i ) ) ) vv ( Slice i ) s2` grows `( slice_at ( vec_at vv 0 ) 0 )`, then reads s2, a view of that element
// Closed (agora #933): a grower handed an element read out of a slice the parameter holds is the parameter's `ireallocs` (an element accessor's container counts, __sx_nroots), and the call refuses another argument pointing into an element of what that argument holds a view of (__bck_held_view_srcs).
// main eedbedfd: accepted; the read of s2 inside the callee reads a freed block (prints 22967022162, not 5).
// map: §2.10 | A2 | rejected | - | agora #933: a sink Vec of slices grown through its element's element beside a view of that element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f sink ( Vec ( Slice ( Vec i ) ) ) vv ( Slice i ) s2 → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_reserve [i] b 4096 )
    ^ ( slice_at [i] s2 0 )
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : ( Slice i ) s2 ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) )
    ( nurl_println_int ( f vv s2 ) )
    ^ 0
}
