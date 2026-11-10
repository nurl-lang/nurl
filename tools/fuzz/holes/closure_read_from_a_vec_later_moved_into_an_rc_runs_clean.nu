// closure_read_from_a_vec_later_moved_into_an_rc_runs_clean: `: f ( vec_at fs 1 )`,
// then `( rc_new fs )` and a clear through `( rc_get r )`, then `( f 1 )`. The
// walk re-roots f's borrow into the Rc and does not see a change through its
// handle (agora #345), so a lent f would run on a freed env (the #552
// adversarial pass). A binding called after its Vec was taken over by a call
// that keeps it copies at its read: clean.
// map: §8.4 | A2 | runs-clean | - | a closure read out of a local Vec that is then moved into an Rc and cleared through it, called after: the binding copies (agora #552).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) { : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] ) ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) ) ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) ) ^ fs }

@ main → i {
    : ( Vec ( @ i i ) ) fs ( fill )
    : ( @ i i ) f ( vec_at [( @ i i )] fs 1 )
    : ( Rc ( Vec ( @ i i ) ) ) r ( rc_new [( Vec ( @ i i ) )] fs )
    : ( Vec ( @ i i ) ) v ( rc_get [( Vec ( @ i i ) )] r )
    ( vec_clear [( @ i i )] v )
    ( nurl_println_int ( f 1 ) )
    ^ 0 }
