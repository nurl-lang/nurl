// closure_local_view_given_to_a_capture_outlives_source: agora #312 — a closure assigning a captured struct a value holding a body local's view of a block's String.
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #312: a closure giving a capture a body local's view
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ V w @ V { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ( @ v ) repoint \ → v { : s t ( string_data b ) = w @ V { t } }
        ( repoint )
    }
    ( nurl_println . w v )
    ^ 0
}
