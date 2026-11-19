// map: §2.1 | A2 | rejected | - | AGORA-929: `^ @ Outer { h }` after a sink took `. h buf`
// AGORA-929 (this shape, closed; AGORA-280's rest; github#2097's review: the literal over two lines): refused (main 85a31ca6: accepted, a null handle or freed memory)
$ `stdlib/core/string.nu`

: Holder { String buf }
: Outer { Holder h }

@ take sink String v → i { ^ ( string_len v ) }

@ f → Outer {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : i n ( take . h buf )
    ^ @ Outer {
        h
    }
}

@ main → i {
    : ~ Outer o ( f )
    ( string_push_str . . o h buf `appended to the emptied field` )
    ( nurl_println ( string_data . . o h buf ) )
    ^ 0
}
