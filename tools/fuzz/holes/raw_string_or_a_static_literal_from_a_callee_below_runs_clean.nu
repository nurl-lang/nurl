// raw_string_or_a_static_literal_from_a_callee_below_runs_clean: AGORA-867 — `^ ( or_lit a k )`, a an `s` this frame owns, `or_lit` defined below handing back a or a static literal: where it may lend a, the result is copied on every run, the literal's copy too, and nothing static is ever freed
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a callee below that hands back a frame-owned raw string or a static literal: copied at the return, the literal never freed
$ `stdlib/core/string.nu`

@ label i k → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( or_lit a k )
}

@ or_lit s x i k → s { ^ ? > k 0 x `a static literal` }

@ main → i { ( nurl_println ( label 1 ) ) ( nurl_println ( label 0 ) ) ^ 0 }
