// diag_closure_captured_guarded_assign.nu — a closure that gives a captured
// guarded `s` a new value is refused with a diagnostic (agora #465).
//
// `cur` is bound from a borrow (string_data), so whether it owns its value
// is tracked in two slots of the enclosing function. The closure's code
// cannot reach them: the assignment used to update the enclosing function's
// registers from inside the closure, and the build died in clang with "use
// of undefined value". Bound to a string it owns (nurl_str_cat's result),
// the same closure compiles and runs.
$ `stdlib/core/string.nu`

@ f String src → i {
    : ~ s cur ( string_data src )
    : ( @ v ) step \ → v { = cur ( nurl_str_slice `xyz` 0 1 ) }
    ( step )
    ^ ( nurl_str_len cur )
}

@ main → i {
    : String s ( string_from `abcdef` )
    ( nurl_print_int ( f s ) ) ( nurl_print `\n` )
    ^ 0
}
