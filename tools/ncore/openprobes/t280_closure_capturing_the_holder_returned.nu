// map: §2.1 | A2 | rejected | - | agora #280: a closure capturing `h` returned after a sink took `. h buf`
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ f → ( @ v ) {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : i n ( take . h buf )
    ^ \ → v { ( string_push_str . h buf `appended to the emptied field` ) }
}

@ main → i {
    : ( @ v ) g ( f )
    ( g )
    ^ 0
}
