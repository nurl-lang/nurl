// drop_view_slice_source_first: agora #224 — a Vec, then a W holding a Slice of it (drop_view_slice_source_first).
// Closed: scope-end drops run newest first (LIFO, as in Rust and C++), so a holder declared after its source is dropped before it, and the borrow checker ends a scope's bindings in the same order (agora #224).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #224: a Vec, then a W holding a Slice of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: W { ( Slice u ) sl }

% Drop W { @ drop W self → v { ?? ( slice_get [u] . self sl 3 ) { T b → ( nurl_println_int # i b ) F _ → {} } } }

@ main → i {
    : ( Vec u ) v ( vec_zeroed [u] 64 )
    : W w @ W { ( slice_from_vec [u] v ) }
    ^ 0
}
