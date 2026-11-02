// closure_given_a_clearing_body_later_in_a_loop: a closure binding given a clearing closure after its call, in a loop.
// Closed: a closure literal is summarised from its own body as a function is (what it changes, moves or drops of its parameters, and the views it leaves between them), under its emitted name; a call through a binding that holds it is a call of the binding's summary node — the union of every literal and node bound to it — and a closure parameter's node is the union of what every caller passes there (agora #359, #403).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #359: a closure binding given a clearing closure after its call, in a loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : ~ ( @ v ( Vec String ) ) f \ ( Vec String ) x → v {}
    : String s0 ( vec_at [String] inner 0 )
    : ~ i k 0
    ~ < k 2 {
        ( f inner )
        = f \ ( Vec String ) x → v { ( vec_clear [String] x ) }
        = k + k 1
    }
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
