// diag_cond_void_call.nu — a 'v'-returning call as a condition.
@ nothing → v {}

@ main → i {
    ? ( nothing ) { ^ 1 } {}
    ^ 0
}
