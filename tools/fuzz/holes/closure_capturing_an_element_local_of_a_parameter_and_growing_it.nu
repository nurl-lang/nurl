// closure_capturing_an_element_local_of_a_parameter_and_growing_it: a local read out of a parameter, captured by a closure that grows it
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #797).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #797: a closure capturing a local read out of a parameter and growing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

@ top ( Vec ( Vec u ) ) vv → v { : ( Vec u ) e ( vec_at [( Vec u )] vv 0 ) : ( @ v ) g \ → v { ( vec_reserve [u] e 4096 ) } ( g ) }

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w a )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( top w )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
