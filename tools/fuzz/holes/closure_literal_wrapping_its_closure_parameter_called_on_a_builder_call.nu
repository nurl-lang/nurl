// closure_literal_wrapping_its_closure_parameter_called_on_a_builder_call: `( g ( mk xs ) )`, g a literal handing back `\ → v { ( f ) }` over its closure parameter, the argument a builder call written in place, run beside a view of xs
// Closed (agora #838): the literal's own retclo (`lq#`) names its parameter, captured by the closure it hands back; the closure argument's effects (`__ce_by_arg`, a call's result too) pass to the result.
// main cfbd6b0e: accepted; the read after the run prints a freed buffer's bytes (233), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a literal wrapping its closure parameter, given a builder call in place, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ ( @ v ) ( @ v ) ) g \ ( @ v ) f → ( @ v ) { ^ \ → v { ( f ) } }
    : ( @ v ) d ( g ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
