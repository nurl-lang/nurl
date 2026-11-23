// raw_string_maker_below_hands_back_fresh_text_runs_clean: AGORA-867 — `^ ( shout a )`, a an `s` this frame owns, `shout` defined below building a fresh string from it: what shout hands over is the caller's as it stands (no second copy, no leak), and a is released at the return
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a callee below that hands back a fresh string built from a frame-owned raw string: its result goes to the caller as its own, nothing leaked
$ `stdlib/core/string.nu`

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( shout a )
}

@ shout s x → s { ^ ( nurl_str_cat x `!` ) }

@ main → i {
    ( nurl_println ( label ) )
    ( nurl_println ( label ) )
    ^ 0
}
