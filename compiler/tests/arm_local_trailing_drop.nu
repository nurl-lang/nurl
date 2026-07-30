// Test: arm-local TRAILING-declaration drop (critic.md A4, the
// "arm-local fall-through bindings" residual). The pre-existing
// arm_local_drop.nu locks arms where a print FOLLOWS the decl; when
// the `:` declaration was the arm's LAST statement, gen_let_or_struct
// left the RHS type in last_type, the arm looked value-producing, and
// gen_cond/gen_match (a) suppressed the Phase 2D fall-through drop —
// leaking the binding — and (b) emitted a bogus phi over the
// discarded decl value. Fixed in gen_stmt: a `:` declaration
// statement now publishes `void`.
//
// Also locks the `= outer x` ownership transfer: an arm-local owned
// string assigned to an outer mutable must NOT be freed by the arm's
// fall-through drop (the buffer lives on through `outer`); its drop
// obligation is cancelled, and `outer` stays readable after the match.
//
// The frees themselves are observable only under ASan/LSan
// (run_san_tests.sh); this golden locks compile + run + output.

$ `stdlib/core/string.nu`

@ main → i {
    // ?-arm whose LAST statement is an owned-string decl.
    ? 1
    { : s t1 ( nurl_str_cat `if-` `trailing` )
    }
    {}

    // ??-arm whose LAST statement is an owned-string decl.
    : ?i opt @ ?i { T 7 }
    ?? opt {
        T v → {
            : s t2 ( nurl_str_cat `match-` `trailing` )
        }
        F → {}
    }

    // Loop body whose LAST statement is an owned-string decl.
    : ~ i j 0
    ~ < j 2 {
        = j + j 1
        : s t3 ( nurl_str_cat `loop-` `trailing` )
    }

    // Escape via outer mutable: the arm-local's buffer must survive
    // the arm's fall-through drop. `kept` is a mutable binding with a
    // literal initialiser, so it owns a heap buffer from birth and is
    // auto-dropped at scope exit; `= kept esc` stores a COPY (the old
    // cancel-the-source's-drop transfer died with the arm's symtab
    // pop), so esc keeps its own arm drop and kept its own scope-exit
    // one. No manual free — adding one would double-free under the
    // sanitizer run, which is exactly the single-ownership lock.
    : ~ s kept ``
    ? 1
    { : s esc ( nurl_str_cat `escaped-` `value` )
        = kept esc
        ( nurl_print `arm done\n` )
    }
    {}
    ( nurl_print kept ) ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
