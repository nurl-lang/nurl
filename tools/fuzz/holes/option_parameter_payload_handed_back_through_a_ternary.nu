// option_parameter_payload_handed_back_through_a_ternary: as h408, the `??` an arm of a `?` the function hands back.
// Closed: as h408 (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// Since AGORA-995 (D4c) the payload is lent back, per call, as `^ x` inside the arm is: the caller keeps its option, and releasing the result is refused as a borrow released ("'s' is a borrow … released or handed over").
// map: §7.6 | A2 | rejected | h411 | as h408, through a ternary
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f ? String o b c → String { ^ ? c ?? o { T s → s F → ( mk ) } ( mk ) }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( f o T )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
