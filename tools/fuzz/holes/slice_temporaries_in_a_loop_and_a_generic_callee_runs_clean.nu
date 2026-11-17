// slice_temporaries_in_a_loop_and_a_generic_callee_runs_clean: `( ln ( mk ) )` in a loop, `( glen [i] ( mk ) )` and `: [i x ( gid [i] ( mk ) )`
// Closed (agora #891): a slice temporary is released after each call by the inner call's answer, in a loop and to a generic instance as to any callee.
// main 2a7b1153: LeakSanitizer reported each temporary never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( ln ( mk ) )` in a loop, `( glen [i] ( mk ) )` and `: [i x ( gid [i] ( mk ) )`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ glen [A] [A a → i { ^ . a 1 }
@ gid [A] [A a → [A { ^ a }
@ main → i { : ~ i k 0 ~ < k 3 { ( nurl_println_int ( ln ( mk ) ) ) = k + k 1 } ( nurl_println_int ( glen [i] ( mk ) ) ) : [i x ( gid [i] ( mk ) ) ( nurl_println_int . x 1 ) ^ 0 }
