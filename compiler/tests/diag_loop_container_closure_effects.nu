// diag_loop_container_closure_effects.nu — a closure that changes a `~`
// loop's container when it runs, run in the loop's body (agora #151): it
// gives a field the loop iterates a new value, it is a literal handed to
// a helper, it is handed to a helper defined further down, it runs
// another closure that does, or it clears the container through a
// generic callee. The loop's cursor walks freed memory after each.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ a_field_given_a_new_value → v {
    : ~ RV r @ RV { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    : ( @ v ) h \ → v { = . r xs ( vec_new [String] ) }
    ~ x . r xs { ( h ) }
}

@ an_inline_closure → v {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    ~ x xs { ( run \ → v { = xs ( vec_new [String] ) } ) }
}

@ a_helper_defined_later → v {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { = xs ( vec_new [String] ) }
    ~ x xs { ( run_later h ) }
}

@ through_a_nested_closure → v {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { = xs ( vec_new [String] ) }
    : ( @ v ) g \ → v { ( h ) }
    ~ x xs { ( g ) }
}

@ cleared_by_a_generic_callee → v {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { ( vec_clear [String] xs ) }
    ~ x xs { ( h ) }
}

@ run_later ( @ v ) f → v { ( f ) }

@ main → i { ^ 0 }
