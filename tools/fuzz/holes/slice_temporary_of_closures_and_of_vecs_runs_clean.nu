// slice_temporary_of_closures_and_of_vecs_runs_clean: `( lnc ( mkc ) )`, a slice of closures, and `( lnv ( mkv ) )`, a slice of Vecs
// Closed (agora #891): a slice temporary's elements go with it, a closure's environment and a Vec's buffer (its drop's name a valid LLVM identifier: `(` `)` mangled as `$` `-`).
// main 2a7b1153: LeakSanitizer reported the slices and their elements never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( lnc ( mkc ) )`, a slice of closures, and `( lnv ( mkv ) )`, a slice of Vecs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mkc → [( @ i ) { : i q 4 ^ [( @ i ) | \ → i { ^ q }] }
@ lnc [( @ i ) a → i { ^ . a 1 }
@ mkv → [( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 3 ) ^ [( Vec i ) | v] }
@ lnv [( Vec i ) a → i { ^ . a 1 }
@ main → i { ( nurl_println_int ( lnc ( mkc ) ) ) ( nurl_println_int ( lnv ( mkv ) ) ) ^ 0 }
