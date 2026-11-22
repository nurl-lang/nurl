// map: §7.6 | A2 | runs-clean | - | AGORA-954 guard: a `:` join of a field viewer assigned to a binding as deep as the struct stays accepted
// AGORA-954: the struct outlives the binding the join is handed to, so nothing is refused
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : P p @ P { ( mk ) 1 }
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : String x . p s
        : y ? T x ( mk )
        = t y
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
