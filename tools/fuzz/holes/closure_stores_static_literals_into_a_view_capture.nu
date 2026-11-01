// closure_stores_static_literals_into_a_view_capture: agora #312 — a closure that gives a captured struct of views static literals, whole and by a field (the shape #312's refusal must keep).
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312).
// main: accepted; ran clean.
// map: §2.11 | A2 | runs-clean | - | agora #312: a closure storing static literals into a view-holding capture
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ V w @ V { ( string_data a ) }
    : ( @ v ) reset \ → v { = w @ V { `a static literal` } = . w v `another static literal` }
    ( reset )
    ( nurl_println . w v )
    ^ 0
}
