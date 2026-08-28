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
    ( nurl_println `3.14` )

    // ── sizeof ────────────────────────────────────────────────────────
    ( nurl_println_int Z i )  // i64  → 8
    ( nurl_println_int Z f )  // double → 8
    ( nurl_println_int Z s )  // i8*  → 8
    ( nurl_println_int Z b )  // i1   → 1
    ( nurl_println_int Z *i )  // i64* → 8

    // ── defer ─────────────────────────────────────────────────────────
    ( nurl_println `before` )
    ; { ( nurl_println `after` ) }
    ( nurl_println `work` )
    // implicit return here: defer runs → prints "after"
}
