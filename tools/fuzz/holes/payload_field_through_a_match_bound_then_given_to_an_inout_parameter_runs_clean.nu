// map: §7.6 | A2 | runs-clean | - | AGORA-957 guard: a `??` arm handing on a field of a local enum payload, given to an `inout` parameter, which codegen copies
// AGORA-957 with AGORA-954's `ioc_` fact: the parameter holds its own copy
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G {
    V P
    Nil
}

@ f inout String t → v {
    : G g @ G { V @ P { ( mk ) 1 } }
    : e ?? g { V p → . p s Nil → ( mk ) }
    = t e
}

@ main → i {
    : ~ String t ( mk )
    ( f t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
