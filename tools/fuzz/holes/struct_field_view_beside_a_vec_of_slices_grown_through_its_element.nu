// struct_field_view_beside_a_vec_of_slices_grown_through_its_element: agora #933 review (github#2109) — as sink_vec_of_slices_grown_beside_a_view_of_its_element, with the view of the grown element in a field of a struct passed beside vv
// nurlc refuses it (__bck_held_view_srcs against the other argument's pointees); ncore and the engine accepted it until github#2109 compared what the call changes through vv's slices with what the other argument's held views and handles point into.
// map: §2.10 | A2 | rejected | - | agora #933: a view of the grown element in a struct field, beside a sink Vec of slices grown through its element's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Slice i ) s }

@ f sink ( Vec ( Slice ( Vec i ) ) ) vv H h → i {
    : ( Slice ( Vec i ) ) e ( vec_at [( Slice ( Vec i ) )] vv 0 )
    : ~ ( Vec i ) b ( slice_at [( Vec i )] e 0 )
    ( vec_reserve [i] b 4096 )
    ^ ( slice_at [i] . h s 0 )
}

@ main → i {
    : ( Vec ( Vec i ) ) w ( vec_new [( Vec i )] )
    : ( Vec i ) w0 ( vec_new [i] )
    ( vec_push [i] w0 5 )
    ( vec_push [( Vec i )] w w0 )
    : ~ ( Vec ( Slice ( Vec i ) ) ) vv ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] vv ( slice_from_vec [( Vec i )] w ) )
    : H h @ H { ( slice_from_vec [i] ( vec_at [( Vec i )] w 0 ) ) }
    ( nurl_println_int ( f vv h ) )
    ^ 0
}
