// drop_changing_a_shared_payload_released_as_the_tail_of_a_then_only_arm: `? c { ( mk r ) } {}`, `mk` handing back an `H` over a clone of its argument: the arm's discarded tail value is released where the arm ends, running the `drop` that clears the payload a slice through `r2` views
// Closed: a then-arm's discarded tail value of a `% Drop` type is owned and released where the arm ends (agora #917), and that release is swept as a call of its `drop` (agora #766).
// main 5f3d33e: accepted; LeakSanitizer: the value leaked and its destructor never ran.
// map: §2.14 | A2 | rejected | - | agora #766: a then-only arm's discarded tail value whose drop clears a shared payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ mk ( Rc ( Vec u ) ) x → H { ^ @ H { ( rc_clone [( Vec u )] x ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : i c 1
    ? > c 0 { ( mk r ) } {}
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
