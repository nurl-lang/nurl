// closure_from_a_maker_that_does_not_take_the_drop_value_runs_clean: `mkf2` borrows the `H` and returns a closure over nothing: releasing the closure runs no `drop`
// Closed: only the impls of values the returned closure took over, whose summary changes the payload, are swept at its release (agora #919): the shape the fix must keep.
// main 5916ad5: accepted, runs clean.
// map: §2.14 | A2 | runs-clean | - | agora #919: mkf2 borrows the H and returns a closure over nothing: releasing the closure runs no drop
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ mkf2 H h → ( @ i ) { ^ \ → i { ^ 1 } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : H hh @ H { r }
    { : ( @ i ) f ( mkf2 hh ) ( nurl_println_int ( f ) ) }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
