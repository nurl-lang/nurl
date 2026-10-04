// borrow_closure_stored_capture_freed.nu — a closure stored into a struct
// keeps reading what it captured. Freeing a capture and then invoking the
// closure is caught while the closure is reachable by its name (§2.11);
// through a struct field it was not, and ran on freed memory. The captures
// of a closure stored into an aggregate are stored into that aggregate
// for the borrow checker now (docs/MEMORY.md §2.12): reading them is fine,
// releasing one while the owner may still invoke the closure is the error.

$ `stdlib/core/vec.nu`

: Box { ( @ i ) f }

// In a struct literal.
@ literal → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 41 )
    : Box b @ Box { \ → i { ^ ( vec_len [i] a ) } }
    ( nurl_println_int ( vec_len [i] a ) )
    ( vec_free [i] a )
    : ( @ i ) g . b f
    ^ ( g )
}

// Through a field assignment.
@ field_store → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 41 )
    : ~ Box b @ Box { \ → i { ^ 0 } }
    = . b f \ → i { ^ ( vec_len [i] a ) }
    ( vec_free [i] a )
    : ( @ i ) g . b f
    ^ ( g )
}

@ main → i {
    ^ + ( literal ) ( field_store )
}
