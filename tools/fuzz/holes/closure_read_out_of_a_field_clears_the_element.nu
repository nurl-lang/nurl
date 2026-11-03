// closure_read_out_of_a_field_clears_the_element: a clearing closure literal stored in a struct field, read out of it into a binding and called with a Vec whose element is still read.
// Closed: a call through a closure nobody follows (read out of a field, an element, a call's result) may run any closure literal of its type the program builds, as well as what its interface allows (agora #418).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #418: a clearing closure literal stored in a struct field, read out of it into a binding and called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( @ v ( Vec String ) ) f }

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : H h @ H { \ ( Vec String ) x → v { ( vec_clear [String] x ) } }
    : ( @ v ( Vec String ) ) g . h f
    : String s0 ( vec_at [String] inner 0 )
    ( g inner )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
