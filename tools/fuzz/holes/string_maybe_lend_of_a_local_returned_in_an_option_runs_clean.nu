// string_maybe_lend_of_a_local_returned_in_an_option_runs_clean: agora #457 guard — `: String x ( maybe o k )` returned as `^ @ ?String { T x }`: a returned wrap copies x where it lent o, a local, and answers owned
// Guard: ran clean on main (base 8a2afbc3); a first cut of #457's fix that kept o without copying here read freed memory.
// main: ran clean.
// map: §7.2 | A2 | runs-clean | - | agora #457 guard: a maybe-lend of a local returned in an option
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ run i k → ?String {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    ^ @ ?String { T x }
}

@ main → i {
    : ?String a ( run 0 )
    ?? a { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    : ?String b ( run 1 )
    ^ 0
}
