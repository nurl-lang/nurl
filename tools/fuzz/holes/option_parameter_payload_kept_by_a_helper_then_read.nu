// option_parameter_payload_kept_by_a_helper_then_read: as h422, the helper pushing the option parameter's payload.
// Closed: as h421 (agora #149).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.12 | A2 | rejected | h423 | as h422, the payload pushed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { ( Vec String ) xs i n }

@ take_any [T] sink T x → v {}

@ f ( Vec String ) out ? String o → v { ?? o { T s → { ( vec_push [String] out s ) } F → {} } }

@ main → i {
    : ( Vec String ) out ( vec_new [String] )
    : ?String o @ ?String { T ( mk ) }
    ( f out o )
    ( vec_free [String] out )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
