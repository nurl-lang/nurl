// H539: agora #151 — a closure that gives a capture a new value, or changes it (view_across_vec_each_closure_assign).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ String x ( mk )
    : s v ( string_data x )
    : ( Vec i ) nums ( vec_new [i] )
    ( vec_push [i] nums 1 )
    ( vec_each [i] nums \ i n → v { = x ( string_new ) } )
    ( nurl_println v )
    ^ 0
}
