// closure_literals_closure_parameter_given_a_clearing_literal: a closure literal calling its own closure parameter, given a clearing literal inline, on a Vec whose element is still read.
// Closed: a closure picked by a join or a block, and a closure literal's own closure parameter, is the closures it may be — each arm's, and what the calls through the literal's holders pass (a node per literal parameter, with anything a call nobody sees may pass) — not any closure read by its interface (agora #420).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #420: a closure literal calling its own closure parameter, given a clearing literal inline, on a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : ( @ v ( Vec String ) ( @ v ( Vec String ) ) ) run \ ( Vec String ) y ( @ v ( Vec String ) ) g → v { ( g y ) }
    : String s0 ( vec_at [String] inner 0 )
    ( run inner \ ( Vec String ) x → v { ( vec_clear [String] x ) } )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
