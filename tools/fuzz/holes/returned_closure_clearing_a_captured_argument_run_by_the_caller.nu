// returned_closure_clearing_a_captured_argument_run_by_the_caller: `@ mk ( Vec String ) x → ( @ v ) { ^ \ → v { ( vec_clear x ) } }`, the caller viewing an element after `( mk xs )` and running the closure
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #656).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #656: a returned closure clearing a captured argument, run by the caller
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ mk ( Vec String ) x → ( @ v ) { ^ \ → v { ( vec_clear [String] x ) } }

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a string long enough to live on the heap for sure` ) )
    : ( @ v ) c ( mk xs )
    : s d ( string_data ( vec_at [String] xs 0 ) )
    ( c )
    ( nurl_println d )
    ^ 0
}
