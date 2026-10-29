// H583: agora #171 — an aggregate literal handed straight to a callee that hands it back (struct_literal_handed_back_and_read_unbound).
// Closed: the literal moves into the result, or the result is copied (agora #171).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

: P { String s i n }

@ pass P p → P { ^ p }

@ main → i {
    ( nurl_println ( string_data . ( pass @ P { ( mk ) 0 } ) s ) )
    ^ 0
}
