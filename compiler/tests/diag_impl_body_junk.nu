// diag_impl_body_junk.nu — a token in an impl body that is neither a
// method nor an associated-type binding.
//
// It used to be skipped. The skip is what made an UNTERMINATED body
// dangerous: the scan stopped somewhere the emit pass did not, the two
// disagreed about where the block ended, and whatever was in between
// vanished without a word.

% Sh {
    @ area i o → i
}

% Sh i {
    42
}

@ main → i {
    ^ 0
}
