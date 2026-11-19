// drop_changing_a_payload_released_before_the_view_is_made_runs_clean: the `H` is released in a block that ends before the view is made (its `drop` empties the payload, refilled before the view)
// Closed: only a destructor whose summary changes the payload, released after the value is made, refuses a return (agora #918): the shape the fix must keep.
// main 5916ad5: accepted, runs clean.
// map: §2.14 | A2 | runs-clean | - | agora #918: the H is released in a block that ends before the view is made
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ f ( Rc ( Vec u ) ) x → ( Slice u ) {
    { : H h @ H { ( rc_clone [( Vec u )] x ) } }
    ( vec_push [u] ( rc_get [( Vec u )] x ) 9 )
    ^ ( slice_from_vec [u] ( rc_get [( Vec u )] x ) )
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Slice u ) sl ( f r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
