// drop_view_source_declared_first: agora #224 — `: String s` then `: W w @ W { ( string_data s ) }`: the source first, its holder second (drop_view_source_declared_first).
// Closed: scope-end drops run newest first (LIFO, as in Rust and C++), so a holder declared after its source is dropped before it, and the borrow checker ends a scope's bindings in the same order (agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free (s dropped first, in declaration order).
// map: §7.6 | A2 | runs-clean | - | agora #224: `: String s` then `: W w @ W { ( string_data s ) }`: the source first, its holder second
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : String s ( string_from `declared first, dropped last` )
    : W w @ W { ( string_data s ) }
    ^ 0
}
