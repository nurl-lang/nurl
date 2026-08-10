// diag_call_unknown_named_arg.nu — a named argument whose name is not a
// declared parameter. NURL matches named arguments by exact spelling,
// so a typo is an error and not a silently-dropped keyword.
@ add i x i y → i { ^ + x y }

@ main → i {
    : i r ( add x : 1 z : 2 )
    ^ r
}
