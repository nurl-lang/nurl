// slice_join_handed_back_runs_clean: `@ f b c [i a → [i { ^ ? c ( mk ) a }`, `: [i x ( f T a )`: the returned join's fresh slice is the caller's
// Closed (agora #903): a slice join's fresh arm is the caller's wherever the join lands: a block arm answers by its tail's call or join (__arm_slice_bit), a returned join by its arms' bit or-ed with a copy of an arm lending the frame's own (gen_ret, ret_join_bit), a struct literal's slice field copies the join on the runs its arms lent only (__slice_join_lent).
// main 85a31ca: LeakSanitizer reported the slice never released.
// map: §7.6 | A2 | runs-clean | - | agora #903: @ f b c [i a → [i { ^ ? c ( mk ) a }, : [i x ( f T a ): the returned join's fresh slice is the caller's
@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ f b c [i a → [i { ^ ? c ( mk ) a }
@ main → i { : [i a [i | 1 2] : [i x ( f T a ) ( nurl_println_int . x 1 ) ^ 0 }
