// map: §7.6 | A2 | runs-clean | - | AGORA-957 guard: a `??` arm handing on a field of an enum payload as deep as the binding it is assigned to stays accepted
// AGORA-957: the enum outlives the binding, so nothing is refused
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ main → i {
    : G g @ G { V @ P { ( mk ) 1 } }
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : e ?? g { V p → . p s Nil → ( mk ) }
        = t e
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
