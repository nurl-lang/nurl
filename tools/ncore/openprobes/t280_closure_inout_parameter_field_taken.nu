// map: §2.1 | A2 | rejected | - | agora #280: a closure's own `inout` parameter has its field taken by a sink and is left empty
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : ( @ v inout Holder ) g \ inout Holder x → v { : i n ( take . x buf ) }
    ( g h )
    ( string_push_str . h buf `appended to the emptied field` )
    ( nurl_println ( string_data . h buf ) )
    ^ 0
}
