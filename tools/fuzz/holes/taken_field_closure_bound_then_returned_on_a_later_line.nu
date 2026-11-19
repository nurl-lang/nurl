// taken_field_closure_bound_then_returned_on_a_later_line: AGORA-929 guard — a closure pushing to `. h buf`, made after a sink took it, bound to `g` and returned by `^ g` on a later line: refused (it holds a copy of h's handle, released when f returns)
// map: §2.1 | A2 | rejected | - | AGORA-929 guard: a closure made after the take, bound and returned on a later line
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ f → ( @ v ) {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : i n ( take . h buf )
    : ( @ v ) g \ → v { ( string_push_str . h buf `appended to the emptied field` ) }
    ^ g
}

@ main → i {
    : ( @ v ) g ( f )
    ( g )
    ^ 0
}
