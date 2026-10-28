// H393: as h389, a trait method whose by-value receiver's field it releases.
// Closed: as h389 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

% Show Q { @ show Q q → v { ( string_free . q name ) } }

@ main → i {
    : Q q @ Q { ( mk ) ( mk ) }
    ( show q )
    ( nurl_println ( string_data . q tag ) )
    ^ 0
}
