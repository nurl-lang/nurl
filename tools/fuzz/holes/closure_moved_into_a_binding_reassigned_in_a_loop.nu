// closure_moved_into_a_binding_reassigned_in_a_loop: `= keep f`, then a loop that calls f and gives keep a new value: the second round called the freed env (agora #835).
// Closed: after `= keep f` moves f's env into keep, f is a borrow of keep (a closure that does not own its env, class k): keep given a new value, or ending, ends f (gen_assign, agora #835).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #835: a closure called in a loop that reassigns the binding its env moved into (UAF on main)
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { : String s ( string_from `a heap string long enough for the heap buffer` ) ^ \ i x → i { ^ + + x n ( string_len s ) } }

@ run ( @ i i ) g → i { ^ ( g 1 ) }

@ main → i {
    : String tag ( string_from `a heap string long enough for the heap buffer` )
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) }
    = keep f
    : ~ i k 0
    ~ < k 2 { ( nurl_println_int ( f 1 ) ) = keep ( mkn k ) = k + k 1 }
    ^ 0
}
