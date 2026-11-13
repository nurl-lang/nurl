// closure_parameter_copy_captured_by_an_inner_closure_that_replaces: a closure literal copying its parameter, `: t x`, captured by an inner closure that replaces the payload, run there
// Closed: what a closure body does to a capture or to its own parameter reaches the enclosing function's or the literal's summary — mutation, drop, irealloc — and a closure a call hands back carries its effects to the caller's binding (agora #784).
// main 820aafb4: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #784: an inner closure replacing what a copy of the outer literal's parameter holds
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ v ( Rc ( Vec u ) ) ) f \ ( Rc ( Vec u ) ) x → v { : ( Rc ( Vec u ) ) t x : ( @ v ) g \ → v { ( rc_set [( Vec u )] t ( vec_new [u] ) ) } ( g ) }
    ( f r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
