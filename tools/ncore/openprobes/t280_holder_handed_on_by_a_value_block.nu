// map: §2.1 | A2 | rejected | - | agora #280: `: ~ Holder g { h }` after a sink took `. h buf`, then `. g buf` pushed to
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : i n ( take . h buf )
    : ~ Holder g { h }
    ( string_push_str . g buf `appended to the emptied field` )
    ^ 0
}
