// elem_across_closure_assign: agora #151 — a closure that gives a capture a new value, or changes it (elem_across_closure_assign).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h525 | agora #151: elem_across_closure_assign
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { = xs ( vec_new [String] ) }
    : String e ( vec_at [String] xs 0 )
    ( h )
    ( nurl_println ( string_data e ) )
    ^ 0
}
