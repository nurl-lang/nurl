// closure_pushing_a_parameter_into_a_captured_vec_then_replaced_outside: the closure pushes the parameter into a captured local Vec; the function replaces the payload through it after
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #784).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #784: a closure putting a parameter into a captured local, changed outside
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

@ ch ( Rc ( Vec u ) ) h → v { : ( Vec ( Rc ( Vec u ) ) ) xs ( vec_new [( Rc ( Vec u ) )] ) : ( @ v ) g \ → v { ( vec_push [( Rc ( Vec u ) )] xs h ) } ( g ) ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] xs 0 ) ( vec_new [u] ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
