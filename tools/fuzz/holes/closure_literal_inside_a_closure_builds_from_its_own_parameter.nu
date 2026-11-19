// closure_literal_inside_a_closure_builds_from_its_own_parameter: inside a closure with parameters a and b, a literal handing back `( mk p )` of its own parameter, called `( g b )` and run beside a view of b
// Closed (agora #838): the literal's `lr#` names its own parameter p as %0 — the literal's index, not the enclosing closure's — rewritten onto the call's argument b; the run of the result ends b's view.
// main cfbd6b0e: accepted; the read after the run prints a freed buffer's bytes (176), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a literal inside a closure, building from its own parameter, called on the closure's second parameter, run beside a view of it
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
        : ( Slice u ) sl ( slice_from_vec [u] b )
        ( d )
        ^ # i ( slice_at [u] sl 0 )
    }
    ( nurl_println_int ( outer xs ys ) )
    ^ 0
}
