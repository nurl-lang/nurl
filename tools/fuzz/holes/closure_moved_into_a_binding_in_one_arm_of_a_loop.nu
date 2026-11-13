// closure_moved_into_a_binding_in_one_arm_of_a_loop: `= keep f` in one round, `= keep ( mkn 3 )` in the next, `( f 1 )` at the top of every round (agora #835).
// Closed: after `= keep f` moves f's env into keep, f is a borrow of keep (a closure that does not own its env, class k): keep given a new value, or ending, ends f (gen_assign, agora #835).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #835: a closure moved into a binding in one round and that binding reassigned in another (UAF on main)
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { : String s ( string_from `a heap string long enough for the heap buffer` ) ^ \ i x → i { ^ + + x n ( string_len s ) } }

@ run ( @ i i ) g → i { ^ ( g 1 ) }

@ main → i {
    : String tag ( string_from `a heap string long enough for the heap buffer` )
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) }
    : ~ i k 0
    ~ < k 3 { ( nurl_println_int ( f 1 ) ) ? == k 0 { = keep f } { = keep ( mkn 3 ) } = k + k 1 }
    ( nurl_println_int ( keep 1 ) )
    ^ 0
}
