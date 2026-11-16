// A closure literal inside a `~` loop whose body has a loop of its own,
// then a `break` after that loop has ended: the innermost loop around the
// `break` is now the enclosing function's, which a closure body cannot
// leave. Refused, naming the reason (agora #871): the closure depth the
// innermost loop was opened at is restored when the closure's own loop
// ends, so the jump is seen at the wrong depth.
@ app ( @ i ) f → i { ^ ( f ) }

@ main → i {
    : ~ i i 0
    ~ < i 3 {
        : i r ( app \ → i {
            : ~ i k 0
            ~ < k 2 { = k + k 1 }
            break
            ^ k
        } )
        = i + i 1
    }
    ^ 0
}
