// closure_moved_into_a_binding_then_passed_while_it_lives: `= keep f`, then f handed to a function while keep still holds the env (agora #835).
// Closed: after `= keep f` moves f's env into keep, f is a borrow of keep (a closure that does not own its env, class k): keep given a new value, or ending, ends f (gen_assign, agora #835).
// main (before this PR): accepted, clean.
// map: §7.6 | A2 | runs-clean | - | agora #835: a closure passed on while the binding its env moved into still holds it
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { : String s ( string_from `a heap string long enough for the heap buffer` ) ^ \ i x → i { ^ + + x n ( string_len s ) } }

@ run ( @ i i ) g → i { ^ ( g 1 ) }

@ main → i {
    : String tag ( string_from `a heap string long enough for the heap buffer` )
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) }
    = keep f
    ( nurl_println_int ( run f ) )
    ( nurl_println_int ( keep 2 ) )
    ^ 0
}
