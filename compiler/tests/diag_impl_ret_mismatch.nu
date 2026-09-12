// diag_impl_ret_mismatch.nu — an impl whose return type is not the
// one the trait declares.
//
// This is the sharpest of the signature mismatches: `dyn` builds its
// thunk from the DECLARED signature, so a trait promising an integer
// and an impl returning a string hands the caller a pointer to read as
// an integer, with no diagnostic anywhere.

% Sh {
    @ area i o → i
}

% Sh i {
    @ area i o → s { ^ `x` }
}

@ main → i {
    ^ 0
}
