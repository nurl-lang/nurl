// string_maybe_lend_of_a_maybe_lend_returned_runs_clean: agora #457 — a binding that may be a lend of a local, `: String y ( maybe x m ) ^ y` with x itself a maybe-lend of a local: copied where it lent, never answered lent
// Closed: a binding lent by a bit is copied where it lent by whatever takes it, so its sources keep and drop their own (agora #457).
// main: ran clean (guard: a first cut of the fix answered "lent" per call and the caller read freed memory) (base 8a2afbc3).
// map: §7.2 | A2 | runs-clean | - | agora #457: a maybe-lend of a local `
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ run i k i m → String {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    : String y ( maybe x m )
    ^ y
}

@ main → i {
    : String a ( run 0 0 ) : String b ( run 1 0 ) : String c ( run 0 1 ) : String d ( run 1 1 )
    ( pr a ) ( pr b ) ( pr c ) ( pr d )
    ^ 0
}
