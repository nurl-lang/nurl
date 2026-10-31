// closure_bindings_joined_then_returned_over_a_parameter: a closure returned through a join of two closure bindings (`^ ? cond c c`), each over a String parameter, outlived the caller's argument.
// Closed: as h384 (agora #141).
// v0.79.1: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h388 | as h384, a join of closure bindings
$ `stdlib/core/string.nu`

@ mk String s → ( @ v ) { : ( @ v ) c \ → v { ( nurl_println ( string_data s ) ) } ^ ? > ( string_len s ) 3 c c }

@ main → i {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( mk t )
    ( string_free t )
    ( g )
    ^ 0
}
