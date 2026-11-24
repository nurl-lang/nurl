// raw_string_handed_back_by_a_generic_callee_below_runs_clean: AGORA-867 — `^ ( first [i] a 3 )`, a an `s` this frame owns, `first` a generic defined below handing back its string argument: an instance is compiled after its caller wherever the generic is written, so this is the callee-below answer: copied at the return
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a generic callee below that hands back a frame-owned raw string: copied at the return
$ `stdlib/core/string.nu`

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( first [i] a 3 )
}

@ first [T] s x T y → s { ^ x }

@ main → i { ( nurl_println ( label ) ) ^ 0 }
