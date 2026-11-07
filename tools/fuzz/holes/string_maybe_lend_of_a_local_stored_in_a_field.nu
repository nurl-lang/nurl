// string_maybe_lend_of_a_local_stored_in_a_field: agora #476 — `: String x ( maybe o k )`, the local o's value on one run and a fresh String on another, stored into a local struct's field (`= . h s x`) and the struct returned
// Closed: the store copies x where it lent o, and o keeps and drops its own value: a binding whose lentness is a bit hands nothing over by identity (agora #476).
// main: LeakSanitizer reported o's buffer on the lent run (base 5dbcdf2a).
// map: §7.2 | A2 | runs-clean | - | agora #476: a maybe-lend of a local stored in a field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ run i k → H {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    : ~ H h @ H { ( string_from `the holder's first value, heap sized` ) 1 }
    = . h s x
    ^ h
}

@ main → i {
    : H a ( run 0 )
    : H b ( run 1 )
    ( nurl_println ( string_data . a s ) ) ( nurl_println ( string_data . b s ) )
    ^ 0
}
