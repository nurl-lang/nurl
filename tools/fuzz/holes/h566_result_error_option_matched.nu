// H566: agora #158 — a result whose payload or error is an option (result_error_option_matched).
// Closed: the result registers its twin past the inner braces (agora #158).
// v0.80.0: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ mkr → !i ? String { ^ @ !i ? String { F @ ?String { T ( mk ) } } }

@ main → i {
    : !i ? String r ( mkr )
    ?? r {
        T n → {}
        F e → { ?? e { T s → { ( nurl_println ( string_data s ) ) } F → {} } }
    }
    ^ 0
}
