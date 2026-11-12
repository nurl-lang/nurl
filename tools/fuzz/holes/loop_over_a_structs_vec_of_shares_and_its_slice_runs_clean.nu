// loop_over_a_structs_vec_of_shares_and_its_slice_runs_clean: `~ h . w hs { ( wipe h ) }`, then a slice of `. w hs` kept past `( wipe r )` (a view of a Vec of shares' own buffer, a loop over it, an element handle copied out: no payload view (the shape the fix must keep))
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage — its own buffer, its element handles and its elements' own fields stay (agora #726).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #726: a loop over a struct's Vec of shares and a slice of it kept past a reset
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

: W { ( Vec ( Rc ( Vec u ) ) ) hs }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : W w @ W { hs }
    ~ h . w hs { ( wipe h ) }
    : ( Slice ( Rc ( Vec u ) ) ) ss ( slice_from_vec [( Rc ( Vec u ) )] . w hs )
    ( wipe r )
    ( nurl_println_int # i ( slice_len [( Rc ( Vec u ) )] ss ) )
    ^ 0
}
