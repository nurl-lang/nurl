// H389: a function handed a field of its by-value struct parameter to a
// consumer and dropped the rest: it took the parameter over (kept), but its
// caller's binding was not moved, and the caller read the struct after the
// call.
// Closed: a parameter whose field is handed to a callee that takes it is an
// inferred `sink`: the call moves the caller's binding (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
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
