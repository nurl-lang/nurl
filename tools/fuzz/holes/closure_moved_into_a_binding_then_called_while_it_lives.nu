// closure_moved_into_a_binding_then_called_while_it_lives: `= keep f`, then `( f 1 )` and `( keep 1 )` while keep still holds the env: clean, and stays accepted (agora #835).
// Closed: after `= keep f` moves f's env into keep, f is a borrow of keep (a closure that does not own its env, class k): keep given a new value, or ending, ends f (gen_assign, agora #835).
// main (before this PR): accepted, clean.
// map: §7.6 | A2 | runs-clean | - | agora #835: a closure called while the binding its env moved into still holds it
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { : String s ( string_from `a heap string long enough for the heap buffer` ) ^ \ i x → i { ^ + + x n ( string_len s ) } }

@ main → i {
    : String tag ( string_from `a heap string long enough for the heap buffer` )
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) }
    = keep f
    ( nurl_println_int ( f 1 ) )
    ( nurl_println_int ( keep 1 ) )
    ^ 0
}
