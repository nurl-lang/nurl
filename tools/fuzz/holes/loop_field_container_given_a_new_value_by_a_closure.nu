// loop_field_container_given_a_new_value_by_a_closure: agora #151 — a closure that gives a capture a new value, or changes it (loop_field_container_given_a_new_value_by_a_closure).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.5 | A1 | rejected | h527 | agora #151: loop_field_container_given_a_new_value_by_a_closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ RV r @ RV { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    : ( @ v ) h \ → v { = . r xs ( vec_new [String] ) }
    ~ x . r xs {
        ( h )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
