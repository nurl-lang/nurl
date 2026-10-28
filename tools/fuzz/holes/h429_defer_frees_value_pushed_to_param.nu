// H429: agora #165 — a ';' defer and the value a return hands back (defer_frees_value_pushed_to_param).
// Closed: rejected by the walk's defer replay at returns (agora #165).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }
: W { String w }

@ take_any [T] sink T x → v {}

@ f ( Vec String ) out → v {
    : String s ( mk )
    ; { ( string_free s ) }
    ( vec_push [String] out s )
}

@ main → i {
    : ( Vec String ) out ( vec_new [String] )
    ( f out )
    ( nurl_println ( string_data ( vec_at [String] out 0 ) ) )
    ( vec_free [String] out )
    ^ 0
}
