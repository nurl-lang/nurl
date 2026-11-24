// diag_parameter_payload_handed_back.nu — a function that hands back its
// option parameter's payload. As the value of a `??`, or in a generic, it
// lends the caller's option, per call, as `^ x` inside the arm does (D4c,
// AGORA-995): the result borrows the option, so reading it after the
// option is given a new value, or releasing it, is refused. Through a
// local over the parameter (`: ?String p o`) the parameter is still taken
// (agora #146), so reading the option afterwards is a use after move.

$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ by_match ? String o → String { ^ ?? o { T s → s F → ( mk ) } }

@ by_cursor ? String o → String {
    : ?String p o
    ^ ?? p { T s → s F → ( mk ) }
}

@ by_generic [A] ? A o A d → A { ^ ?? o { T s → s F → d } }

@ read_after_match → v {
    : ~ ? String o @ ?String { T ( mk ) }
    : String s ( by_match o )
    = o @ ?String { F }
    ( nurl_println ( string_data s ) )
}

@ read_after_cursor → v {
    : ?String o @ ?String { T ( mk ) }
    : String s ( by_cursor o )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ read_after_generic → v {
    : ?String o @ ?String { T ( mk ) }
    : String s ( by_generic [String] o ( mk ) )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ main → i { ^ 0 }
