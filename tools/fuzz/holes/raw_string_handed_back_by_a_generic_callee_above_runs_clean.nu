// raw_string_handed_back_by_a_generic_callee_above_runs_clean: AGORA-867 — `^ ( first [i] a 3 )` with the generic `first` defined above: its instance is still compiled after its caller, so the answer is the same copy as for one below (refused before AGORA-867, in either order)
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a generic callee defined above that hands back a frame-owned raw string: copied at the return, as for one below
$ `stdlib/core/string.nu`

@ first [T] s x T y → s { ^ x }

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( first [i] a 3 )
}

@ main → i { ( nurl_println ( label ) ) ^ 0 }
