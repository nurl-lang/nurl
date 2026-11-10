// closure_read_from_a_vec_bound_through_a_value_block_runs_clean:
// `: g { f }` then `( vec_clear fs )` then `( g 1 )`. The walk does not tie
// g to fs through the block for a closure. f read as a value copies: clean.
// map: §8.4 | A2 | runs-clean | - | a closure read out of a local Vec, bound again through a value block `{ f }`, called after the Vec is cleared: the first binding copies, being read as a value (agora #552).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

@ main → i { : ( Vec ( @ i i ) ) fs ( fill ) : ( @ i i ) f ( vec_at [( @ i i )] fs 1 ) : ( @ i i ) g { f } ( vec_clear [( @ i i )] fs ) ( nurl_println_int ( g 1 ) ) ( vec_free [( @ i i )] fs ) ^ 0 }
