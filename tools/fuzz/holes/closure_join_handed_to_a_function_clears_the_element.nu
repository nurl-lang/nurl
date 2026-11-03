// closure_join_handed_to_a_function_clears_the_element: a join of a clearing and a no-op closure handed to a function that calls it on a Vec whose element is still read.
// Closed: a closure picked by a join or a block, and a closure literal's own closure parameter, is the closures it may be — each arm's, and what the calls through the literal's holders pass (a node per literal parameter, with anything a call nobody sees may pass) — not any closure read by its interface (agora #420).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #420: a join of a clearing and a no-op closure handed to a function that calls it on a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ apply ( Vec String ) v ( @ v ( Vec String ) ) f → v { ( f v ) }

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : b c > ( vec_len [String] inner ) 0
    : ( @ v ( Vec String ) ) clr \ ( Vec String ) x → v { ( vec_clear [String] x ) }
    : ( @ v ( Vec String ) ) nop \ ( Vec String ) x → v {}
    : String s0 ( vec_at [String] inner 0 )
    ( apply inner ? c clr nop )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
