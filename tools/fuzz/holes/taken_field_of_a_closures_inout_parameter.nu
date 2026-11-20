// map: §2.1 | A2 | rejected | - | AGORA-929: a closure's own `inout` parameter has its field taken by a sink and is left empty
// AGORA-929 (this shape, closed): refused - a closure's inout parameter goes back to its caller at each exit, like a function's (main 08e56f54: accepted, a null handle)
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
