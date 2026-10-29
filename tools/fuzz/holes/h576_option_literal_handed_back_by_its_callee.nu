// H576: agora #171 — an aggregate literal handed straight to a callee that hands it back (option_literal_handed_back_by_its_callee).
// Closed: the literal moves into the result, or the result is copied (agora #171).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ pass ? String o → ?String { ^ o }

@ main → i {
    : ?String r ( pass @ ?String { T ( mk ) } )
    ?? r { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
