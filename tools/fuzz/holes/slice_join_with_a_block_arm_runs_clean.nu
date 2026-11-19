// slice_join_with_a_block_arm_runs_clean: `: [i x ? c { ( mk ) } { a }` and `( ln ? c { : i q 1 ( mk ) } a )`: the block arm's fresh slice is released
// Closed (agora #903): a slice join's fresh arm is the caller's wherever the join lands: a block arm answers by its tail's call or join (__arm_slice_bit), a returned join by its arms' bit or-ed with a copy of an arm lending the frame's own (gen_ret, ret_join_bit), a struct literal's slice field copies the join on the runs its arms lent only (__slice_join_lent).
// main 85a31ca: LeakSanitizer reported two slices never released.
// map: §7.6 | A2 | runs-clean | - | agora #903: : [i x ? c { ( mk ) } { a } and ( ln ? c { : i q 1 ( mk ) } a ): the block arm's fresh slice is released
@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ main → i { : [i a [i | 1 2] : b c T : [i x ? c { ( mk ) } { a } ( nurl_println_int . x 1 ) ( nurl_println_int ( ln ? c { : i q 1 ( mk ) } a ) ) ^ 0 }
