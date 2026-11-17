// slice_join_with_a_literal_arm_handed_to_a_call_runs_clean: `( ln ? c [i | 4 5 6] a )`: the literal is released after the call on the runs its arm was taken, `a` never
// Closed (agora #893): the mixed phi a slice join already had for a literal arm (agora #664) is now published for a call the join is handed to as well (mem_arg_temps), so the literal's buffer is released after the call.
// main 6f75d223: LeakSanitizer reported the literal's slice never released on `run T`.
// map: §7.6 | A2 | runs-clean | - | AGORA-893: `( ln ? c [i | 4 5 6] a )`: the literal arm's slice is released after the call
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ ln [i a → i { ^ . a 1 }
@ run b c → v { : [i a [i | 1 2] ( nurl_println_int ( ln ? c [i | 4 5 6] a ) ) ( nurl_println_int ( ln a ) ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
