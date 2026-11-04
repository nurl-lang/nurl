// string_maybe_lend_of_a_local_kept_by_rc_new: agora #457 — a binding that may be a lend of a local, kept by `rc_new` (a keeper through a raw pointer: its sink flag, not a store)
// Closed: a binding lent by a bit is copied where it lent by whatever takes it, so its sources keep and drop their own (agora #457).
// main: LeakSanitizer reported o's buffer on the fresh run (base 8a2afbc3).
// map: §7.2 | A2 | runs-clean | - | agora #457: a maybe-lend of a local kept by `rc_new`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: H { String s i n }

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ run i k → ( Rc String ) {
    : String o ( string_from `a local value long enough for the heap` )
    : String x ( maybe o k )
    ^ ( rc_new [String] x )
}

@ main → i {
    : ( Rc String ) a ( run 0 ) : ( Rc String ) b ( run 1 )
    ( pr ( rc_get [String] a ) ) ( pr ( rc_get [String] b ) )
    ^ 0
}
