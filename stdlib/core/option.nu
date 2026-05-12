// stdlib/core/option.nu — combinators for ?T
//
// NURL has `?T` as a built-in tagged union { i1 tag, T payload }. Constructor
// `@ ? T { T v }` builds Some(v); `@ ? T { F 0 }` builds None. Field access
// `. o 0` → tag (i1), `. o 1` → payload (T). The try operator `\` propagates
// None upward through the enclosing function.
//
//   ( opt_is_some [T] o )          → b       true iff o = Some
//   ( opt_is_none [T] o )          → b       true iff o = None
//   ( opt_unwrap_or [T] o default) → T       payload if Some, default otherwise
//   ( opt_map [T U] o f )          → ?U      None → None; Some(v) → Some(f v)
//   ( opt_and_then [T U] o f )     → ?U      None → None; Some(v) → f v
//
// Type-variable names use A/B (not T/U) to avoid colliding with the boolean
// literal `T` used inside `@ ? A { T ... }` constructors.

// Note: direct `. o 0` is intentionally a no-op for opt/res — it returns the
// whole struct so `??` can do its own tag extract. Use `??` here instead.

@ opt_is_some [A] ? A o → b {
  ^ ?? o { T → T  F → F }
}

@ opt_is_none [A] ? A o → b {
  ^ ?? o { T → F  F → T }
}

@ opt_unwrap_or [A] ? A o A default → A {
  ^ ?? o { T v → v  F → default }
}

@ opt_map [A B] ? A o (@ B A) f → ? B {
  : A v \ o
  ^ @ ? B { T ( f v ) }
}

@ opt_and_then [A B] ? A o (@ ? B A) f → ? B {
  : A v \ o
  ^ ( f v )
}
