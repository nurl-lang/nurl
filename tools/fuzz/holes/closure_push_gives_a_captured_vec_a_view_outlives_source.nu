// closure_push_gives_a_captured_vec_a_view_outlives_source: agora #312 — a closure pushing a view of a block's String into a captured Vec of views, read after the block.
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #312: a closure's push of a view into a captured Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    ( vec_push [s] ws ( string_data a ) )
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ( @ v ) grow \ → v { ( vec_push [s] ws ( string_data b ) ) }
        ( grow )
    }
    ( nurl_println ( vec_at [s] ws 1 ) )
    ( vec_free [s] ws )
    ^ 0
}
