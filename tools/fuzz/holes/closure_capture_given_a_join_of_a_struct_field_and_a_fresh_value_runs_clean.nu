// map: §7.5 | A2 | runs-clean | - | AGORA-955: a closure's by-name capture given a `:` join of a struct field (AGORA-941's form) and a fresh value
// AGORA-955 (closed by github#2189, AGORA-953): runs clean - where the join lends the field, the store into the by-pointer capture copies it (main 26f26b53: heap-use-after-free under ASan)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : g \ → v {
        : P p @ P { ( mk ) 1 }
        : y ? T . p s ( mk )
        = t y
    }
    ( g )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
