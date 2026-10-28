// OPEN in v0.79.1 — a closure returned over a local view of a String parameter (`: s v ( string_data s ) ^ \ → v { … v … }`): the callee's `retclo` summary records captures that are parameters, not a capture that views one, so the caller frees its argument and the closure reads freed memory. ASan: heap-use-after-free (agora #141).
$ `stdlib/core/string.nu`

@ mk2 String s → ( @ v ) {
    : s v ( string_data s )
    ^ \ → v { ( nurl_println v ) }
}

@ main → i {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( mk2 t )
    ( string_free t )
    ( g )
    ^ 0
}
