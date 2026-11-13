// closure_calling_a_named_grower_on_a_captured_parameter: `: c \ → v { ( grow x ) } ( c )` with a named `grow` that reserves
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #656).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #656: a closure calling a named grower on a captured parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow ( Vec u ) x → v { ( vec_reserve [u] x 4096 ) }

@ w ( Vec u ) x → v {
    : ( @ v ) c \ → v { ( grow x ) }
    ( c )
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( w xs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
