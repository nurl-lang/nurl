// map: §7.6 | A2 | rejected | - | AGORA-957: a field of a loop body's enum payload through a `??`, bound by `:` then assigned to a binding outside the loop
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
    : ~ i k 0
    ~ < k 2 {
        : G g @ G { V @ P { ( mk ) k } }
        : e ?? g { V p → . p s Nil → ( mk ) }
        = t e
        = k + k 1
    }
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
