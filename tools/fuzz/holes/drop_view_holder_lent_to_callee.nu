// drop_view_holder_lent_to_callee: agora #224 — a W handed to a callee, then dropped at the end of main after the String it views (drop_view_holder_lent_to_callee).
// Closed: scope-end drops run newest first (LIFO, as in Rust and C++), so a holder declared after its source is dropped before it, and the borrow checker ends a scope's bindings in the same order (agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #224: a W handed to a callee, then dropped at the end of main after the String it views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ keep W w → i { ^ 0 }

@ main → i {
    : String s ( string_from `a holder handed to a callee that drops it` )
    : W w @ W { ( string_data s ) }
    : i n ( keep w )
    ^ n
}
