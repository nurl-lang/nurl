// diag_trait_body_junk.nu — a token in a trait body that is neither a
// method nor an associated type. Same rule, and the same reason, as
// diag_impl_body_junk.nu: a skip here is what let an unterminated trait
// body swallow the declarations after it.

% Sh {
    42
}

@ main → i {
    ^ 0
}
