// H405: a closure gave a field of a struct it captured by reference
// (`: ~ Q q`) a new value: the value the field held was never released.
// Closed: a field of a by-pointer capture given a new value releases the old
// one when the captured binding owns it — the caller's drop flag, which the
// env carries (agora #144).
// v0.80.0: accepted; LeakSanitizer reported memory leaks.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ main → i {
    : ~ Q q @ Q { ( mk ) ( mk ) }
    : ( @ v ) h \ → v { = . q tag ( mk ) }
    ( h )
    ( nurl_println ( string_data . q tag ) )
    ^ 0
}
