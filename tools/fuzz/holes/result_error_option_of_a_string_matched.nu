// result_error_option_of_a_string_matched: agora #158 — a result whose payload or error is an option (result_error_option_of_a_string_matched).
// Closed: the result registers its twin past the inner braces (agora #158).
// v0.80.0: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h569 | agora #158: result_error_option_of_a_string_matched
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ mkr → !String ? String { ^ @ !String ? String { F @ ?String { T ( mk ) } } }

@ main → i {
    : !String ? String r ( mkr )
    ?? r { T s → {} F e → { ?? e { T x → { ( nurl_println ( string_data x ) ) } F → {} } } }
    ^ 0
}
