// group_d.nu — tests for Group D: ffi_decl, enum_decl, try_expr, import_decl
//
// Build:
//   ./nurlc.exe compiler/tests/group_d.nu > /tmp/group_d.ll
//   clang /tmp/group_d.ll stdlib/runtime.o -o /tmp/group_d
//   /tmp/group_d
//
// Expected output:
//   5
//   0
//   1
//   not equal
//   true
//   7
//   false
//   imported
//   30

// ── import_decl ───────────────────────────────────────────────────
$ `compiler/tests/should_fail_group_d_lib.nu`

// ── ffi_decl ──────────────────────────────────────────────────────
// (`strlen` is declared by the compiler preamble globally, so a
// per-file FFI redeclaration is not needed and would duplicate-define.)

// ── enum_decl ─────────────────────────────────────────────────────
: | Direction { North South East West }

// ── Functions using try_expr ──────────────────────────────────────
// Returns Some(a/b) or None if b==0
@ safe_div i a i b → ?i {
    ? == b 0
    { ^ @ ?i { F 0 } }
    { ^ @ ?i { T / a b } }
}

// Uses \ to unwrap; propagates None if safe_div returns None
@ compute i a i b → ?i {
    : r ( safe_div a b )
    : n \ r
    ^ @ ?i { T + n 2 }
}

@ main → v {
    // ── ffi_decl test ────────────────────────────────────────────────
    ( nurl_println_int ( strlen `hello` ) )  // strlen("hello") = 5

    // ── enum test ────────────────────────────────────────────────────
    ( nurl_println_int North )  // 0
    ( nurl_println_int South )  // 1
    ? == North South
    ( nurl_println `equal` )
    ( nurl_println `not equal` )  // not equal

    // ── try_expr: success path ───────────────────────────────────────
    // safe_div(10,2) = Some(5), compute adds 2 → Some(7)
    : ok ( compute 10 2 )
    ( nurl_println ? . ok 0 `true` `false` )  // true
    ( nurl_println_int . ok 1 )  // 7

    // ── try_expr: failure path ───────────────────────────────────────
    // safe_div(10,0) = None, \ propagates → compute returns zeroinitializer
    : no ( compute 10 0 )
    ( nurl_println ? . no 0 `true` `false` )  // false

    // ── import_decl test ─────────────────────────────────────────────
    ( nurl_println ( lib_greet ) )  // imported
    ( nurl_println_int ( lib_mul 5 6 ) )  // 30
}
