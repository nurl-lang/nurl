// H387: a closure binding given a new closure over a String parameter (`= c \ → v { … s … }`) and then returned outlived the caller's argument: the binding's summary was its first value's.
// Closed: as h384 — every `assign` row of the binding counts (agora #141).
// v0.79.1: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk String s → ( @ v ) { : ~ ( @ v ) c \ → v { ( nurl_println `none` ) } = c \ → v { ( nurl_println ( string_data s ) ) } ^ c }

@ main → i {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( mk t )
    ( string_free t )
    ( g )
    ^ 0
}
