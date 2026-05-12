// stdlib/core/result.nu — combinators for !T E
//
// NURL's `!T E` lowers to { i1 tag, i64 payload } — error values larger than
// i64 are coerced (strings via ptrtoint, enums via extractvalue of the tag).
// Constructor `@ ! T E { T v }` → Ok(v); `@ ! T E { F e }` → Err(e). Field
// access `. r 0` → tag, `. r 1` → payload (always i64). `\` propagates Err
// upward and requires matching error types in the enclosing function.
//
//   ( res_is_ok      [T E]   r )           → b     true iff r = Ok
//   ( res_is_err     [T E]   r )           → b     true iff r = Err
//   ( res_unwrap_or  [T E]   r default )   → T     Ok payload or default
//   ( res_map        [T U E] r f )         → !U E  f: T → U; Err forwards
//   ( res_and_then   [T U E] r f )         → !U E  f: T → !U E; Err forwards
//   ( res_map_err    [T E G] r fe )        → !T G  fe: E → G; Ok forwards
//
// Forwarding note: the Err branch is rebuilt via `@ ! U E { F . r 1 }`. Since
// `!T E` and `!U E` share the same `{ i1, i64 }` layout and the error payload
// is stored as i64, `. r 1` yields the raw i64 which feeds straight back into
// a new constructor without re-coercion.
//
// `res_map_err` binds the err in the F arm as i64 (opt/res-bool fallback) and
// casts it back to E via `# E e` before calling `fe`. This works for E ∈
// { i, s, b, enum-types } because their storage representation round-trips
// through i64 unchanged. Enum re-construction is handled by the `#` cast
// path in gen_cast.
//
// Type-variable names avoid `T` and `F` because those lex as bool literals
// and would be rewritten by the generic source substitution — A/B for value
// types, E/G for error types.

@ res_is_ok [A E] ! A E r → b {
  ^ ?? r { T → T  F → F }
}

@ res_is_err [A E] ! A E r → b {
  ^ ?? r { T → F  F → T }
}

@ res_unwrap_or [A E] ! A E r A default → A {
  ^ ?? r { T v → v  F → default }
}

@ res_map [A B E] ! A E r (@ B A) f → ! B E {
  ^ ?? r {
    T v → @ ! B E { T ( f v ) }
    F   → @ ! B E { F . r 1 }
  }
}

@ res_and_then [A B E] ! A E r (@ ! B E A) f → ! B E {
  ^ ?? r {
    T v → ( f v )
    F   → @ ! B E { F . r 1 }
  }
}

@ res_map_err [A E G] ! A E r (@ G E) fe → ! A G {
  ^ ?? r {
    T v → @ ! A G { T v }
    F e → @ ! A G { F ( fe # E e ) }
  }
}
