// nested_closure_frees_its_capture_twice: agora #151 — a closure that gives a capture a new value, or changes it (nested_closure_frees_its_capture_twice).
// Closed: the assignment is an effect of running the closure (agora #151).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.11 | A2 | rejected | h537 | agora #151: nested_closure_frees_its_capture_twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ String s ( mk )
    : ( @ v ) h \ → v { ( string_free s ) }
    : ( @ v ) g \ → v { ( h ) }
    ( g )
    ( g )
    ^ 0
}
