// returned_closure_over_a_field_path_argument_run_by_the_caller: `( mk . w xs )` handing back a closure that reserves its capture, run after the caller took a slice of `. w xs`
// Closed: a closure a function hands back carries its effects on the arguments it captured to the caller's binding — through a field-path or lending argument, a join or a block, an `=`, and a by-reference capture re-pointed before it runs (agora #802).
// main b73574d9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #802: a returned closure over a field-path argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

: W { ( Vec u ) xs i n }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : W w @ W { xs 1 }
    : ( @ v ) c ( mk . w xs )
    : ( Slice u ) sl ( slice_from_vec [u] . w xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
