// generic_option_parameter_payload_handed_back: as h408, in a generic function (`@ f [A] ?A o A d → A`) instantiated
// at `String`.
// Closed: as h408 (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// Since AGORA-995 (D4c) the payload is lent back, per call, as `^ x` inside the arm is: the caller keeps its option, and releasing the result is refused as a borrow released ("'s' is a borrow … released or handed over").
// map: §7.6 | A2 | rejected | h415 | as h408, a generic instance
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f [A] ? A o A d → A { ^ ?? o { T s → s F → d } }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( f [String] o ( mk ) )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
