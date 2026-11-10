// closure_read_from_a_vec_passed_beside_it_to_a_clearing_callee_runs_clean:
// `( both fs f )`, f read out of fs, both clearing fs and then calling f.
// A lent f would run on a freed env (claude-formal's review of #552). A
// binding read as a value copies at its read: clean.
// map: §8.4 | A2 | runs-clean | - | a closure read out of a local Vec, passed in the same call as that Vec to a callee that clears it then calls the closure: the binding copies at its read, the walk does not see the clear before the call (agora #552).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

@ both ( Vec ( @ i i ) ) v ( @ i i ) g → i { ( vec_clear [( @ i i )] v ) ^ ( g 1 ) }

@ main → i { : ( Vec ( @ i i ) ) fs ( fill ) : ( @ i i ) f ( vec_at [( @ i i )] fs 1 ) ( nurl_println_int ( both fs f ) ) ( vec_free [( @ i i )] fs ) ^ 0 }
