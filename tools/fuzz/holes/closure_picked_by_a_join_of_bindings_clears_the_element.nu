// closure_picked_by_a_join_of_bindings_clears_the_element: a closure picked by a join of two bindings (`? c clr nop`), one clearing, called with a Vec whose element is still read.
// Closed: a closure picked by a join or a block, and a closure literal's own closure parameter, is the closures it may be — each arm's, and what the calls through the literal's holders pass (a node per literal parameter, with anything a call nobody sees may pass) — not any closure read by its interface (agora #420).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #420: a closure picked by a join of two bindings (`? c clr nop`), one clearing, called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : b c > ( vec_len [String] inner ) 0
    : ( @ v ( Vec String ) ) clr \ ( Vec String ) x → v { ( vec_clear [String] x ) }
    : ( @ v ( Vec String ) ) nop \ ( Vec String ) x → v {}
    : ( @ v ( Vec String ) ) f ? c clr nop
    : String s0 ( vec_at [String] inner 0 )
    ( f inner )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
