// diag_closure_arity_few.nu — invoking a closure with fewer arguments
// than its declared type takes. Under opaque pointers the emitted call
// carries its own signature, so `( f 1 )` on a two-param closure
// ASSEMBLED — the callee read an unset parameter register: garbage,
// not even a crash.
@ main → i {
    : ( @ i i i ) f \ i a i b → i { ^ + a b }
    ^ ( f 1 )
}
