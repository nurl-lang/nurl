// string_maybe_lend_of_a_local_assigned_then_returned: agora #476 — `: String x ( maybe o k )`, the local o's value on one run and a fresh String on another, given to another binding (`= y x`) and that one returned
// Closed: the return copies y where it holds a lend of o, and o keeps and drops its own: a cursor's sources are not handed over where the route copied (agora #476).
// main: LeakSanitizer reported o's buffer on the lent run (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #476: a maybe-lend of a local assigned to another binding, returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ run i k → String {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    : ~ String y ( string_from `the first value of y, heap sized` )
    = y x
    ^ y
}

@ main → i {
    : String a ( run 0 )
    : String b ( run 1 )
    ( nurl_println ( string_data a ) ) ( nurl_println ( string_data b ) )
    ^ 0
}
