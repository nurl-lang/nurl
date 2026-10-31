// view_across_closure_nested_field_assign: agora #151 — a closure that gives a capture a new value, or changes it (view_across_closure_nested_field_assign).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h538 | agora #151: view_across_closure_nested_field_assign
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

: W { R r i pad }

@ main → i {
    : ~ W w @ W { @ R { ( mk ) 0 } 0 }
    : ( @ v ) h \ → v { = . . w r s ( string_new ) }
    : s v ( string_data . . w r s )
    ( h )
    ( nurl_println v )
    ^ 0
}
