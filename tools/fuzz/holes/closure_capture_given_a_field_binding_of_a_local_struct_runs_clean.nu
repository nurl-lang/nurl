// map: §7.5 | A2 | runs-clean | - | AGORA-955: a closure's by-name capture given a field binding of a struct the closure made
// AGORA-955 (closed by github#2189, AGORA-953): runs clean - the guard: codegen takes or copies the field here, as it did before
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : g \ → v {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        = t x
    }
    ( g )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
