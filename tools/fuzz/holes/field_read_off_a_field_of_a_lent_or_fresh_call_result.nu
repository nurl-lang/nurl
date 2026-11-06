// field_read_off_a_field_of_a_lent_or_fresh_call_result: agora #474 — a read two levels off a call's result that the call only LENT (`. . ( peekb b2 ) v a`, a getter of its parameter's field) must release nothing the owner still holds; one the call lends on some calls only (`( pick bx k )` hands back its parameter, or a fresh Box1) must release the fresh one, and only it.
// Closed: the outer read drops the struct the inner read took out of the call's result exactly when the call handed its result over (the call's own per-call answer); the owner's String is read after every lent read.
// main (before this PR): LeakSanitizer, pick's fresh Box1 per round on the fresh path (the lent reads ran clean).
// map: §7.1 | A2 | runs-clean | - | agora #474: a field read off a field of a lent or maybe-lent call result releases what the call handed over, and nothing the owner holds
$ `stdlib/core/string.nu`

: Pair { String a i b }
: Box1 { Pair v }
: Box2 { Box1 w }

@ boxit Pair p → Box1 { ^ @ Box1 { p } }

@ mkpair i k → Pair { ^ @ Pair { ( string_from `a string long enough to be on the heap, and then some more bytes` ) k } }

@ box2 i k → Box2 { ^ @ Box2 { ( boxit ( mkpair k ) ) } }

@ peekb Box2 b → Box1 { ^ . b w }

@ pick Box1 a i k → Box1 { ? > k 4 { ^ a } { ^ ( boxit ( mkpair k ) ) } }

@ once i k → i {
    : Box2 b2 ( box2 k )
    : i n . . ( peekb b2 ) v b
    : String s . . ( peekb b2 ) v a
    : Box1 bx ( boxit ( mkpair 7 ) )
    : i m . . ( pick bx k ) v b
    : String s2 . . ( pick bx k ) v a
    ^ + + + + + n ( string_len s ) ( string_len . . . b2 w v a ) m ( string_len s2 ) ( string_len . . bx v a )
}

@ main → i {
    : ~ i t 0
    : ~ i k 0
    ~ < k 10 { = t + t ( once k ) = k + k 1 }
    ( nurl_println_int t )
    ^ 0
}
