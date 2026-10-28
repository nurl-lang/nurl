// H399: a closure body handed a field of a struct it captured by value to
// `string_free`: only the closure's snapshot was emptied, and the enclosing
// binding released the field again.
// Closed: a field of a capture handed to a callee that takes it is rejected
// — gen_call's `pendfc` row (agora #145; by-reference field writes: agora
// #144).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ main → i {
    : Q q @ Q { ( mk ) ( mk ) }
    : ( @ v ) h \ → v { ( string_free . q name ) }
    ( h )
    ^ 0
}
