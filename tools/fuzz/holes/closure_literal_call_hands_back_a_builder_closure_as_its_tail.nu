// closure_literal_call_hands_back_a_builder_closure_as_its_tail: a closure literal's call hands back, as its body's tail, a builder's closure it captured, run beside a view of xs
// Closed (agora #838): a literal's body records what a closure it hands back does (`lr#`, its own parameters as `%k`) and which of its closure parameters it hands back (`lq#`); a call of it gives its binding those effects, as a function's `retcloeff` / `retclo` do.
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (62), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a closure literal's tail hands back a builder's closure it captured, run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( @ ( @ v ) ) g \ → ( @ v ) { c }
    : ( @ v ) d ( g )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
