// closure_capturing_by_reference_re_pointed_at_an_element_before_it_runs: the same with `= e ( vec_at vv 0 )`
// Closed: a closure a function hands back carries its effects on the arguments it captured to the caller's binding — through a field-path or lending argument, a join or a block, an `=`, and a by-reference capture re-pointed before it runs (agora #802).
// main b73574d9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #802: a by-reference capture re-pointed at a parameter's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ w ( Vec ( Vec u ) ) vv → v {
    : ~ ( Vec u ) e ( vec_new [u] )
    : ( @ v b ) c \ b k → v { ( vec_reserve [u] e 4096 ) ? k { = e ( vec_new [u] ) } {} }
    = e ( vec_at [( Vec u )] vv 0 )
    ( c F )
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( w vv )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
