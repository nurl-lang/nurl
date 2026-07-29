// The mirror image of should_fail_ret_int_width: a `b`-typed comparison
// returned from a `→ i` function emitted `ret i1` out of an i64
// function. Must be a compile error suggesting '^ ? cond 1 0'.
@ cmp i a i b → i { ^ == a b }

@ main → i { ^ ( cmp 1 1 ) }
