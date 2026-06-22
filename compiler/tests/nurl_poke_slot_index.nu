// nurl_poke_slot_index.nu — regression for the `* j 8` heap-overrun
// bug fixed 2026-05-26.
//
// `nurl_poke(base, idx, val)` and `nurl_peek(base, idx)` use SLOT
// indexing (idx scaled by 8 internally for the i64 store/load). The
// prior bug was call sites passing `j * 8` as `idx`, treating it as
// a byte offset — so for an `nurl_alloc(n * 8)` buffer (correctly
// sized for n slots) the call `nurl_poke(buf, j * 8, v)` actually
// wrote at byte offset `j * 64`, scribbling 7×n bytes past the
// buffer end. With ASan instrumentation this is a deterministic
// heap-buffer-overflow on the second write (j=1 → byte 64 vs a
// 16-byte buffer for n=2).
//
// This test:
//   1. Allocates a buffer for `N` slots.
//   2. Writes N distinct markers via `nurl_poke(buf, k, val)`.
//   3. Reads them back via `nurl_peek(buf, k)` and checks each.
//   4. Frees and exits 0.
//
// Under ASan (run via `compiler/tests/run_san_tests.sh`) any
// regression where `nurl_poke` is called with a misshapen index
// would surface immediately as a heap-buffer-overflow. Under a
// regular `./build.sh` run the test is a fast no-op that confirms
// the slot-indexed accessor pair is consistent.

@ main → i {
    : i n 32
    : i bytes * n 8
    : s buf ( nurl_alloc bytes )

    // Write n markers — exactly fills the buffer.
    : ~ i k 0
    ~ < k n {
        : i marker + * k 7 1  // 1, 8, 15, 22, … — distinct per k
        ( nurl_poke buf k marker )
        = k + k 1
    }

    // Read back and verify.
    : ~ i mismatches 0
    = k 0
    ~ < k n {
        : i got ( nurl_peek buf k )
        : i want + * k 7 1
        ? != got want {
            = mismatches + mismatches 1
            ( nurl_print `MISMATCH at slot ` )
            ( nurl_print ( nurl_str_int k ) )
            ( nurl_print `: got=` ) ( nurl_print ( nurl_str_int got ) )
            ( nurl_print ` want=` ) ( nurl_print ( nurl_str_int want ) )
            ( nurl_print `\n` )
        } {}
        = k + k 1
    }

    ( nurl_free buf )

    ( nurl_print `slot_index_ok=` ) ( nurl_print ? == mismatches 0 `T` `F` ) ( nurl_print `\n` )
    ^ mismatches
}
