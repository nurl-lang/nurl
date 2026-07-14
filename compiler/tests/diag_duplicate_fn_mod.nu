// The imported half of diag_duplicate_fn: a file with a "private"
// helper whose name another file also picked. There is nothing wrong with
// THIS file — the conflict only exists once both are in the same program.
@ __shared_helper i x → i {
    ^ + x 1
}
