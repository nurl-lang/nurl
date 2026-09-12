// diag_trait_method_no_return_type.nu — a trait method header with no
// return arrow at all, in the spelling that is not the ASCII-arrow
// mistake (see diag_trait_method_no_arrow.nu for that one).
//
// Every other function header requires the arrow. A trait method header
// did not: the scan recorded a signature with no return type, and
// nothing read it back unless the trait was used as a `dyn` object — a
// use the program may never make.

% Sh [T] {
    @ area T o i
}

@ main → i {
    ^ 0
}
