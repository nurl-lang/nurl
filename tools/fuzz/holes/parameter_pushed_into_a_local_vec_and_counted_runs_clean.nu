// parameter_pushed_into_a_local_vec_and_counted_runs_clean: `( vec_push hs h )` and `( vec_len hs )` in a helper handed `r` (the shape the fix must keep)
// Closed: a local a parameter was put into — a literal, a container it was pushed into, the result of a call that keeps it, `( box_new h )` — holds the parameter's storage (g_pderiv, g_pd_put), and so does a closure literal's local copy of its own parameter: what a call changes through it is in the summary (agora #770).
// main 5e576b82: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #770: a parameter pushed into a local Vec and counted
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ ch ( Rc ( Vec u ) ) h → i { : ~ ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] ) ( vec_push [( Rc ( Vec u ) )] hs h ) ^ # i ( vec_len [( Rc ( Vec u ) )] hs ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( nurl_println_int ( ch r ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
