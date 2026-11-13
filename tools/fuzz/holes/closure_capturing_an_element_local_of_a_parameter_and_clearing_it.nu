// closure_capturing_an_element_local_of_a_parameter_and_clearing_it: `: m ( vec_at vv 0 )` captured by a closure that clears it, run in the function
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #784).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #784: a closure capturing a local read out of a parameter and clearing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

@ top ( Vec ( Vec String ) ) vv → v { : ( Vec String ) m ( vec_at [( Vec String )] vv 0 ) : ( @ v ) g \ → v { ( vec_clear [String] m ) } ( g ) }

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to live on the heap for sure` ) )
    ( vec_push [( Vec String )] w v )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] w 0 ) 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}
