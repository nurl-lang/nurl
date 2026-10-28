// diag_returned_closure_outlives_argument.nu — a closure a function
// returns over its parameter, kept by the caller past the argument's
// release (agora #141). Each spelling of the callee — bound first,
// joined, given a new value, over a view — is a view of the argument, so
// running the closure after the release is rejected.

$ `stdlib/core/string.nu`

@ bound String s → ( @ v ) {
    : ( @ v ) c \ → v { ( nurl_println ( string_data s ) ) }
    ^ c
}

@ joined String s → ( @ v ) {
    : ( @ v ) c \ → v { ( nurl_println ( string_data s ) ) }
    ^ ? > ( string_len s ) 3 c c
}

@ reassigned String s → ( @ v ) {
    : ~ ( @ v ) c \ → v { ( nurl_println `none` ) }
    = c \ → v { ( nurl_println ( string_data s ) ) }
    ^ c
}

@ over_view String s → ( @ v ) {
    : s v ( string_data s )
    ^ \ → v { ( nurl_println v ) }
}

@ use_bound → v {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( bound t )
    ( string_free t )
    ( g )
}

@ use_joined → v {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( joined t )
    ( string_free t )
    ( g )
}

@ use_reassigned → v {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( reassigned t )
    ( string_free t )
    ( g )
}

@ use_view → v {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( over_view t )
    ( string_free t )
    ( g )
}

@ main → i {
    ( use_bound ) ( use_joined ) ( use_reassigned ) ( use_view )
    ^ 0
}
