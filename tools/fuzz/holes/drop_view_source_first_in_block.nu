// drop_view_source_first_in_block: agora #224 — the same inside one inner block (drop_view_source_first_in_block).
// Closed: scope-end drops run newest first (LIFO, as in Rust and C++), so a holder declared after its source is dropped before it, and the borrow checker ends a scope's bindings in the same order (agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #224: the same inside one inner block
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    {
        : String s ( string_from `both in one inner block` )
        : W w @ W { ( string_data s ) }
    }
    ^ 0
}
