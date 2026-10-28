// OPEN in v0.79.1 — a closure literal bound to a local and then returned, over a String parameter it captured without taking it over (`: ( @ v ) c \ → v { … s … } ^ c`): the callee's `retclo` summary records only a closure literal written in the `^`, so the caller's binding of the result holds no view of its argument, the caller frees it, and the closure reads freed memory. ASan: heap-use-after-free (agora #141).
$ `stdlib/core/string.nu`

@ mk3 String s → ( @ v ) {
    : ( @ v ) c \ → v { ( nurl_println ( string_data s ) ) }
    ^ c
}

@ main → i {
    : String t ( string_from `a string long enough to own a heap buffer here` )
    : ( @ v ) g ( mk3 t )
    ( string_free t )
    ( g )
    ^ 0
}
