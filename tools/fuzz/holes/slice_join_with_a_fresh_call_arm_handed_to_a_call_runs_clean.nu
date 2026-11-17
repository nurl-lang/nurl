// slice_join_with_a_fresh_call_arm_handed_to_a_call_runs_clean: `( ln ? c ( mk ) a )`: the join is a temporary of the caller's, released after the call on the runs its fresh arm was taken
// Closed (agora #893): a slice join handed straight to a call is released after it by the join's own bit (`__last_slice_join_own__`, read as a join's ownership by mem_arg_temps), unless the callee keeps it.
// main 6f75d223: LeakSanitizer reported the call's slice never released on `run T`.
// map: §7.6 | A2 | runs-clean | - | AGORA-893: `( ln ? c ( mk ) a )`: the join handed to a call is released after it on the fresh arm's runs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ run b c → v { : [i a [i | 1 2] ( nurl_println_int ( ln ? c ( mk ) a ) ) ( nurl_println_int ( ln ? c a ( mk ) ) ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
