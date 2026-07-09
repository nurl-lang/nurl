// stdlib/core/result.nu — combinators for !T E
//
// NURL's `!T E` lowers to `{ i1 tag, T ok, E err }` — both payloads sit BY
// VALUE in their own slot (no i64 squeeze / heap-box). Constructor
// `@ ! T E { T v }` → Ok(v) fills field 1; `@ ! T E { F e }` → Err(e) fills
// field 2. Field access `. r 0` → tag, `. r 1` → Ok payload (type T),
// `. r 2` → Err payload (type E). `\` propagates Err upward and requires
// matching error types in the enclosing function.
//
//   ( res_is_ok      [T E]   r )           → b     true iff r = Ok
//   ( res_is_err     [T E]   r )           → b     true iff r = Err
//   ( res_unwrap_or  [T E]   r default )   → T     Ok payload or default
//   ( res_unwrap_or_else [T E] r f )       → T     Ok payload or ( f err )
//   ( res_unwrap     [T E]   r )           → T     Ok payload, PANICS on Err
//   ( res_expect     [T E]   r msg )       → T     Ok payload, PANICS with msg on Err
//   ( res_ok         [T E]   r )           → ?T    Ok(v) → Some(v); Err → None
//   ( res_err        [T E]   r )           → ?E    Err(e) → Some(e); Ok → None
//   ( res_map        [T U E] r f )         → !U E  f: T → U; Err forwards
//   ( res_and_then   [T U E] r f )         → !U E  f: T → !U E; Err forwards
//   ( res_map_err    [T E G] r fe )        → !T G  fe: E → G; Ok forwards
//
// Leaf-site tools: at a site that cannot `\`-propagate (a `→ i` main, a
// callback with a fixed signature), `res_expect` / `res_unwrap` take the
// Ok payload or PANIC — a real NURL panic: recover-able, and the unwind
// journal reclaims tracked owned values (docs/MEMORY.md §7). Prefer
// `res_expect` with a message that names what was being attempted; the
// Err payload itself is not rendered (no generic display dispatch), so
// say it in the message.
//
// Forwarding note: the Err branch is rebuilt via `@ ! U E { F . r 2 }`. `!T E`
// and `!U E` share the same Err slot type E in field 2, so `. r 2` yields the
// error value at its real type, which feeds straight back into the new
// constructor by value.
//
// `res_map_err` binds the err in the F arm at its real type E (field 2,
// by value) and passes it to `fe` directly via the `# E e` cast (now a no-op
// for already-typed payloads). Enum re-construction in `#` still applies for
// bare-variant payloads.
//
// Type-variable names avoid `T` and `F` because those lex as bool literals
// and would be rewritten by the generic source substitution — A/B for value
// types, E/G for error types.

@ res_is_ok [A E] ! A E r → b {
    ^ ?? r { T → T F → F }
}

@ res_is_err [A E] ! A E r → b {
    ^ ?? r { T → F F → T }
}

@ res_unwrap_or [A E] ! A E r A default → A {
    ^ ?? r { T v → v F → default }
}

@ res_unwrap_or_else [A E] ! A E r ( @ A E ) f → A {
    ^ ?? r {
        T v → v
        F e → ( f # E e )
    }
}

// Ok payload or PANIC with `msg` (recover-able; see the header note).
@ res_expect [A E] ! A E r s msg → A {
    ? ( res_is_err [A E] r ) { ( nurl_panic msg ) } {}
    ^ . r 1
}

@ res_unwrap [A E] ! A E r → A {
    ? ( res_is_err [A E] r ) { ( nurl_panic `res_unwrap on an Err value` ) } {}
    ^ . r 1
}

// Result → Option bridges (drop the other payload).
@ res_ok [A E] ! A E r → ?A {
    ^ ?? r {
        T v → @ ?A { T v }
        F → @ ?A { F }
    }
}

@ res_err [A E] ! A E r → ?E {
    ^ ?? r {
        T → @ ?E { F }
        F e → @ ?E { T # E e }
    }
}

@ res_map [A B E] ! A E r ( @ B A ) f → !B E {
    ^ ?? r {
        T v → @ !B E { T ( f v ) }
        F → @ !B E { F . r 2 }
    }
}

@ res_and_then [A B E] ! A E r ( @ !B E A ) f → !B E {
    ^ ?? r {
        T v → ( f v )
        F → @ !B E { F . r 2 }
    }
}

@ res_map_err [A E G] ! A E r ( @ G E ) fe → !A G {
    ^ ?? r {
        T v → @ !A G { T v }
        F e → @ !A G { F ( fe # E e ) }
    }
}
