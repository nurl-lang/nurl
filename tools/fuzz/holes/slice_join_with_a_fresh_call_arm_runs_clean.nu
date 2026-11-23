// slice_join_with_a_fresh_call_arm_runs_clean: a `?` join of slices with a call's fresh slice on one arm, handed on; the fresh arm's slice is the result's own on the calls that take it
// Guard for AGORA-893's fix (the leak it closed); graduated from tools/ncore/openprobes once the reference checker and the engine read the per-call own bit (AGORA-915).
// main acec7a3: accepted, clean under ASan.
// map: §7.6 | A2 | runs-clean | - | AGORA-893 / AGORA-915 guard: a `?` join of slices with a call's fresh slice on one arm
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ run b c → v { : [i a [i | 1 2] : [i x ? c ( mk ) a ( nurl_println_int ( ln x ) ) ( nurl_println_int ( ln ? c ( mk ) a ) ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
