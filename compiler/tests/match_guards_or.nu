// match_guards_or.nu — acceptance test for `??` match guards and
// or-patterns added to gen_match.
//
//   * Guard:  `Pattern payloads ? <cond> → body` — the arm fires only
//     when <cond> (evaluated after payload binding) is true; otherwise
//     control falls through to the next arm. A guarded arm does not
//     satisfy exhaustiveness for its variant (a catch-all is still
//     required).
//   * Or-pattern:  `A | B | C → body` — several tag-only variants share
//     one body.
//
// Determinism: pure, no clock/socket/env. ASan-clean.


: | Dir { North South East West Up Down }

// Guards: same variant T appears guarded several times + once bare.
@ classify ?i o → s {
    ^ ?? o {
        T v ? > v 100 → `big`
        T v ? > v 0 → `small-pos`
        T v → `non-pos`
        F → `none`
    }
}

// Or-patterns: tag-only variants grouped.
@ axis i d → s {
    ^ ?? # Dir d {
        North | South → `vertical`
        East | West → `horizontal`
        Up | Down → `depth`
    }
}

@ main → i {
    ( nurl_print `g500=` ) ( nurl_print ( classify @ ?i { T 500 } ) ) ( nurl_print `\n` )
    ( nurl_print `g50=` ) ( nurl_print ( classify @ ?i { T 50 } ) ) ( nurl_print `\n` )
    ( nurl_print `g-5=` ) ( nurl_print ( classify @ ?i { T -5 } ) ) ( nurl_print `\n` )
    ( nurl_print `g0=` ) ( nurl_print ( classify @ ?i { T 0 } ) ) ( nurl_print `\n` )
    ( nurl_print `gNone=` ) ( nurl_print ( classify @ ?i { F 0 } ) ) ( nurl_print `\n` )

    ( nurl_print `North=` ) ( nurl_print ( axis # i # Dir North ) ) ( nurl_print `\n` )
    ( nurl_print `West=` ) ( nurl_print ( axis # i # Dir West ) ) ( nurl_print `\n` )
    ( nurl_print `Up=` ) ( nurl_print ( axis # i # Dir Up ) ) ( nurl_print `\n` )
    ( nurl_print `South=` ) ( nurl_print ( axis # i # Dir South ) ) ( nurl_print `\n` )
    ^ 0
}
