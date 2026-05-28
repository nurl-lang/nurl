// should_warn_caret_xor.nu — `^` vs `^^` confusion warning.
//
// `^ a b` looks like XOR but `^` is the return operator (arity 1),
// so this parses as `^ a` and `b` is left over as a separate (dead)
// expression statement. The user almost certainly meant `^^ a b`
// (two adjacent carets, no space — the native XOR operator).
//
// Post-fix: the compiler emits a non-fatal `warning:` line at the
// trailing operand. Compile + link + run still succeed (this is a
// SOFT diagnostic, not a compile error) so legacy code keeps
// building. The WARNINGS baseline block in correct.txt captures
// the exact diagnostic text.
//
// Three positive sites + one negative control (`fine` — a single
// expression `^ + a b` consumes both operands via `+`, no warning).

@ xor_confused_in_binding → i {
    : i a 5
    : i b 3
    : i x ^ a b     // ← warns: `^` returns `a`, `b` is dead
    ^ x
}

@ xor_confused_at_stmt i a i b → i {
    ^ a b           // ← warns: `^` returns `a`, `b` is dead
}

@ xor_confused_with_lit i a → i {
    ^ a 42          // ← warns: `^` returns `a`, the `42` is dead
}

@ fine i a i b → i {
    ^ + a b         // OK — `+ a b` is one expression, `^` returns it
}

@ main → i {
    // The three "warned" fns still compile and run; they just return
    // the first operand because `^ X Y` is `^ X`. Exercise each so the
    // baseline pins the runtime semantics too.
    ( nurl_print `binding=` )
    ( nurl_print ( nurl_str_int ( xor_confused_in_binding ) ) )
    ( nurl_print `\n` )
    ( nurl_print `stmt=` )
    ( nurl_print ( nurl_str_int ( xor_confused_at_stmt 5 3 ) ) )
    ( nurl_print `\n` )
    ( nurl_print `lit=` )
    ( nurl_print ( nurl_str_int ( xor_confused_with_lit 5 ) ) )
    ( nurl_print `\n` )
    ( nurl_print `fine=` )
    ( nurl_print ( nurl_str_int ( fine 5 3 ) ) )
    ( nurl_print `\n` )
    ^ 0
}
