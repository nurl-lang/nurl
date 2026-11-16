// map: §2.1 | A2 | rejected | - | agora #280: `( grow { h } )` after a sink took `. h buf`
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ grow Holder x → v { ( string_push_str . x buf `appended to the emptied field` ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : i n ( take . h buf )
    ( grow { h } )
    ^ 0
}
