// H392: as h389, the field handed to a `sink` defined after the caller: the
// parameter's consumption was a module-end implication that only kept it.
// Closed: as h389; the parked implication is a `sink` one, which also keeps
// (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ f Q q → v { ( later . q name ) }

@ main → i {
    : Q q @ Q { ( mk ) ( mk ) }
    ( f q )
    ( nurl_println ( string_data . q tag ) )
    ^ 0
}

@ later sink String s → v { ( string_free s ) }
