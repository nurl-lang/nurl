// diag_call_closure_sig_mismatch.nu — a closure whose signature
// differs from the declared '(@ …)' parameter type. The callee invokes
// the closure with the DECLARED signature, so every argument and the
// return value would be reinterpreted bit patterns (here: an i64
// argument read as a double). Compared whitespace-blind because the
// two lowering paths spell the aggregate with different spacing.
@ apply ( @ i i ) fn i x → i { ^ ( fn x ) }

@ main → i {
    : ( @ f f ) g \ f a → f { ^ a }
    ^ ( apply g 3 )
}
