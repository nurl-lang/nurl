// The imported half of diag_duplicate_fn: a SHARED (non-__) helper whose
// name another file also picked. Nothing is wrong with THIS file — the
// conflict only exists once both are in the same program.
@ shared_helper i x → i {
    ^ + x 1
}
