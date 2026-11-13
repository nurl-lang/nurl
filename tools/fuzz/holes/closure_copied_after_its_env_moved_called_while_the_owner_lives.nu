// closure_copied_after_its_env_moved_called_while_the_owner_lives: `= keep f  : ( @ i i ) g f`, then `( g 1 )` and `( keep 1 )` while keep still holds the env (agora #835).
// Closed: after `= keep f` moves f's env into keep, f is lent from keep (mem_clo_mark_lent) and a borrow of it in the walk: `: g f` is a second name of keep's env, a borrow of f, and ends with keep (agora #835).
// main (before this PR): accepted, clean.
// map: §7.6 | A2 | runs-clean | - | agora #835: a copy of a closure whose env moved, called while the owner holds it
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { ^ \ i x → i { ^ + x n } }

@ main → i {
    : String tag ( string_from `tag string long enough for a heap buffer` )
    : ~ ( @ i i ) keep ( mkn 1 )
    : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) } = keep f : ( @ i i ) g f
    ( nurl_println_int + ( g 1 ) ( keep 1 ) )
    ^ 0
}
