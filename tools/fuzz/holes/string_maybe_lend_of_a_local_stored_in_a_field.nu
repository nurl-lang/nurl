// string_maybe_lend_of_a_local_stored_in_a_field: agora #457 — `: String x ( maybe o k )`, which is the local o's value on one run and a fresh String on another, stored into a field (`= . h s x`)
// Closed: a binding whose lentness is a bit (a call that answers per call whether it lent, `@slot`) never hands its sources' values over: it is its own value where the bit says so and a copy where it lent, so o keeps and drops its own (agora #457).
// main: LeakSanitizer reported o's or x's buffer (base 8a2afbc3).
// map: §7.2 | A2 | runs-clean | - | agora #457: a maybe-lend of a local stored into a field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ run i k → H {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    : ~ H h @ H { ( string_from `h` ) 1 }
    = . h s x
    ^ h
}

@ main → i {
    : H a ( run 0 )
    : H b ( run 1 )
    ( nurl_println ( string_data . a s ) ) ( nurl_println ( string_data . b s ) )
    ^ 0
}
