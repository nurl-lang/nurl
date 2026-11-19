// map: §2.1 | A2 | rejected | - | AGORA-929: a closure capturing `h` returned after a sink took `. h buf`
// AGORA-929 (this shape, closed; AGORA-280's rest): refused (main 85a31ca6: accepted, a null handle)
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
