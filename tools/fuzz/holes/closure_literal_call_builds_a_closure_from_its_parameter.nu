// closure_literal_call_builds_a_closure_from_its_parameter: `( g xs )`, g a literal handing back `( mk p )` of its parameter, run beside a view of xs
// Closed (agora #838): a literal's body records what a closure it hands back does (`lr#`, its own parameters as `%k`) and which of its closure parameters it hands back (`lq#`); a call of it gives its binding those effects, as a function's `retcloeff` / `retclo` do.
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (88), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a literal's call handing back a builder's closure over its parameter, run beside a view of the argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ ( @ v ) ( Vec u ) ) g \ ( Vec u ) p → ( @ v ) { ^ ( mk p ) }
    : ( @ v ) d ( g xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
