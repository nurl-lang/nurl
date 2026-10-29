// H567: agora #158 — a result whose payload or error is an option (result_of_an_option_copied_then_matched).
// Closed: the result registers its twin past the inner braces (agora #158).
// v0.80.0: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : !?String i r @ !?String i { T @ ?String { T ( mk ) } }
    : !?String i r2 r
    ?? r { T o → { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} } } F e → {} }
    ^ 0
}
