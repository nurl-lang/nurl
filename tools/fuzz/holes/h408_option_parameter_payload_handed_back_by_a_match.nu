// H408: a function handed back its option parameter's payload as the value
// of a `??` (`^ ?? o { T s → s F → ( mk ) }`): it took the payload over
// (kept the parameter), but its caller's option was not moved, and the
// caller read the payload it had freed.
// Closed: a parameter whose value a function moves on through a cursor over
// it — handed back, put in a literal, given to a `sink` — is an inferred
// `sink` (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f ? String o → String { ^ ?? o { T s → s F → ( mk ) } }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( f o )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
