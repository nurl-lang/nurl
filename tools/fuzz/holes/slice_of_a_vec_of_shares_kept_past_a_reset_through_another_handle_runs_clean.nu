// slice_of_a_vec_of_shares_kept_past_a_reset_through_another_handle_runs_clean: a slice of `hs` itself kept past `( wipe r )`, then a payload read through its element (a view of a Vec of shares' own buffer, a loop over it, an element handle copied out: no payload view (the shape the fix must keep))
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage — its own buffer, its element handles and its elements' own fields stay (agora #726).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #726: a slice of a Vec of shares kept past a reset through another handle
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : ( Slice ( Rc ( Vec u ) ) ) ss ( slice_from_vec [( Rc ( Vec u ) )] hs )
    ( wipe r )
    ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] ( slice_at [( Rc ( Vec u ) )] ss 0 ) ) ) )
    ^ 0
}
