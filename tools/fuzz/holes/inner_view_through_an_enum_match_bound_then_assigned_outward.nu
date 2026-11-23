// map: §7.6 | A2 | rejected | - | AGORA-954: a view of an inner block's struct field as an enum `??` arm, bound by `:` then assigned outward
// AGORA-954 (closed): refused (main 3f08626b: accepted, heap-use-after-free under ASan)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : G g @ G { V @ P { ( mk ) 1 } }
        : P p @ P { ( mk ) 2 }
        : String x . p s
        : y ?? g { V q → x Nil → ( mk ) }
        = t y
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
