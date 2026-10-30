// closure_bound_then_returned_over_a_parameter: a closure literal bound to a local and then returned (`: ( @ v ) c \ → v { … s … } ^ c`), over a String parameter it captured without taking it over, outlived the caller's argument: the callee's `retclo` summary recorded only a closure literal written in the `^`, so the caller's binding of the result held no view of its argument, the caller freed it, and the closure read freed memory.
// Closed: what a returned value that may hold a closure lends is read off its source expression at the `^` — through the closures, views and borrows of the frame it names, by their borrow-checker rows (__clo_param_lends) — and a bound closure literal records the parameters it lends (mem_note_clo_bind_lend), agora #141.
// v0.79.1: accepted; AddressSanitizer reported heap-use-after-free in the closure's string_data.
// map: §2.11 | A2 | rejected | h384 | a closure literal bound to a local, then returned over a String parameter: retclo recorded only a literal written in the ^; the caller freed its argument and the closure read freed memory (UAF); a returned value that may hold a closure lends what its source expression reaches
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
