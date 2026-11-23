// map: §7.6 | A2 | rejected | - | AGORA-957: a field of an inner block's enum payload through a `??`, bound by `:`, aliased, then assigned outward
// AGORA-957 (closed): refused - a `??` arm handing on a field of its payload borrows the matched binding (main 26f26b53: accepted, heap-use-after-free under ASan)
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
        : e ?? g { V p → . p s Nil → ( mk ) }
        : String u e
        = t u
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
