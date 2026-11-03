// string_maybe_lend_of_a_local_kept_by_rc_set: agora #457 — a binding that may be a lend of a local, kept by `rc_set` into a parameter's Rc
// Closed: a binding lent by a bit is copied where it lent by whatever takes it, so its sources keep and drop their own (agora #457).
// main: LeakSanitizer reported o's buffer on the fresh run (base 8a2afbc3).
// map: §7.2 | A2 | runs-clean | - | agora #457: a maybe-lend of a local kept by `rc_set` into a parameter's Rc
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ run ( Rc String ) r i k → v {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    ( rc_set [String] r x )
}

@ main → i {
    : ( Rc String ) r ( rc_new [String] ( string_from `start long enough for the heap` ) )
    ( run r 0 ) ( pr ( rc_get [String] r ) )
    ( run r 1 ) ( pr ( rc_get [String] r ) )
    ^ 0
}
