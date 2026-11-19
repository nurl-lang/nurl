// closure_literal_hands_back_its_closure_parameter: `( g c )`, g a literal handing back its closure parameter, c a builder's closure, run beside a view of xs
// Closed (agora #838): a literal's body records what a closure it hands back does (`lr#`, its own parameters as `%k`) and which of its closure parameters it hands back (`lq#`); a call of it gives its binding those effects, as a function's `retcloeff` / `retclo` do.
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (206), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a literal handing back its closure parameter, handed a builder's closure, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( @ ( @ v ) ( @ v ) ) g \ ( @ v ) f → ( @ v ) { ^ f }
    : ( @ v ) d ( g c )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
