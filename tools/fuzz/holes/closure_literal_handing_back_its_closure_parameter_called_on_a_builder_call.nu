// closure_literal_handing_back_its_closure_parameter_called_on_a_builder_call: `( g ( mk xs ) )`, g a literal handing back its closure parameter, the argument a builder call written in place, run beside a view of xs
// Closed (agora #838): the literal's own retclo (`lq#`) names its parameter; the closure argument's effects, of a call written in place too, pass to the result.
// main cfbd6b0e: accepted; the read after the run prints a freed buffer's bytes (96), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: a literal handing back its closure parameter, given a builder call in place, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ ( @ v ) ( @ v ) ) g \ ( @ v ) f → ( @ v ) { ^ f }
    : ( @ v ) d ( g ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
