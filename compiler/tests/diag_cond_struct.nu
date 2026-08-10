// diag_cond_struct.nu — a struct used directly as a condition.
: S { i a }

@ main → i {
    : S s @ S { 1 }
    ? s { ^ 1 } {}
    ^ 0
}
