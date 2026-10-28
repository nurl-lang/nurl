// H385: a closure returned over a local view of a String parameter (`: s v ( string_data s ) ^ \ → v { … v … }`) outlived the caller's argument: the `retclo` summary recorded captures that are parameters, not a capture that views one.
// Closed: as h384 — a captured view's row says what it was made from (agora #141).
// v0.79.1: accepted; AddressSanitizer reported heap-use-after-free in nurl_println.
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
