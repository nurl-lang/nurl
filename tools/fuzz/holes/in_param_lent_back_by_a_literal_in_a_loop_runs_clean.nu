// in_param_lent_back_by_a_literal_in_a_loop_runs_clean: `^ @ K { p j }` inside a loop, and `^ @ K { p 0 }` after it, given a local
// The reference checker's per-literal records are this evaluation's: a loop's second round no longer reads `p` as named twice (review of github#2280).
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-995: a literal in a loop names its parameter once per round
$ `stdlib/core/string.nu`

: K { String a i n }

@ wrap String p i k → K {
    : ~ i j 0
    ~ < j k {
        ? == j 2 { ^ @ K { p j } } {}
        = j + j 1
    }
    ^ @ K { p 0 }
}

@ esc i k → K {
    : String x ( string_from `a local value long enough for the heap` )
    ^ ( wrap x k )
}

@ main → i {
    : K a ( esc 5 )
    : K b ( esc 1 )
    ( nurl_println ( string_data . a a ) )
    ( nurl_println ( string_data . b a ) )
    ^ 0
}
