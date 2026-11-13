// closure_moved_into_a_binding_then_that_binding_reassigned: `= keep f` moves f's env into keep; `= keep ( mkn 2 )` released it; `( f 1 )` ran on the freed env (agora #835).
// Closed: after `= keep f` moves f's env into keep, f is a borrow of keep (a closure that does not own its env, class k): keep given a new value, or ending, ends f (gen_assign, agora #835).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #835: a closure called after the binding its env moved into was reassigned (UAF on main)
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { : String s ( string_from `a heap string long enough for the heap buffer` ) ^ \ i x → i { ^ + + x n ( string_len s ) } }

@ main → i {
    : String tag ( string_from `a heap string long enough for the heap buffer` )
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) }
    = keep f
    = keep ( mkn 2 )
    ( nurl_println_int ( f 1 ) )
    ^ 0
}
