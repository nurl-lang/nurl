// closure_read_from_a_vec_called_after_a_clearing_call_in_the_same_statement_runs_clean:
// `+ ( cz fs ) ( f 10 )`: the walk records a statement's call effects after
// its reads, so it does not order the clear before the call of f. A call of
// a lent binding while a call's effects wait makes it copy: clean.
// map: §8.4 | A2 | runs-clean | - | a closure read out of a local Vec, called in the same statement after a call that clears the Vec: the binding copies, the statement's call effects are recorded after its reads (agora #552).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

@ cz ( Vec ( @ i i ) ) v → i { ( vec_clear [( @ i i )] v ) ^ 0 }

@ main → i { : ( Vec ( @ i i ) ) fs ( fill ) : ( @ i i ) f ( vec_at [( @ i i )] fs 1 ) ( nurl_println_int + ( cz fs ) ( f 10 ) ) ( vec_free [( @ i i )] fs ) ^ 0 }
