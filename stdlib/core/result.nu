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
//   ( res_map        [T U E] r f )         → !U E  f: T → U; Err forwards
//   ( res_and_then   [T U E] r f )         → !U E  f: T → !U E; Err forwards
//   ( res_map_err    [T E G] r fe )        → !T G  fe: E → G; Ok forwards
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
