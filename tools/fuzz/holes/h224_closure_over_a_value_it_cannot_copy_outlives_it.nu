// H224: a closure capturing by value a value that cannot be copied (a `% Drop` value with no clone) holds a copy of its bits while the binding keeps owning what they point at. Handed back — `^ f`, or in a struct literal returned — it outlived the binding, which was released on the way out: the caller's call read freed memory.
// Closed: such a closure is a view of the binding (its source expression holds it), so the borrow walk ends it with the binding — handing it back, directly or inside a value, is rejected; in its own frame it stays usable.
// main (before this PR): ASan heap-use-after-free.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mk → ( @ i ) {
    : Res r @ Res { ( vec_new [i] ) }
    ( vec_push [i] . r buf 5 )
    : ( @ i ) f \ → i { ( vec_len [i] . r buf ) }
    ^ f
}

@ main → i {
    : ( @ i ) g ( mk )
    ( nurl_println_int ( g ) )
    ^ 0
}
