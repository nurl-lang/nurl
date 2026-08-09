// diag_dup_variant_same_enum.nu — the same variant declared twice in
// one enum: two tags cannot share a name (a match arm or a bare `X`
// could only ever reach the first).
: | A {
    X
    X
}

@ main → i {
    ^ 0
}
