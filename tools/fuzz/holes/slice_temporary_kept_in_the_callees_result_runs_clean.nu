// slice_temporary_kept_in_the_callees_result_runs_clean: fresh slice temporaries handed to callees that keep them in their result (a struct, an option) or hand them back whole
// Guard for AGORA-895's fix (the leak it closed); graduated from tools/ncore/openprobes once the reference checker and the engine read the per-call own bit (AGORA-915).
// main acec7a3: accepted, clean under ASan.
// map: §7.6 | A2 | runs-clean | - | AGORA-895 / AGORA-915 guard: a slice temporary its callee keeps in its result or hands back whole
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ mk → [i { ^ [i | 7 8 9] }
@ id [i a → [i { ^ a }
@ wrapb [i a → Bag { ^ @ Bag { a 1 } }
@ wrap [i a → ?[i { ^ @ ?[i { T a } }
@ f → [i { ^ ( id ( mk ) ) }
@ main → i { : Bag g ( wrapb ( mk ) ) ( nurl_println_int . . g s 1 ) : ?[i o ( wrap ( mk ) ) ?? o { T q → { ( nurl_println_int . q 1 ) } F → {} } : [i x ( f ) ( nurl_println_int . x 1 ) ^ 0 }
