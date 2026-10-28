// H524: agora #151 — a closure that gives a capture a new value, or changes it (view_across_closure_field_assign).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ R r @ R { ( mk ) 0 }
    : ( @ v ) h \ → v { = . r s ( string_new ) }
    : s v ( string_data . r s )
    ( h )
    ( nurl_println v )
    ^ 0
}
