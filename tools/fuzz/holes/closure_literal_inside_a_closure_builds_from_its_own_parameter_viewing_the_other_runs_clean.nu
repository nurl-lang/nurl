// closure_literal_inside_a_closure_builds_from_its_own_parameter_viewing_the_other_runs_clean: the guard of closure_literal_inside_a_closure_builds_from_its_own_parameter: the view is of a, the closure's first parameter
// Closed (agora #838): the result's effects are on b alone (%0 of the literal, its argument b), so a view of a stays good; nothing is refused.
// main cfbd6b0e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #838: a literal inside a closure, building from its own parameter on b, run beside a view of a
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Vec u ) ys ( vec_new [u] )
    ( vec_push [u] ys 8 )
    : ( @ i ( Vec u ) ( Vec u ) ) outer \ ( Vec u ) a ( Vec u ) b → i {
        : ( @ ( @ v ) ( Vec u ) ) g \ ( Vec u ) p → ( @ v ) { ^ ( mk p ) }
        : ( @ v ) d ( g b )
        : ( Slice u ) sl ( slice_from_vec [u] a )
        ( d )
        ^ # i ( slice_at [u] sl 0 )
    }
    ( nurl_println_int ( outer xs ys ) )
    ^ 0
}
