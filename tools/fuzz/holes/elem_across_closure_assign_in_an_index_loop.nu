// elem_across_closure_assign_in_an_index_loop: agora #151 — a closure that gives a capture a new value, or changes it (elem_across_closure_assign_in_an_index_loop).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h542 | agora #151: elem_across_closure_assign_in_an_index_loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    : ( @ v ) h \ → v { = xs ( vec_new [String] ) }
    : ~ i k 0
    ~ < k ( vec_len [String] xs ) {
        : String e ( vec_at [String] xs k )
        ( h )
        ( nurl_println ( string_data e ) )
        = k + k 1
    }
    ^ 0
}
