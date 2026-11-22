// map: §7.6 | A2 | rejected | - | AGORA-954: a view of a view of an inner block's struct field through a `?`, bound by `:` then assigned outward
// AGORA-954 (closed): refused - a viewer of a field viewer is one too (main 3f08626b: accepted, heap-use-after-free under ASan)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        : String x2 x
        : y ? T x2 ( mk )
        = t y
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
