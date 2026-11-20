// field_read_of_a_drop_call_temporary_under_a_view_of_a_shared_payload_is_refused: `( nurl_println_int . ( mk r ) n )` with H's `% Drop` clearing the payload r shares, then a slice through another handle r2 of that payload read
// Closed (agora #895): a struct temporary released where a field read takes what it needs runs its `% Drop` for the borrow walk too: the release is swept as a call of that drop (__udrop_release_tmp), as a discarded value's is (agora #766).
// main aae76ca (with github#2103): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #895: a field read of a call's `% Drop` struct releases it under a view of the payload its drop clears
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a i n }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ mk ( Rc ( Vec u ) ) x → H { ^ @ H { ( rc_clone [( Vec u )] x ) 5 } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( nurl_println_int . ( mk r ) n )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
