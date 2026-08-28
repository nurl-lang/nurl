// Test: native u (u8 = unsigned 8-bit byte) type — Grammar v1.6.
//
// `u` is the only NURL type that lowers to LLVM `i8`. Comparisons,
// `>>`, `/`, `%` use the unsigned variants (`icmp ugt`, `lshr`, `udiv`,
// `urem`). Arithmetic wraps mod 256. Casts: `# u i_expr` truncates,
// `# i u_expr` zero-extends.

@ main → i {
    // ── Bindings + literals + arithmetic wrap-around ────────────────
    : u a 200
    : u b 100
    ( nurl_println_int # i + a 60 )  // 4   (260 mod 256)
    ( nurl_println_int # i - b 200 )  // 156 (-100 mod 256)
    ( nurl_println_int # i * a 3 )  // 88  (600 mod 256)

    // ── Unsigned comparison (signed would say 200 < 100) ─────────────
    ? > a b ( nurl_print `200 > 100 unsigned\n` )
    ( nurl_print `WRONG: signed leak\n` )
    ? < b a ( nurl_print `100 < 200 unsigned\n` )
    ( nurl_print `WRONG: signed leak\n` )

    // ── Logical right shift (200 >> 1 = 100, ashr would give 228) ───
    ( nurl_println_int # i >> a 1 )  // 100
    ( nurl_println_int # i >> 255 4 )  // 15

    // ── Unsigned division and modulo ────────────────────────────────
    ( nurl_println_int # i / a 3 )  // 66  (200 / 3)
    ( nurl_println_int # i % a 7 )  // 4   (200 mod 7)
    // udiv(255 / 16) = 15 (signed -1 / 16 would be 0)
    ( nurl_println_int # i / 255 16 )  // 15

    // ── Slice literal of bytes ──────────────────────────────────────
    : [u xs [u | 0 1 2 3 4 5 6 7 8 9]
    ( nurl_println_int . xs 1 )  // 10  (length)
    : *u p . xs 0
    : ~ i sum 0
    : ~ i k 0
    ~ < k 10 {
        : u v . p k
        = sum + sum # i v
        = k + k 1
    }
    ( nurl_println_int sum )  // 45

    // ── Heap-allocated u-buffer via nurl_alloc + poke + peek ────────
    // Keep this branch generic: nurl_alloc returns i8* and we cast it
    // through to *u for typed access. This is exactly the pattern a
    // future `bytes` module will use.
    // (0xCA 0xFE 0xBA 0xBE = 202 254 186 190 — NURL has no hex literals yet.)
    : *u buf # *u ( nurl_alloc 4 )
    = . buf 0 # u 202
    = . buf 1 # u 254
    = . buf 2 # u 186
    = . buf 3 # u 190
    : u b0 . buf 0
    : u b1 . buf 1
    : u b2 . buf 2
    : u b3 . buf 3
    ( nurl_println_int # i b0 )  // 202 (0xCA)
    ( nurl_println_int # i b1 )  // 254 (0xFE)
    ( nurl_println_int # i b2 )  // 186 (0xBA)
    ( nurl_println_int # i b3 )  // 190 (0xBE)
    ( nurl_free # *v buf )

    // ── Cast round-trip + bool widen ────────────────────────────────
    : u from_b # u T  // 1
    ( nurl_println_int # i from_b )  // 1
    : u big # u 1000  // truncates to 232 (1000 mod 256)
    ( nurl_println_int # i big )  // 232

    ^ 0
}
