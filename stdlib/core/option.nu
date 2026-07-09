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
//   ( opt_unwrap_or_else [T] o f ) → T       payload if Some, ( f ) otherwise
//   ( opt_unwrap [T] o )           → T       payload, PANICS on None
//   ( opt_expect [T] o msg )       → T       payload, PANICS with msg on None
//   ( opt_ok_or [T E] o err )      → !T E    Some(v) → Ok(v); None → Err(err)
//   ( opt_map [T U] o f )          → ?U      None → None; Some(v) → Some(f v)
//   ( opt_and_then [T U] o f )     → ?U      None → None; Some(v) → f v
//
// Leaf-site tools: at a site that cannot `\`-propagate (a `→ i` main, a
// callback with a fixed signature), `opt_expect` / `opt_unwrap` take the
// payload or PANIC — a real NURL panic: recover-able, and the unwind
// journal reclaims tracked owned values (docs/MEMORY.md §7). Prefer
// `opt_expect` with a message that names what was being attempted.
//
// Type-variable names use A/B (not T/U) to avoid colliding with the boolean
// literal `T` used inside `@ ? A { T ... }` constructors.

// Note: direct `. o 0` is intentionally a no-op for opt/res — it returns the
// whole struct so `??` can do its own tag extract. Use `??` here instead.

@ opt_is_some [A] ? A o → b {
    ^ ?? o { T → T F → F }
}

@ opt_is_none [A] ? A o → b {
    ^ ?? o { T → F F → T }
}

@ opt_unwrap_or [A] ? A o A default → A {
    ^ ?? o { T v → v F → default }
}

@ opt_unwrap_or_else [A] ? A o ( @ A ) f → A {
    ^ ?? o { T v → v F → ( f ) }
}

// Payload or PANIC with `msg` (recover-able; see the header note).
@ opt_expect [A] ? A o s msg → A {
    ? ( opt_is_none [A] o ) { ( nurl_panic msg ) } {}
    ^ . o 1
}

@ opt_unwrap [A] ? A o → A {
    ? ( opt_is_none [A] o ) { ( nurl_panic `opt_unwrap on a None value` ) } {}
    ^ . o 1
}

// Option → Result bridge: Some(v) → Ok(v), None → Err(err). `err` is
// consumed (moved into the result) on the None path and dropped by the
// caller's normal ownership on the Some path.
@ opt_ok_or [A E] ? A o E err → !A E {
    ^ ?? o {
        T v → @ !A E { T v }
        F → @ !A E { F err }
    }
}

@ opt_map [A B] ? A o ( @ B A ) f → ?B {
    : A v \ o
    ^ @ ?B { T ( f v ) }
}

@ opt_and_then [A B] ? A o ( @ ?B A ) f → ?B {
    : A v \ o
    ^ ( f v )
}
