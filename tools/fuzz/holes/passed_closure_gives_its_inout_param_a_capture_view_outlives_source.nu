// passed_closure_gives_its_inout_param_a_capture_view_outlives_source: agora #312 — as closure_gives_its_inout_param_a_capture_view_outlives_source, the literal handed to a function that runs it on its own `inout` parameter.
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #312: a closure literal, run by a function, giving its inout parameter a capture's view
$ `stdlib/core/string.nu`

: V { s v }

@ run_on ( @ v inout V ) f inout V p → v { ( f p ) }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ V w @ V { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( run_on \ inout V x → v { = x @ V { ( string_data b ) } } w )
    }
    ( nurl_println . w v )
    ^ 0
}
