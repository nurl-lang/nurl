// string_maybe_lend_of_a_local_captured_by_a_returned_closure: agora #457 — `: String x ( maybe o k )`, which is the local o's value on one run and a fresh String on another, captured by a returned closure
// Closed: a binding whose lentness is a bit (a call that answers per call whether it lent, `@slot`) never hands its sources' values over: it is its own value where the bit says so and a copy where it lent, so o keeps and drops its own (agora #457).
// main: LeakSanitizer reported o's or x's buffer (base 8a2afbc3).
// map: §7.2 | A2 | runs-clean | - | agora #457: a maybe-lend of a local captured by a returned closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ run i k → ( @ i ) {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    ^ \ → i { ^ ( string_len x ) }
}

@ main → i {
    : ( @ i ) a ( run 0 )
    : ( @ i ) b ( run 1 )
    ( nurl_println_int ( a ) ) ( nurl_println_int ( b ) )
    ^ 0
}
