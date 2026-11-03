// closure_clears_its_parameter_through_a_nested_closure: a closure literal whose nested closure clears the outer literal's parameter, called with a Vec whose element is still read.
// Closed: what a nested closure does to a capture that is a parameter of the literal it runs in is a drop of that literal's summary, as the call written inline would be (agora #435).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #435: a closure literal whose nested closure clears the outer literal's parameter, called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ( @ v ( Vec String ) ) f \ ( Vec String ) x → v {
        : ( @ v ) g \ → v { ( vec_clear [String] x ) }
        ( g )
    }
    : String e ( vec_at [String] v 0 )
    ( f v )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
