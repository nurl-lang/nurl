// struct_literal_handed_back_by_a_generic: agora #171 — an aggregate literal handed straight to a callee that hands it back (struct_literal_handed_back_by_a_generic).
// Closed: the literal moves into the result, or the result is copied (agora #171).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: CallT.summary | A1 | runs-clean | h581 | agora #171: struct_literal_handed_back_by_a_generic
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

: P { String s i n }

@ id [T] T x → T { ^ x }

@ main → i {
    : P r ( id [P] @ P { ( mk ) 0 } )
    ( nurl_println ( string_data . r s ) )
    ^ 0
}
