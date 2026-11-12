// parameter_put_into_a_local_struct_and_read_runs_clean: `: H x @ H { h 1 }` and a read of `( rc_get . x a )` in a helper handed `r` (the shape the fix must keep)
// Closed: a local a parameter was put into — a literal, a container it was pushed into, the result of a call that keeps it, `( box_new h )` — holds the parameter's storage (g_pderiv, g_pd_put), and so does a closure literal's local copy of its own parameter: what a call changes through it is in the summary (agora #770).
// main 5e576b82: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #770: a parameter put into a local struct and read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a i n }

@ ch ( Rc ( Vec u ) ) h → i { : H x @ H { h 1 } ^ # i ( vec_len [u] ( rc_get [( Vec u )] . x a ) ) }

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
