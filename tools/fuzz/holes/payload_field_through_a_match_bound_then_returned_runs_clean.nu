// map: §7.6 | A2 | runs-clean | - | AGORA-957 guard: a `??` arm handing on a field of a local enum payload, bound by `:` then returned, is copied and runs clean
// AGORA-957: `^` copies what is lent out of a local
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ f → String {
    : G g @ G { V @ P { ( mk ) 1 } }
    : e ?? g { V p → . p s Nil → ( mk ) }
    ^ e
}

@ main → i {
    : String t ( f )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
