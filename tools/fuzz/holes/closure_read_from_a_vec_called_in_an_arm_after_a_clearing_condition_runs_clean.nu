// closure_read_from_a_vec_called_in_an_arm_after_a_clearing_condition_runs_clean:
// `? == ( cz fs ) 0 { … ( f 1 ) … }`: the condition's call effects are recorded
// when the `?` statement ends, after the arm's reads. A call of a lent binding
// while they wait makes it copy: clean.
// map: §8.4 | A2 | runs-clean | - | a closure read out of a local Vec, called in an arm whose condition cleared the Vec: the binding copies, the condition's effects wait for the whole statement (agora #552).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

@ cz ( Vec ( @ i i ) ) v → i { ( vec_clear [( @ i i )] v ) ^ 0 }

@ main → i { : ( Vec ( @ i i ) ) fs ( fill ) : ( @ i i ) f ( vec_at [( @ i i )] fs 1 ) ? == ( cz fs ) 0 { ( nurl_println_int ( f 1 ) ) } {} ( vec_free [( @ i i )] fs ) ^ 0 }
