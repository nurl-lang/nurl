// slice_of_drop_values_from_a_then_only_arm_released_under_a_view_of_a_shared_payload_is_refused: `? c { ( mks r ) } {}`, the then-only arm's discarded slice of `% Drop` values released where the arm ends, then a slice through another handle r2 of the payload it cleared read
// Closed (agora #931): an owned slice releases its elements, so releasing one of a `% Drop` type runs each element's drop for the borrow walk too (__udrop_fns, __rc_reach and __rc_runs_user_drop ask an owned slice's element type; a discarded slice's release is swept as a call of that drop, __udrop_release_tmp), as a single value's release is (agora #766).
// main 85a31ca: accepted; LeakSanitizer: the slice and its elements leaked (released by AGORA-903 at the arm end, the read was a heap-use-after-free).
// map: §2.14 | A2 | rejected | - | agora #931: `? c { ( mks r ) } {}`, the then-only arm's discarded slice of `% Drop` values released where the arm ends, then a slice through another handle r2 of the payload it cleared read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ mk ( Rc ( Vec u ) ) x → H { ^ @ H { ( rc_clone [( Vec u )] x ) } }

@ mks ( Rc ( Vec u ) ) x → [H { ^ [H | ( mk x )] }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : i c 1
    ? > c 0 { ( mks r ) } {}
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
