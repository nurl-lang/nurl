// diag_impl_receiver_mismatch.nu — an impl whose receiver is not the
// type it implements the trait for.
//
// In a NON-generic trait the receiver slot is a placeholder each impl
// replaces, so a differing receiver there is the idiom. In a GENERIC
// trait the receiver IS the type parameter, and substitution makes it
// exact: `% Sp Dog` must take a `Dog`. A `dyn` object calls through the
// thunk built from the DECLARED signature, so a disagreement here is a
// type confusion at the call, not a local matter.

% Sp [T] {
    @ speak T self → i
}

: Dog {
    i pitch
}

% Sp Dog {
    @ speak i self → i { ^ self }
}

@ main → i {
    : Dog d @ Dog { 3 }
    ^ . d pitch
}
