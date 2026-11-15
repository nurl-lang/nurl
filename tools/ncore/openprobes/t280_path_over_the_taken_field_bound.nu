// map: §2.1 | A2 | rejected | - | agora #280: `. . o a buf` taken by a sink, then `. o a` bound and its field pushed to
$ `stdlib/core/string.nu`

: Inner { String buf }
: Outer { Inner a }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( string_from `the inner string, long enough to own a heap buffer` ) } }
    : i n ( take . . o a buf )
    : ~ Inner x . o a
    ( string_push_str . x buf `appended to the emptied field` )
    ^ 0
}
