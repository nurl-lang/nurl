// closure_capturing_by_reference_re_pointed_at_a_parameter_before_it_runs: a closure assigning `e` (so captured by reference) and growing it; `= e x` with x a parameter, then `( c F )`
// Closed: a closure a function hands back carries its effects on the arguments it captured to the caller's binding — through a field-path or lending argument, a join or a block, an `=`, and a by-reference capture re-pointed before it runs (agora #802).
// main b73574d9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #802: a by-reference capture re-pointed at a parameter before the closure runs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ w ( Vec u ) x → v {
    : ~ ( Vec u ) e ( vec_new [u] )
    : ( @ v b ) c \ b k → v { ( vec_reserve [u] e 4096 ) ? k { = e ( vec_new [u] ) } {} }
    = e x
    ( c F )
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( w xs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
