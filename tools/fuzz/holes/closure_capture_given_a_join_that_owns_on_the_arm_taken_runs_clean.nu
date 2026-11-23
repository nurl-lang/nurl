// map: §7.5 | A2 | runs-clean | - | AGORA-955: a closure's by-name capture given a `:` join that owns its value on the arm taken
// AGORA-955 (closed by github#2189, AGORA-953): runs clean - the guard: where the join owns, the value moves into the capture, no copy and no leak
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : g \ → v {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        : y ? F x ( mk )
        = t y
    }
    ( g )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
