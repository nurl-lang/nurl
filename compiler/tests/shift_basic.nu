// Test: shift operators `<<` and `>>` (Grammar v1.5).
//
// `<<` lowers to LLVM `shl`, `>>` to `ashr` (arithmetic, sign-preserving).
// Both are pure prefix-binary like the other binops — write `<< x n`,
// not `x << n`.

@ main → i {
    // ── Left shift: 1 << k for k = 0..6 ─────────────────────────────
    ( nurl_print_int << 1 0 )  //  1
    ( nurl_print_int << 1 1 )  //  2
    ( nurl_print_int << 1 2 )  //  4
    ( nurl_print_int << 1 3 )  //  8
    ( nurl_print_int << 1 4 )  // 16
    ( nurl_print_int << 1 6 )  // 64

    // ── Combined into a 32-bit pack: (51966 << 16) | 4660 = 3405648436
    ( nurl_print `--\n` )
    : i pack | << 51966 16 4660
    ( nurl_print_int pack )
    // Reverse: extract high and low halves.
    ( nurl_print_int >> pack 16 )  // 51966
    ( nurl_print_int & pack 65535 )  // 4660

    // ── Arithmetic right shift preserves sign ───────────────────────
    ( nurl_print `--\n` )
    ( nurl_print_int >> -8 1 )  // -4 (arithmetic)
    ( nurl_print_int >> -1 4 )  // -1 (arithmetic shift on -1 stays -1)
    ( nurl_print_int >> 1 0 )  //  1 (no-op)
    ( nurl_print_int >> 1024 5 )  // 32

    // ── Mixed expression: << dominates if used inside binop chain ──
    ( nurl_print `--\n` )
    // Compute (3 * 4) << 2  →  prefix: << * 3 4 2 → 12 << 2 = 48
    ( nurl_print_int << * 3 4 2 )
    // (1 << 10) - 1 = 1023
    ( nurl_print_int - << 1 10 1 )

    // ── Variable shift count ────────────────────────────────────────
    ( nurl_print `--\n` )
    : ~ i k 0
    ~ < k 8 {
        ( nurl_print_int << 1 k )
        = k + k 1
    }

    ^ 0
}
