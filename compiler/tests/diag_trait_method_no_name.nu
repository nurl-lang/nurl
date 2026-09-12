// diag_trait_method_no_name.nu — an `@` in a trait body with no method
// name after it. A trait declares each method as `@ name params → ret`;
// without the name there is nothing to record a signature under, and
// the scan used to walk on and record one anyway.

% Sh {
    @ → i
}

@ main → i {
    ^ 0
}
