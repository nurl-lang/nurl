// handle_pushed_into_a_vec_of_shares_past_a_view_through_another_runs_clean: `( vec_push hs r )` and `( vec_reserve hs 64 )` while a slice of the payload is taken through `r2`: growing a Vec of shares moves its own buffer, no Rc's payload (the shape the fix must keep)
// Closed: the rule compares what a call may change through an argument with what a view's source is or holds in its own storage (agora #712).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #712: a share pushed into a Vec of shares, past a view through another share
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( vec_push [( Rc ( Vec u ) )] hs r )
    ( vec_reserve [( Rc ( Vec u ) )] hs 64 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
