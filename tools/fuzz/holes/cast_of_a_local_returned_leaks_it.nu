// cast_of_a_local_returned_leaks_it: agora #545 — `^ # T a`, a cast of a local to the type it already has: the return took it for a read through a cast, lent by nobody, so the local's flag stayed set for nobody and its value leaked.
// Closed: a cast of a binding to its own type returns the binding itself: `^ # T a` is `^ a` — a local handed over, a parameter copied for the caller.
// main (before this PR): LeakSanitizer, the String and the struct's String.
// map: §7.6 | A2 | runs-clean | - | agora #545: a local returned through a cast to its own type (`^ # T a`) leaked
$ `stdlib/core/string.nu`

: P { String name i n }

@ get_slice → [i { : [i a [i | 1 2 3] ^ # [i a }
@ get_string → String { : String a ( string_from `a long enough string to be on the heap, one` ) ^ # String a }
@ get_struct → P { : P a @ P { ( string_from `a long enough string to be on the heap, two!` ) 1 } ^ # P a }
@ of_param String a → String { ^ # String a }

@ main → i {
    : [i w ( get_slice )
    ~ x w { ( nurl_println ( nurl_str_int x ) ) }
    : String t ( get_string )
    ( nurl_println ( string_data t ) )
    : P u ( get_struct )
    ( nurl_println ( string_data . u name ) )
    ( get_string )
    : String w3 ( of_param t )
    ( nurl_println ( string_data w3 ) )
    ( nurl_println ( string_data t ) )
    ^ 0
}
