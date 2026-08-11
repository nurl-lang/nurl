// cond_str_literal_join.nu — `?`-joins over string values, every
// ownedness mix, used in ARGUMENT position (regression for the
// literal-arm copy leak, 2026-08-11).
//
// A string-LITERAL ternary arm used to be strdup'd eagerly so a join
// beside an owning sibling would be uniformly owned — but the copy had
// no consumer in argument position and leaked once per EVALUATION
// (~10 MB/step of a 4B LoRA finetune: grad's per-launch kernel-name
// prefix `( string_from ? == dtype 2 `gpm_` `gpf_` )`). Now:
//
//   lit / lit    → no copies at all; the join is uniformly borrowed
//   lit / owned  → repaired AT THE JOIN (copy the picked pointer, free
//                  the owned original; free(null) no-op on the lit path)
//   owned / lit  → the literal side copies eagerly (the then-arm's
//                  ownedness is already known when the else-arm emits)
//
// The checks below run every mix through BOTH paths and print the
// selected values — a wrong select polarity, a freed static, or a
// double free all change the output or crash.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

// lit/lit in argument position: zero allocations, both paths.
@ ll i dt → String {
    : String o ( string_from ? == dt 2 `gpm_` `gpf_` )
    ^ o
}

// lit then-arm, OWNED else-arm (join-block repair).
@ lo i dt s a s b2 → String {
    : String o ( string_from ? == dt 2 `lit_` ( nurl_str_cat a b2 ) )
    ^ o
}

// OWNED then-arm, lit else-arm (eager else copy).
@ ol i dt s a s b2 → String {
    : String o ( string_from ? == dt 2 ( nurl_str_cat a b2 ) `lit_` )
    ^ o
}

// lit/lit bound through a tracked binding, then used — the binding form.
@ bind_form i dt → String {
    : ~ s pre `gpf_`
    ? == dt 2 { = pre `gpm_` } {}
    : String o ( string_from pre )
    ( string_push_str o `tail` )
    ^ o
}

@ pr String x → v {
    ( nurl_println ( string_data x ) )
    ( string_free x )
}

@ main → i {
    ( pr ( ll 2 ) )
    ( pr ( ll 1 ) )
    ( pr ( lo 2 `aa` `bb` ) )
    ( pr ( lo 1 `aa` `bb` ) )
    ( pr ( ol 2 `aa` `bb` ) )
    ( pr ( ol 1 `aa` `bb` ) )
    ( pr ( bind_form 2 ) )
    ( pr ( bind_form 1 ) )
    ^ 0
}
