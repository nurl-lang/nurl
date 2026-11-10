// closure_read_from_a_vec_moved_into_a_struct_then_an_rc_runs_clean: fs goes
// into a literal `@ H { fs }`, the holder into `( rc_new h )`, and is
// cleared through `( rc_get r )` before `( f 2 )`. The walk does not follow
// a change through the Rc handle (agora #345), so a lent f ran on a freed env
// (claude-formal's review of #1726). A Vec stored into an owner counts as
// moved, so the binding copies: clean (agora #552).
// map: §8.4 | A2 | runs-clean | - | a closure read out of a Vec moved into a struct, the struct into an Rc and cleared through it: the binding copies (agora #552).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

: H { ( Vec ( @ i i ) ) v }

@ id i x → i { ^ x }

@ main → i { : ( Vec ( @ i i ) ) fs ( fill ) : ( @ i i ) f ( vec_at [( @ i i )] fs 1 ) : H h @ H { fs } : ( Rc H ) r ( rc_new [H] h ) ( vec_clear [( @ i i )] . ( rc_get [H] r ) v ) ( nurl_println_int ( f 2 ) ) ^ 0 }
