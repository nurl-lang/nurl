// closure_wrapping_a_closure_whose_maker_dropped_the_value_runs_clean: `mkf` drops its `sink` `H` before it returns a closure over nothing; the view is taken after, and releasing `( wrap c )` runs no `drop`
// Closed: an argument closure's set counts only where every maker on its way took the value over (`retcap` of each, agora #919): the shape the fix must keep.
// main 029b01d: accepted, runs clean.
// map: §2.14 | A2 | runs-clean | - | agora #919: mkf drops its sink H before returning a closure over nothing; releasing ( wrap c ) runs no drop
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ mkf sink H h → ( @ i ) { ^ \ → i { ^ 1 } }

@ wrap sink ( @ i ) c → ( @ i ) { ^ \ → i { ^ ( c ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    {
        : ( @ i ) c ( mkf @ H { r } )
        ( vec_push [u] ( rc_get [( Vec u )] r2 ) 8 )
        : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
        { : ( @ i ) d ( wrap c ) ( nurl_println_int ( d ) ) }
        ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    }
    ^ 0
}
