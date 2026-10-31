// defer_in_loop_frees_returned: agora #165 — a ';' defer and the value a return hands back (defer_in_loop_frees_returned).
// Closed: rejected by the walk's defer replay at returns (agora #165).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §7.2 | A2 | rejected | h433 | agora #165: defer_in_loop_frees_returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ f → String {
    : String s ( mk )
    : ~ i k 0
    ~ < k 1 { ; { ( string_free s ) } = k + k 1 }
    ^ s
}

@ main → i {
    : String r ( f )
    ( nurl_println ( string_data r ) )
    ^ 0
}
