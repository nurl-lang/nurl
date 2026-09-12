// diag_impl_missing_method.nu — an impl that omits a method the trait
// requires.
//
// A trait method with no body is required. An impl was never checked
// against the trait it names at all, so omitting one simply compiled,
// and a `dyn` object built a vtable slot for a method nothing defined.

% Sh {
    @ area i o → i
}

% Sh i {
}

@ main → i {
    ^ 0
}
