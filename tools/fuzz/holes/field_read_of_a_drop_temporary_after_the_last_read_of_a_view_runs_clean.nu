// field_read_of_a_drop_temporary_after_the_last_read_of_a_view_runs_clean: the view through r2 read first, then `. ( mk r ) n` and `. @ H { ( rc_clone r ) 5 } n` read for a field: their releases run H's `% Drop` after the view's last read
// Guard (agora #895): the release swept as a call of the struct's drop ends the views of what the drop changes from there on, not before.
// main aae76ca (with github#2103): ran clean (the call's), leaked the literal.
// map: §2.14 | A2 | runs-clean | - | agora #895: a field read of a `% Drop` temporary after the last read of a view of the payload its drop clears
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
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( nurl_println_int . ( mk r ) n )
    ( nurl_println_int . @ H { ( rc_clone [( Vec u )] r ) 5 } n )
    ^ 0
}
