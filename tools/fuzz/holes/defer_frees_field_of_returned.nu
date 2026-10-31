// defer_frees_field_of_returned: agora #165 — a ';' defer and the value a return hands back (defer_frees_field_of_returned).
// Closed: rejected by the walk's defer replay at returns (agora #165).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §7.2 | A2 | rejected | h428 | agora #165: defer_frees_field_of_returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }
: W { String w }

@ take_any [T] sink T x → v {}

@ f → Q {
    : Q q @ Q { ( mk ) ( mk ) }
    ; { ( string_free . q name ) }
    ^ q
}

@ main → i {
    : Q q ( f )
    ( nurl_println ( string_data . q name ) )
    ^ 0
}
