// field_of_a_parameter_taken_then_the_caller_read_the_struct: a function handed a field of its by-value struct parameter to a
// consumer and dropped the rest: it took the parameter over (kept), but its
// caller's binding was not moved, and the caller read the struct after the
// call.
// Closed: a parameter whose field is handed to a callee that takes it is an
// inferred `sink`: the call moves the caller's binding (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | rejected | h389 | a field of a by-value struct parameter handed to string_free: the function took the parameter over (kept) and dropped the rest, but the caller read the struct after the call (UAF); a parameter whose field is taken is an inferred sink
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ f Q q → v { ( string_free . q name ) }

@ main → i {
    : Q q @ Q { ( mk ) ( mk ) }
    ( f q )
    ( nurl_println ( string_data . q tag ) )
    ^ 0
}
