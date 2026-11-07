// string_maybe_lend_of_a_local_returned_in_an_enum_literal: agora #476 — `: String x ( maybe o k )`, the local o's value on one run and a fresh String on another, returned as an enum variant's payload `^ @ E { Word x }`
// Closed: the payload is copied where x lent o, o keeps and drops its own, and the return does not hand over again what the literal's field already settled (agora #476).
// main: LeakSanitizer reported o's buffer on the lent run (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #476: a maybe-lend of a local returned in an enum literal
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Word String Bare }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ run i k → E {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    ^ @ E { Word x }
}

@ main → i {
    : E a ( run 0 )
    : E b ( run 1 )
    ?? a { Word s → { ( nurl_println ( string_data s ) ) } Bare → {} }
    ?? b { Word s → { ( nurl_println ( string_data s ) ) } Bare → {} }
    ^ 0
}
