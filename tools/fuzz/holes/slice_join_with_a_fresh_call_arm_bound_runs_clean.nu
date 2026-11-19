// slice_join_with_a_fresh_call_arm_bound_runs_clean: `: [i x ? c ( mk ) a`: the call's fresh slice is x's on the runs its arm is taken
// Closed (agora #893): a `?` join of slices counts a call arm by the call's answer (always fresh, or per run), as a binding of the call does; the join's own bit carries it, so a binding of the join owns the buffer on the fresh arm's runs only (gen_cond, __arm_slice_bit).
// main 6f75d223: LeakSanitizer reported the call's slice never released on `run T`.
// map: §7.6 | A2 | runs-clean | - | AGORA-893: `: [i x ? c ( mk ) a`: the call's fresh slice is x's on the runs its arm is taken
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ run b c → v { : [i a [i | 1 2] : [i x ? c ( mk ) a ( nurl_println_int ( ln x ) ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
