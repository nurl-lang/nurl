// arity_ternary_in_condition.nu — the n-ary arity check must not fire on
// a ternary that ENDS AN ENCLOSING CONDITION.
//
// `arity_strict_nary.nu` pins the trap: a `?` whose bare then/else were
// eaten by a short `&`, with the real blocks left dangling after it. The
// signal it fires on is "a `{` follows a completed ternary", and that
// signal has a second, entirely correct source:
//
//     ~ & ok < i0 ? >= stopat 0 stopat N { body }
//
// Here the ternary is part of the LOOP's condition and the `{` opens the
// loop body. Nothing is stray, there is no rewrite that avoids the
// diagnostic, and it was a hard error by default — so a correct program
// could not be compiled at all. `packages/lingbot-map` had exactly this
// shape and could not be installed from the registry.
//
// The check now stays silent while a condition is being parsed
// (`g_cond_depth`), and fires as before everywhere else. Inside a
// condition the two cases are genuinely indistinguishable — the `{` is
// the enclosing construct's block either way — so silence is the only
// answer that keeps correct code compiling.
//
// Expected: COMPILE OK, EXIT 0, and the loops actually run.

@ count_to i stopat i cap → i {
    : ~ i n 0
    : b ok T
    // The loop condition ends in a ternary; `{` is the body.
    ~ & ok < n ? >= stopat 0 stopat cap {
        = n + n 1
    }
    ^ n
}

// The same shape in an `?` condition rather than a `~` one: the `{`
// opens the then-block.
@ pick_bounded i stopat i cap → i {
    ? > ? >= stopat 0 stopat cap 2 {
        ^ 1
    } {
        ^ 0
    }
}

@ main → i {
    // stopat >= 0 → the ternary yields stopat (3), so the loop runs 3×.
    ( nurl_print ( nurl_str_int ( count_to 3 9 ) ) ) ( nurl_print `\n` )
    // stopat < 0 → the ternary yields cap (5), so the loop runs 5×.
    ( nurl_print ( nurl_str_int ( count_to -1 5 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( pick_bounded 3 9 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( pick_bounded -1 1 ) ) ) ( nurl_print `\n` )
    ^ 0
}
