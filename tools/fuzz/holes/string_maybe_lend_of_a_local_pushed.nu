// string_maybe_lend_of_a_local_pushed: agora #457 — `: String x ( maybe o k )`, which is the local o's value on one run and a fresh String on another, pushed into a Vec (`( vec_push [String] out x )`)
// Closed: a binding whose lentness is a bit (a call that answers per call whether it lent, `@slot`) never hands its sources' values over: it is its own value where the bit says so and a copy where it lent, so o keeps and drops its own (agora #457).
// main: LeakSanitizer reported o's or x's buffer (base 8a2afbc3).
// map: §7.2 | A2 | runs-clean | - | agora #457: a maybe-lend of a local pushed into a Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ run i k → ( Vec String ) {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    : ~ ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out x )
    ^ out
}

@ main → i {
    : ( Vec String ) a ( run 0 )
    : ( Vec String ) b ( run 1 )
    ( nurl_println ( string_data ( vec_at [String] a 0 ) ) ) ( nurl_println ( string_data ( vec_at [String] b 0 ) ) )
    ^ 0
}
