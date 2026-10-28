// H427: agora #165 — a ';' defer and the value a return hands back (defer_frees_value_returned_in_literal).
// Closed: rejected by the walk's defer replay at returns (agora #165).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }
: W { String w }

@ take_any [T] sink T x → v {}

@ f → W {
    : String s ( mk )
    ; { ( string_free s ) }
    ^ @ W { s }
}

@ main → i {
    : W w ( f )
    ( nurl_println ( string_data . w w ) )
    ^ 0
}
