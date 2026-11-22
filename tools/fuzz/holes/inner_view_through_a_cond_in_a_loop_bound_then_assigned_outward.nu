// map: §7.6 | A2 | rejected | - | AGORA-954: a view of an inner block's struct field through a `?` in a loop body, bound by `:` then assigned to a binding outside the loop
// AGORA-954 (closed): refused (main 3f08626b: accepted, heap-use-after-free under ASan)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : ~ i k 0
    ~ < k 2 {
        : P p @ P { ( mk ) k }
        : String x . p s
        : y ? == k 1 x ( mk )
        = t y
        = k + k 1
    }
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
