// string_param_view_by_a_call_in_a_closure_outlives_source: agora #301 — a closure that hands one capture and a String capture to a callee storing a view of the String's buffer; the String ends in a block, the holder read after it.
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312; #301 made it a dependency where the closure ran).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #301: a closure that hands one capture and a String capture to a callee storing a view of the String's buffer; the String ends in a block, the holder read after it
$ `stdlib/core/string.nu`

: W { s v }

@ repoint inout W w String src → v { = w @ W { ( string_data src ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ( @ v ) f \ → v { ( repoint w b ) }
        ( f )
    }
    ( nurl_println . w v )
    ^ 0
}
