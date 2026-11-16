// A `break` in a closure literal written inside a `~` loop, with no loop of
// its own in the closure body. The closure is a function of its own: the
// enclosing loop's exit label is a block of the enclosing function, and the
// branch to it was emitted into the closure's function, which clang refused
// (`use of undefined value '%loop_exit_3'`). nurlc refuses it now, naming
// the reason (agora #871): an exit never crosses a call frame, as in the
// calculus (formal/A2: a block's exits are its own body's).
@ app ( @ i ) f → i { ^ ( f ) }

@ main → i {
    : ~ i i 0
    ~ < i 3 {
        : i r ( app \ → i { break ^ 1 } )
        = i + i 1
    }
    ^ 0
}
