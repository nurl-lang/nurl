// slice_of_drop_values_lent_by_a_then_only_arm_runs_clean: `? c { hs } {}`, a then-only arm naming a slice binding of `% Drop` values: the binding is lent, released after the view is read
// Closed (agora #931): an owned slice releases its elements, so releasing one of a `% Drop` type runs each element's drop for the borrow walk too (__udrop_fns, __rc_reach and __rc_runs_user_drop ask an owned slice's element type; a discarded slice's release is swept as a call of that drop, __udrop_release_tmp), as a single value's release is (agora #766).
// main 85a31ca: runs clean (the guard against a fix that refuses it).
// map: §2.14 | A2 | runs-clean | - | agora #931: `? c { hs } {}`, a then-only arm naming a slice binding of `% Drop` values: the binding is lent, released after the view is read
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
    : [H hs [H | ( mk r )]
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : i c 1
    ? > c 0 { hs } {}
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
