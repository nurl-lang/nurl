// drop_at_a_functions_exit_under_the_view_it_falls_off_with: the same view as the body's fall-off value, no `^`
// Closed: a return hands back a value read through an Rc's payload; a binding the exit releases whose `% Drop` may drop, replace or move what its parameter reaches, on an Rc type the value is read through, refuses the return (agora #918).
// main 5916ad5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #918: the same view as the body's fall-off value, no ^
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ f ( Rc ( Vec u ) ) x → ( Slice u ) {
    : H h @ H { ( rc_clone [( Vec u )] x ) }
    ( slice_from_vec [u] ( rc_get [( Vec u )] x ) )
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Slice u ) sl ( f r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
