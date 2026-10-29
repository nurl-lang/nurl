// H535: agora #151 — a closure that gives a capture a new value, or changes it (loop_container_cleared_through_a_generic_callee).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ my_clear [T] inout ( Vec T ) v → v { ( vec_clear [T] v ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { ( my_clear [String] xs ) }
    ~ x xs {
        ( h )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
