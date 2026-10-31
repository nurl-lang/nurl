// loop_container_given_a_new_value_by_an_inline_closure: agora #151 — a closure that gives a capture a new value, or changes it (loop_container_given_a_new_value_by_an_inline_closure).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.5 | A1 | rejected | h528 | agora #151: loop_container_given_a_new_value_by_an_inline_closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    ~ x xs {
        ( run \ → v { = xs ( vec_new [String] ) } )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
