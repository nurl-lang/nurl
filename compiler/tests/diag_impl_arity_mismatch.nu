// diag_impl_arity_mismatch.nu — an impl with fewer parameters than the
// trait declares. The call site is checked against the declaration, so
// the extra argument lands in a register the impl never reads.

% Sh {
    @ area i o i k → i
}

% Sh i {
    @ area i o → i { ^ o }
}

@ main → i {
    ^ 0
}
