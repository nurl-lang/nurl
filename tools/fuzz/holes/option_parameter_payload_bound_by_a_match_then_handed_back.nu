// option_parameter_payload_bound_by_a_match_then_handed_back: as h408, the `??` value bound to a local first (`: String r ?? o {…}
// ^ r`).
// Closed: as h408 (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// Since AGORA-995 (D4c) the payload is lent back, per call, as `^ x` inside the arm is: the caller keeps its option, and releasing the result is refused as a borrow released ("'s' is a borrow … released or handed over").
// map: §7.6 | A2 | rejected | h409 | as h408, bound first
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f ? String o → String {
    : String r ?? o { T s → s F → ( mk ) }
    ^ r
}

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( f o )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
