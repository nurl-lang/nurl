// match_of_an_option_of_a_fresh_s_binding_returned: agora #478 — `^ ?? o { T v → v … }`, o = `@ ?s { T a }`, a an `s` given a fresh string: the payload is a's buffer, released at the return
// main ebc1b407: rejected already (the payload is a's storage); kept as the fourth spelling of agora #478.
// map: §2.10 | A2 | rejected | - | agora #478: `^ ?? o { T v → v … }`, o = `@ ?s { T a }`, a an `s` given a fresh string: the payload is a's buffer, released at the return
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    : ?s o @ ?s { T a }
    ^ ?? o { T v → v F → `none` }
}

@ main → i { ( nurl_println ( label ) ) ^ 0 }
