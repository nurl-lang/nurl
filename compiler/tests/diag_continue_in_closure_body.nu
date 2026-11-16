// A `continue` in a closure literal written inside a `~` loop, with no loop
// of its own in the closure body: refused, naming the reason, as `break` is
// (diag_break_in_closure_body.nu; agora #871). It branched to the enclosing
// function's loop check block from the closure's function.
@ app ( @ i ) f → i { ^ ( f ) }

@ main → i {
    : ~ i i 0
    ~ < i 3 {
        = i + i 1
        : i r ( app \ → i { continue ^ 1 } )
    }
    ^ 0
}
