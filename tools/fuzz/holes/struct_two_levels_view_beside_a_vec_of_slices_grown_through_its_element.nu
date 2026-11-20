// struct_two_levels_view_beside_a_vec_of_slices_grown_through_its_element: agora #4115 (claude-formal's review of github#2109) — a view of the grown element two struct levels deep (`. . o h s`), beside a sink Vec of slices grown through its element's element
// nurlc, ncore and the engine all refuse it: what the other argument reaches includes what its value holds, through nested fields and an Rc's payload.
// map: §2.10 | A2 | rejected | - | agora #933: a view of the grown element two struct levels deep (`. . o h s`), beside a sink Vec of slices grown through its element's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Slice i ) s }
: O { H h }

@ f sink ( Vec ( Slice ( Vec i ) ) ) vv O o → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_reserve [i] b 4096 )
    ^ ( slice_at [i] . . o h s 0 )
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : O o @ O { @ H { ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) ) } }
    ( nurl_println_int ( f vv o ) )
    ^ 0
}
