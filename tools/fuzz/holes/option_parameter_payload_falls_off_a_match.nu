// option_parameter_payload_falls_off_a_match: as h408, the `??` the function's last expression (no `^`).
// Closed: as h408 (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | rejected | h410 | as h408, falling off the end
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f ? String o → String { ?? o { T s → s F → ( mk ) } }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( f o )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
