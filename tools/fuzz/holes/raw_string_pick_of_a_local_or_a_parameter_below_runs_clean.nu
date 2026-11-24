// raw_string_pick_of_a_local_or_a_parameter_below_runs_clean: AGORA-867 — `^ ( pick a p k )`, a an `s` this frame owns, p a borrowed parameter, `pick` defined below handing back either: the result is the caller's own on every run (a copy where pick lent), a is released at the return, p stays the caller's
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a callee below that may lend a frame-owned raw string or a parameter: copied at the return on every run, nothing freed twice or leaked
$ `stdlib/core/string.nu`

@ label s p i k → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( pick a p k )
}

@ pick s a s b i k → s { ^ ? > k 0 a b }

@ main → i {
    : s p ( nurl_str_cat `the caller's own string, ` `kept alive past the call` )
    : s x ( label p 1 )
    : s y ( label p 0 )
    ( nurl_println x )
    ( nurl_println y )
    ( nurl_println p )
    ^ 0
}
