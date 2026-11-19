// map: §2.1 | A2 | rejected | - | AGORA-929: `. . o a buf` taken by a sink, then `. o a` handed to a grower
// AGORA-929 (this shape, closed; AGORA-280's rest): refused (main 85a31ca6: accepted, a null handle or freed memory)
$ `stdlib/core/string.nu`

: Inner { String buf }
: Outer { Inner a }

@ take sink String v → i { ^ ( string_len v ) }

@ grow Inner x → v { ( string_push_str . x buf `appended to the emptied field` ) }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( string_from `the inner string, long enough to own a heap buffer` ) } }
    : i n ( take . . o a buf )
    ( grow . o a )
    ^ 0
}
