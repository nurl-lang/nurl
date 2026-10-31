// defer_frees_returned_value: agora #165 — a ';' defer and the value a return hands back (defer_frees_returned_value).
// Closed: rejected by the walk's defer replay at returns (agora #165).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §7.2 | A2 | rejected | h426 | agora #165: defer_frees_returned_value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ f → String {
    : String s ( mk )
    ; { ( string_free s ) }
    ^ s
}

@ main → i {
    : String r ( f )
    ( nurl_println ( string_data r ) )
    ^ 0
}
