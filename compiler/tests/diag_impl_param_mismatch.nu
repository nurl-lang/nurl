// diag_impl_param_mismatch.nu — an impl whose non-receiver parameter
// types are not the ones the trait declares.
//
// Every call site is type-checked against the DECLARATION, and `dyn`
// dispatch builds its thunk from it, so the impl reads the caller`s
// arguments as the types it declared for itself.

% Sh {
    @ area i o i k → i
}

% Sh i {
    @ area i o f k → i { ^ o }
}

@ main → i {
    ^ 0
}
