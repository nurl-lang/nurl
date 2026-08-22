// diag_closure_param_name_reg.nu — the same reservation on a closure's
// parameter list: a closure body stores its parameters from `%<name>` too.
@ main → i {
    : ( @ i i ) inc \ i r2 → i { ^ + r2 1 }
    ^ ( inc 41 )
}
