// generic_identity_of_a_builder_call: `( idg [( @ v )] ( mk xs ) )` run beside a view of xs
// Closed (agora #813): a generic callee instance is compiled after its caller, so its `retclo` is not there yet at the call; the result gets placeholders that the walk resolves against the instance's summary, and the run replays the builder's effects.
// main 431ca15e: accepted; the read after the run prints a freed buffer's bytes (172), and ASan reports heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #838: `( idg [( @ v )] ( mk xs ) )` run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ idg [T] T x → T { ^ x }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( idg [( @ v )] ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
