// string_maybe_lend_of_a_local_returned_in_a_result: agora #531 — `: String x ( maybe o k )` returned as `^ @ !String String { T x }`: on the runs maybe lent the local o, the return handed o's value over by identity yet answered "lent", so the caller dropped nothing and o's buffer leaked
// main: leaked (LSan with use_stacks=0:use_registers=0, or clang 23's default LSan).
// map: §7.2 | A2 | runs-clean | - | agora #531: a maybe-lend of a local returned in a result answers owned by identity
$ `stdlib/core/string.nu`

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ run i k → !String String {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    ^ @ !String String { T x }
}

@ main → i {
    : !String String a ( run 0 )
    ?? a { T s → { ( nurl_println ( string_data s ) ) } F e → {} }
    : !String String b ( run 1 )
    ?? b { T s → { ( nurl_println ( string_data s ) ) } F e → {} }
    ^ 0
}
