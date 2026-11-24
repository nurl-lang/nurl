// raw_string_parameter_lent_back_past_a_local_by_a_callee_below_runs_clean: AGORA-867 — `^ ( second a p )`, a an `s` this frame owns, `second` defined below handing back its other argument: no copy is made (second lends no argument this frame owns), the result stays a lend of p, which the caller keeps alive and releases once
// map: §2.10 | A2 | runs-clean | - | AGORA-867 guard: a callee below that lends only a parameter past a frame-owned raw string: the result stays the caller's lend of its own argument
$ `stdlib/core/string.nu`

@ label s p → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( second a p )
}

@ second s a s b → s { ^ b }

@ main → i {
    : s p ( nurl_str_cat `the caller's own string, ` `kept alive past the call` )
    : s r ( label p )
    ( nurl_println r )
    ( nurl_println p )
    ^ 0
}
