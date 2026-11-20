// slice_join_into_a_struct_field_runs_clean: `: P p @ P { ? c ( mk ) a 3 }`: the join's fresh slice is the struct's
// Closed (agora #903): a slice join's fresh arm is the caller's wherever the join lands: a block arm answers by its tail's call or join (__arm_slice_bit), a returned join by its arms' bit or-ed with a copy of an arm lending the frame's own (gen_ret, ret_join_bit), a struct literal's slice field copies the join on the runs its arms lent only (__slice_join_lent).
// main 85a31ca: LeakSanitizer reported the slice never released.
// map: §7.6 | A2 | runs-clean | - | agora #903: : P p @ P { ? c ( mk ) a 3 }: the join's fresh slice is the struct's
@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
: P { [i s i n }
@ main → i { : [i a [i | 1 2] : b c T : P p @ P { ? c ( mk ) a 3 } ( nurl_println_int . . p s 1 ) ^ 0 }
