// returned_closure_over_an_rc_field_argument_run_by_the_caller: `( mk . p a )` of an Rc field, the closure replacing the payload, a view through another handle
// Closed: a closure a function hands back carries its effects on the arguments it captured to the caller's binding — through a field-path or lending argument, a join or a block, an `=`, and a by-reference capture re-pointed before it runs (agora #802).
// main b73574d9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #802: a returned closure over an Rc field argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

: P { ( Rc ( Vec u ) ) a i n }

@ mk ( Rc ( Vec u ) ) h → ( @ v ) { ^ \ → v { ( rc_set [( Vec u )] h ( vec_new [u] ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : P p @ P { r 1 }
    : ( @ v ) c ( mk . p a )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
