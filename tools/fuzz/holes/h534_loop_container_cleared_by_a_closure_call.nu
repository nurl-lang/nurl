// H534: agora #151 — a closure that gives a capture a new value, or changes it (loop_container_cleared_by_a_closure_call).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { ( vec_clear [String] xs ) }
    ~ x xs {
        ( h )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
