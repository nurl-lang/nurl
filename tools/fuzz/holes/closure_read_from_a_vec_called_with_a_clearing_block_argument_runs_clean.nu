// closure_read_from_a_vec_called_with_a_clearing_block_argument_runs_clean:
// `( f { ( vec_clear fs ) 1 } )`. The block's statement clears fs while f's
// argument is computed, before f runs, and its flush drops the walk's
// pending read of f (claude-formal's review of #1726: a use-after-free). A
// call completed while a lent binding's own arguments are compiled makes it
// copy at its read (g_calls_total): clean (agora #552).
// map: §8.4 | A2 | runs-clean | - | a closure read out of a Vec, called with a value-block argument that clears the Vec: the binding copies (agora #552).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

: H { ( Vec ( @ i i ) ) v }

@ id i x → i { ^ x }

@ main → i { : ( Vec ( @ i i ) ) fs ( fill ) : ( @ i i ) f ( vec_at [( @ i i )] fs 1 ) ( nurl_println_int ( f { ( vec_clear [( @ i i )] fs ) 1 } ) ) ( vec_free [( @ i i )] fs ) ^ 0 }
