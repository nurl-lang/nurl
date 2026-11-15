// map: §2.1 | A2 | rejected | - | agora #280: `. o a` taken by a sink, then `. . o a buf` pushed to
$ `stdlib/core/string.nu`

: Inner { String buf }
: Outer { Inner a }

@ take sink Inner x → i { ^ ( string_len . x buf ) }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( string_from `the inner string, long enough to own a heap buffer` ) } }
    : i n ( take . o a )
    ( string_push_str . . o a buf `appended to the emptied field` )
    ( nurl_println ( string_data . . o a buf ) )
    ^ 0
}
