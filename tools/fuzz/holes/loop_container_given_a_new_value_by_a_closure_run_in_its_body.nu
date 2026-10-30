// loop_container_given_a_new_value_by_a_closure_run_in_its_body: as h419, through a closure the body runs, which assigns its captured
// `xs`.
// Closed: a closure run in a loop body whose captured assignments or effects
// reach a loop container is rejected (agora #147).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.5 | A1 | rejected | h420 | as h419, through a closure run in the body
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { = xs ( vec_new [String] ) }
    ~ x xs {
        ( h )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
