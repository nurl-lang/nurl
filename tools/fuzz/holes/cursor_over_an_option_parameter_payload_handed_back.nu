// cursor_over_an_option_parameter_payload_handed_back: as h408, through a local over the parameter (`: ?String p o`, then
// `?? p { T s → s … }`).
// Closed: as h408 (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | rejected | h414 | as h408, through a cursor over the parameter
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f ? String o → String { : ?String p o ^ ?? p { T s → s F → ( mk ) } }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( f o )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
