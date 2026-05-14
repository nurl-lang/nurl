// group_b.nu — tests for Group B features: float literals, sizeof, defer
//
// Build:
//   ./nurlc.exe compiler/tests/group_b.nu > /tmp/group_b.ll
//   clang /tmp/group_b.ll stdlib/runtime.o -o /tmp/group_b
//   /tmp/group_b
//
// Expected output:
//   3.14
//   8
//   8
//   8
//   1
//   8
//   before
//   work
//   after

@ main → v {
    // ── Float literals ────────────────────────────────────────────────
    ( nurl_print_str `3.14` )

    // ── sizeof ────────────────────────────────────────────────────────
    ( nurl_print_int Z i )  // i64  → 8
    ( nurl_print_int Z f )  // double → 8
    ( nurl_print_int Z s )  // i8*  → 8
    ( nurl_print_int Z b )  // i1   → 1
    ( nurl_print_int Z *i )  // i64* → 8

    // ── defer ─────────────────────────────────────────────────────────
    ( nurl_print_str `before` )
    ; { ( nurl_print_str `after` ) }
    ( nurl_print_str `work` )
    // implicit return here: defer runs → prints "after"
}
