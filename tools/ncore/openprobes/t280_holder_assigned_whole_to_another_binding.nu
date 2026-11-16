// map: §2.1 | A2 | rejected | - | agora #280: `= h2 h` after a sink took `. h buf`, then `. h2 buf` pushed to
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : ~ Holder h2 @ Holder { ( string_from `the second holder's string, long enough for the heap too` ) }
    : i n ( take . h buf )
    = h2 h
    ( string_push_str . h2 buf `appended to the emptied field` )
    ( nurl_println ( string_data . h2 buf ) )
    ^ 0
}
