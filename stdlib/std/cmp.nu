// stdlib/std/cmp.nu — three-way comparison + min/max/clamp
//
// Convention: a comparator returns
//   < 0   when a precedes b   (a is "smaller")
//     0   when a == b
//   > 0   when a follows b
//
// Stock comparators on this convention:
//   ( cmp_int a b )            → i  for i
//   ( cmp_float a b )          → i  for f (NaN treated as greatest, see below)
//   ( cmp_str a b )            → i  for raw `s` (i8*) — bytewise via strcmp
//   ( cmp_string a b )         → i  for owned String handles
//
// Generic helpers (parameterised over a comparator closure):
//   ( min_by [A] a b cmp )     → A  the smaller of two values
//   ( max_by [A] a b cmp )     → A  the larger
//   ( clamp_by [A] x lo hi cmp ) → A  x bounded to [lo..hi]
//
// Convenience scalar helpers (no closure overhead):
//   ( min_i a b ) ( max_i a b ) ( clamp_i x lo hi )
//   ( min_f a b ) ( max_f a b ) ( clamp_f x lo hi )
//
// Pair these with stdlib/std/sort.nu's sort_by / binary_search.

$ `stdlib/core/string.nu`

// ── Stock comparators ──────────────────────────────────────────────

@ cmp_int i a i b → i {
  ? < a b { ^ -1 } {}
  ? > a b { ^ 1 } {}
  ^ 0
}

// IEEE-754 caveat: NaN is non-comparable to anything. We treat any
// occurrence of NaN as "greater" so sort places NaNs at the end and
// binary_search stays well-defined. If you need stricter semantics,
// filter NaNs out first.
@ cmp_float f a f b → i {
  ? < a b { ^ -1 } {}
  ? > a b { ^ 1 } {}
  ^ 0
}

@ cmp_str s a s b → i {
  ^ ( nurl_str_cmp a b )
}

@ cmp_string String a String b → i {
  ^ ( nurl_str_cmp ( string_data a ) ( string_data b ) )
}

// ── Generic min/max/clamp via comparator ───────────────────────────

@ min_by [A] A a A b (@ i A A) cmp → A {
  ? <= ( cmp a b ) 0 { ^ a } {}
  ^ b
}

@ max_by [A] A a A b (@ i A A) cmp → A {
  ? >= ( cmp a b ) 0 { ^ a } {}
  ^ b
}

@ clamp_by [A] A x A lo A hi (@ i A A) cmp → A {
  ? < ( cmp x lo ) 0 { ^ lo } {}
  ? > ( cmp x hi ) 0 { ^ hi } {}
  ^ x
}

// ── Scalar specialisations ─────────────────────────────────────────

@ min_i i a i b → i {
  ? < a b { ^ a } {}
  ^ b
}

@ max_i i a i b → i {
  ? > a b { ^ a } {}
  ^ b
}

@ clamp_i i x i lo i hi → i {
  ? < x lo { ^ lo } {}
  ? > x hi { ^ hi } {}
  ^ x
}

@ min_f f a f b → f {
  ? < a b { ^ a } {}
  ^ b
}

@ max_f f a f b → f {
  ? > a b { ^ a } {}
  ^ b
}

@ clamp_f f x f lo f hi → f {
  ? < x lo { ^ lo } {}
  ? > x hi { ^ hi } {}
  ^ x
}
