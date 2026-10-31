// elem_across_inline_closure_assign: agora #151 — a closure that gives a capture a new value, or changes it (elem_across_inline_closure_assign).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h531 | agora #151: elem_across_inline_closure_assign
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : String e ( vec_at [String] xs 0 )
    ( run \ → v { = xs ( vec_new [String] ) } )
    ( nurl_println ( string_data e ) )
    ^ 0
}
