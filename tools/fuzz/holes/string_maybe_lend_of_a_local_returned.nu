// string_maybe_lend_of_a_local_returned: agora #476 — `: String x ( maybe o k )`, which is the local o's value on one run and a fresh String on another, returned bare
// Closed: the return copies x where it lent o, and o keeps and drops its own value: a binding whose lentness is a bit hands nothing over by identity (agora #476).
// main: LeakSanitizer reported o's buffer on the lent run (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #476: a maybe-lend of a local returned bare
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ run i k → String {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    ^ x
}

@ main → i {
    : String a ( run 0 )
    : String b ( run 1 )
    ( nurl_println ( string_data a ) ) ( nurl_println ( string_data b ) )
    ^ 0
}
