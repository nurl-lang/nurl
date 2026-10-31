// loop_container_closure_handed_to_a_later_helper: agora #151 — a closure that gives a capture a new value, or changes it (loop_container_closure_handed_to_a_later_helper).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.5 | A1 | rejected | h529 | agora #151: loop_container_closure_handed_to_a_later_helper
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { = xs ( vec_new [String] ) }
    ~ x xs {
        ( run_after h )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}

@ run_after ( @ v ) f → v { ( f ) }
