// defer_frees_early_returned: agora #165 — a ';' defer and the value a return hands back (defer_frees_early_returned).
// Closed: rejected by the walk's defer replay at returns (agora #165).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §7.2 | A2 | rejected | h434 | agora #165: defer_frees_early_returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ f b c → String {
    : String s ( mk )
    ; { ( string_free s ) }
    ? c { ^ s } {}
    ^ ( mk )
}

@ main → i {
    : String r ( f T )
    ( nurl_println ( string_data r ) )
    ^ 0
}
