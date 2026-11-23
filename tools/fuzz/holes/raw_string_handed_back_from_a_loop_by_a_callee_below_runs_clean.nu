// raw_string_handed_back_from_a_loop_by_a_callee_below_runs_clean: AGORA-867 — `? == k 2 { ^ ( same a ) }` inside a loop, a an `s` made in the loop body, `same` defined below: the copy is made on the run that returns, and a is released on every other iteration
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a return inside a loop body through a callee below that lends a raw string made in the body: copied at the return
$ `stdlib/core/string.nu`

@ label i n → s {
    : ~ i k 0
    ~ < k n {
        : s a ( nurl_str_cat `a fresh string in a loop, ` `long enough for a heap buffer` )
        ? == k 2 { ^ ( same a ) } {}
        = k + k 1
    }
    ^ `none`
}

@ same s x → s { ^ x }

@ main → i { ( nurl_println ( label 5 ) ) ( nurl_println ( label 1 ) ) ^ 0 }
