// Regression: a `~` while-loop condition that is a side-effecting call
// must be evaluated exactly (bodies + 1) times — once per iteration
// plus the final false test.
//
// gen_loop speculatively parses the condition (to tell a while loop
// from a complement expression used as a statement) and used to leave
// that speculative IR in the output, so the condition ran one extra
// time up front — a side-effecting condition then performed its first
// iteration's side effects with no matching body run, silently
// dropping one iteration. gen_loop now captures the speculative IR
// into the print buffer and discards it.

@ next_val * i st → i {
    : i v . st 0
    = . st 0 + v 1
    ^ v
}

@ main → i {
    // Side-effecting condition: next_val returns 0,1,2,3,4,… and bumps
    // the counter. `< … 4` is true for 0,1,2,3 → 4 bodies, then 4 → F.
    : *i st # *i ( nurl_alloc 8 )
    = . st 0 0
    : ~ i bodies 0
    ~ < ( next_val st ) 4 {
        = bodies + bodies 1
    }
    ( nurl_print `sideeffect_cond: bodies=` )
    ( nurl_print ( nurl_str_int bodies ) )
    ( nurl_print ` evals=` )
    ( nurl_print ( nurl_str_int . st 0 ) )
    ( nurl_print `\n` )

    // A plain pure-condition loop still works.
    : ~ i sum 0
    : ~ i k 0
    ~ < k 5 {
        = sum + sum k
        = k + k 1
    }
    ( nurl_print `pure_cond: sum=` )
    ( nurl_print ( nurl_str_int sum ) )
    ( nurl_print `\n` )

    // `~ expr` as a statement (complement, value discarded) — grammar
    // alternative 3 — must still parse.
    ~ 7
    ( nurl_print `complement_stmt: ok\n` )

    ( nurl_free # *v st )
    ^ 0
}
