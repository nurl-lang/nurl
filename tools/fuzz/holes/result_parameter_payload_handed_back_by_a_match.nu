// result_parameter_payload_handed_back_by_a_match: as h408, a result (`!String s`) parameter's `T` payload.
// Closed: as h408 (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | rejected | h412 | as h408, a result parameter
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ take_any [T] sink T x → v {}

@ f ! String s r → String { ^ ?? r { T v → v F e → ( mk ) } }

@ main → i {
    : !String s r @ !String s { T ( mk ) }
    : String x ( f r )
    ( string_free x )
    ?? r { T y → { ( nurl_println ( string_data y ) ) } F e → {} }
    ^ 0
}
