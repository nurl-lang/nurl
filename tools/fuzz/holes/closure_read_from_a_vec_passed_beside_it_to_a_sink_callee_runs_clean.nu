// closure_read_from_a_vec_passed_beside_it_to_a_sink_callee_runs_clean:
// `( sk fs f )`, sk freeing its sink Vec and then calling f — agora #494's
// shape, open for a String. f read as a value copies: clean.
// map: §8.4 | A2 | runs-clean | - | a closure read out of a local Vec, passed with that Vec to a sink parameter that frees it, then called: the binding copies (agora #552, #494).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

@ sk sink ( Vec ( @ i i ) ) v ( @ i i ) g → i { ( vec_free [( @ i i )] v ) ^ ( g 1 ) }

@ main → i { : ( Vec ( @ i i ) ) fs ( fill ) : ( @ i i ) f ( vec_at [( @ i i )] fs 1 ) ( nurl_println_int ( sk fs f ) ) ^ 0 }
