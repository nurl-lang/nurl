// taken_field_closure_pushing_another_capture_first_then_the_taken_field_returned: AGORA-929 — a closure with effects on two captures, `. h buf` (taken by a sink) and a Vec `w`, returned on the line it is made on (github#2097's review: one `clox` row per capture, either order)
// AGORA-929 (this shape, closed): refused
// map: §2.1 | A2 | rejected | - | AGORA-929: a returned closure pushing to a taken field and to another capture
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ f → ( @ v ) {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : ~ ( Vec i ) w ( vec_new [i] )
    : i n ( take . h buf )
    ^ \ → v { ( vec_push [i] w 1 ) ( string_push_str . h buf `appended to the emptied field` ) }
}

@ main → i {
    : ( @ v ) g ( f )
    ( g )
    ^ 0
}
