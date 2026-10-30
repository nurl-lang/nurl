// loop_container_cleared_by_an_inline_closure: agora #151 — a closure that gives a capture a new value, or changes it (loop_container_cleared_by_an_inline_closure).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.5 | A1 | rejected | h532 | agora #151: loop_container_cleared_by_an_inline_closure
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
        ( run \ → v { ( vec_clear [String] xs ) } )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
