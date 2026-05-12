// group_c.nu — tests for Group C: compound types, type inference,
//              aggregate construction (@ T { ... }) and field access (. agg INT)
//
// Build:
//   ./nurlc.exe compiler/tests/group_c.nu > /tmp/group_c.ll
//   clang /tmp/group_c.ll stdlib/runtime.o -o /tmp/group_c
//   /tmp/group_c
//
// Expected output:
//   7
//   hello
//   true
//   8
//   true
//   42
//   false

@ add i a i b → i { ^ + a b }

// fn_type as parameter type: (@ i i) is a function pointer taking i, returning i
@ apply (@ i i) cb i x → i { ^ x }

@ main → v {
  // ── Type inference ────────────────────────────────────────────────
  : x ( add 3 4 )            // x inferred as i
  ( nurl_print_int x )       // 7
  : msg `hello`              // msg inferred as s
  ( nurl_print_str msg )     // hello
  : flag T                   // flag inferred as b
  ( nurl_print_bool flag )   // true

  // ── fn_type sizeof: (@ i i) ───────────────────────────────────────
  ( nurl_print_int Z (@ i i) ) // sizeof fn ptr → 8

  // ── Aggregate construction + numeric field access ─────────────────
  // @ ? i { T 42 }  builds { i1=true, i64=42 }  (Some(42))
  : opt @ ? i { T 42 }
  : is_some . opt 0           // extractvalue field 0 → i1
  ( nurl_print_bool is_some ) // true
  : val . opt 1               // extractvalue field 1 → i64
  ( nurl_print_int val )      // 42

  // @ ? i { F 0 }  builds { i1=false, i64=0 }  (None)
  : none @ ? i { F 0 }
  : none_tag . none 0
  ( nurl_print_bool none_tag ) // false
}
