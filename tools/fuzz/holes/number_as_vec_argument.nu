// number_as_vec_argument: a number passed where a function takes a ( Vec i ) by value: the call handed the callee the integer as the Vec's bytes, a control block at address 0, and vec_push wrote through null.
// Closed: outside `unsafe` no number is passed for a struct parameter (an enum's takes a bare variant) — __arg_param_checks.
// ASan: SEGV in vec_push (use).
// map: §6.2 | B | rejected | h188 | number passed for a Vec by-value parameter: callee pushes through null
$ `stdlib/core/vec.nu`

@ use ( Vec i ) v → i {
    ( vec_push [i] v 1 )
    ^ ( vec_len [i] v )
}

@ main → i {
    ( nurl_println_int ( use 0 ) )
    ^ 0
}
