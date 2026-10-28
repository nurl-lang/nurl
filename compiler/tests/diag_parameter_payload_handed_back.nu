// diag_parameter_payload_handed_back.nu — a function that hands back its
// option parameter's payload takes the parameter (agora #146): as the
// value of a `??`, through a local over the parameter, or in a generic,
// the call moves the caller's option, so reading it afterwards is a use
// after move — it held what the function gave away.

$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ by_match ? String o → String { ^ ?? o { T s → s F → ( mk ) } }

@ by_cursor ? String o → String {
    : ?String p o
    ^ ?? p { T s → s F → ( mk ) }
}

@ by_generic [A] ? A o A d → A { ^ ?? o { T s → s F → d } }

@ read_after_match → v {
    : ?String o @ ?String { T ( mk ) }
    : String s ( by_match o )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ read_after_cursor → v {
    : ?String o @ ?String { T ( mk ) }
    : String s ( by_cursor o )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ read_after_generic → v {
    : ?String o @ ?String { T ( mk ) }
    : String s ( by_generic [String] o ( mk ) )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ main → i { ^ 0 }
