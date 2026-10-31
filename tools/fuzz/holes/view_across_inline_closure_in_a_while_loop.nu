// view_across_inline_closure_in_a_while_loop: agora #151 — a closure that gives a capture a new value, or changes it (view_across_inline_closure_in_a_while_loop).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h541 | agora #151: view_across_inline_closure_in_a_while_loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ String x ( mk )
    : s v ( string_data x )
    : ~ i k 0
    ~ < k 1 {
        ( run \ → v { = x ( string_new ) } )
        = k + k 1
    }
    ( nurl_println v )
    ^ 0
}
