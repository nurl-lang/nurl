// closure_changes_view_free_captures: agora #312 — a closure that changes an integer capture and gives a String capture a fresh value (the shape #312's refusal must keep).
// Closed: a closure cannot give one of its captures, or its own `inout` parameter, a value that may hold a view — a whole assignment, a field store, a push or keep the callee really stores — since a closure's type does not say what running it stores, so nothing where it runs follows the view; A2's CapsOK and Implements (__clo_cap_marks, bck_clo_cap_view_diag, agora #312).
// main: accepted; ran clean.
// map: §2.11 | A2 | runs-clean | - | agora #312: a closure changing view-free captures
$ `stdlib/core/string.nu`

@ main → i {
    : ~ i n 0
    : ~ String t ( string_from `start` )
    : ( @ v ) bump \ → v { = n + n 1 = t ( string_from `again` ) }
    ( bump )
    ( bump )
    ( nurl_println_int n )
    ( nurl_println ( string_data t ) )
    ^ 0
}
