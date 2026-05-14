// Test: multi-field struct mutation through closures.
// Before 2026-05-14: closures captured multi-field structs by value
// (heap-malloced env block snapshotted the struct from the caller's
// alloca), so `= . c field val` inside the closure body landed on a
// dead local copy and the caller's binding stayed at the initial
// value. The standard workaround was to back state with a single
// pointer-handle struct (e.g. `( Vec i )`).
//
// Fix (2026-05-14): when a captured binding is BOTH `__mutable`
// (declared with `: ~`) AND a multi-field struct (the named type
// has at least one `__idx_1__type` registered and is not an enum),
// the closure captures by POINTER instead of by value. The env field
// type becomes `T*`, the body reads the pointer back, and registers
// it as the binding's `__ptr` directly — every read/write reaches
// the caller's alloca. Closes docs/GOTCHAS.md §2.
//
// Backward-compatible: immutable captures (`: Counter c …`) keep the
// snapshot behaviour. Single-field handle structs (`%String`, `%Vec`)
// already share through their inner pointer, so they're unaffected.

: Counter { i n  i max }

@ main → i {
  // ── Case 1: explicit `: ~` Counter, mutated through closure ──────
  : ~ Counter c1 @ Counter { 0 100 }
  : (@ v) bump \ → v {
    = . c1 n + . c1 n 1
  }
  ( bump ) ( bump ) ( bump )
  ( nurl_print `c1.n=` )
  ( nurl_print ( nurl_str_int . c1 n ) )
  ( nurl_print `\n` )

  // Reading c1.max inside the closure also reaches the caller's alloca.
  : (@ i) read_max \ → i {
    ^ . c1 max
  }
  ( nurl_print `c1.max=` )
  ( nurl_print ( nurl_str_int ( read_max ) ) )
  ( nurl_print `\n` )

  // ── Case 2: caller mutation OUTSIDE the closure still visible ────
  // The closure captures a pointer; the caller's alloca is shared,
  // so caller-side writes are observed on the next closure call.
  = . c1 max 999
  ( nurl_print `c1.max=` )
  ( nurl_print ( nurl_str_int ( read_max ) ) )
  ( nurl_print `\n` )

  // ── Case 3: immutable binding still snapshots (backward compat) ─
  : Counter c2 @ Counter { 7 11 }
  : (@ v) snap_bump \ → v {
    // This `=` writes to the local snapshot, not the caller's c2.
    = . c2 n + . c2 n 1
  }
  ( snap_bump ) ( snap_bump )
  ( nurl_print `c2.n (caller view)=` )
  ( nurl_print ( nurl_str_int . c2 n ) )
  ( nurl_print `\n` )

  // ── Case 4: whole-struct reassignment on a `: ~` binding ─────────
  // The closure's pointer keeps pointing at the same alloca, so a
  // caller-side `= c1 @ Counter { … }` overwrites the alloca's
  // contents — the closure sees the new value.
  = c1 @ Counter { 42 84 }
  ( nurl_print `c1 after reassign: n=` )
  ( nurl_print ( nurl_str_int . c1 n ) )
  ( nurl_print `, max=` )
  ( nurl_print ( nurl_str_int . c1 max ) )
  ( nurl_print `\n` )
  ( nurl_print `c1.max via closure=` )
  ( nurl_print ( nurl_str_int ( read_max ) ) )
  ( nurl_print `\n` )

  ^ 0
}
