// map: §2.1 | A2 | rejected | - | AGORA-929: `= h2 h` after a sink took `. h buf`, then `. h2 buf` pushed to
// AGORA-929 (this shape, closed; AGORA-280's rest): refused (main 85a31ca6: accepted, a null handle or freed memory)
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
