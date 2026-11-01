// braceless_arm_repoints_a_vec_at_binding_then_returned: agora #335 (formal's #1610 regression 2) — a `: ~ Conn` binding of a local Vec's element, given a fresh value in a match arm written without braces, then returned. The arm runs no block entry, so its `=` was taken as straight-line and dropped the lend: the element left as owned, a double drop on #1494's first head.
// Closed: gen_match counts every arm body as a block level, braced or not, so mem_note_assign_lend keeps the lend for an `=` that may not run.
// main: refused ("this hands back what 'vec_at' may lend out of 'cs'"); the braced arm is refused too.
// map: §7.6 | A2 | rejected | - | agora #335: a brace-less arm's re-point does not drop the binding's lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn {
    @ drop Conn c → v {}
}

@ pick ? i o → Conn {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `x` ) } )
    : ~ Conn c ( vec_at [Conn] cs 0 )
    ?? o { T e → = c @ Conn { ( string_from `y` ) } F → {} }
    ^ c
}

@ main → i {
    : Conn a ( pick @ ?i { F } )
    ^ 0
}
