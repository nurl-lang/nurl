// diag_closure_body_unbraced.nu — a closure body written bare. Always
// braced, even for a single expression.
@ main → i {
    : ( @ i i ) f \ i x → i ^ + x 1
    ^ 0
}
