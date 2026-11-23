// raw_string_pick_of_two_locals_by_a_callee_below_runs_clean: AGORA-867 — `^ ( pick a b k )`, a and b both `s` this frame owns, `pick` defined below handing back either: the result is copied whichever it lent, and both are released at the return
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a callee below that may lend either of two frame-owned raw strings: copied at the return, both released once
$ `stdlib/core/string.nu`

@ label i k → s {
    : s a ( nurl_str_cat `first fresh string, ` `long enough for a heap buffer` )
    : s b ( nurl_str_cat `second fresh string, ` `long enough for a heap buffer` )
    ^ ( pick a b k )
}

@ pick s x s y i k → s { ^ ? > k 0 x y }

@ main → i { ( nurl_println ( label 1 ) ) ( nurl_println ( label 0 ) ) ^ 0 }
