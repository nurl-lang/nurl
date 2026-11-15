// map: §2.1 | A2 | rejected | - | agora #280: `^ { h }` after a sink took `. h buf`
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ f → Holder {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : i n ( take . h buf )
    ^ { h }
}

@ main → i {
    : ~ Holder g ( f )
    ( string_push_str . g buf `appended to the emptied field` )
    ( nurl_println ( string_data . g buf ) )
    ^ 0
}
