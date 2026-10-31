// drop_view_holder_vec_after_source: agora #224 — a String, then a Vec of W holding views of it (drop_view_holder_vec_after_source).
// Closed: scope-end drops run newest first (LIFO, as in Rust and C++), so a holder declared after its source is dropped before it, and the borrow checker ends a scope's bindings in the same order (agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #224: a String, then a Vec of W holding views of it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String s ( string_from `a holder kept in a Vec made after its source` )
    : ( Vec W ) ws ( vec_new [W] )
    ( vec_push [W] ws @ W { ( string_data s ) } )
    ^ 0
}
