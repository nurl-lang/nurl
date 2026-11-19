// slice_joins_into_struct_fields_both_ways_runs_clean: `@ P { ? c a b 3 }`, `@ P { ? c ( mk ) a 3 }`, `@ P { ? T ( mk ) a 3 }`: copied where the join lent, taken where it is fresh
// Closed (agora #903): a slice join's fresh arm is the caller's wherever the join lands: a block arm answers by its tail's call or join (__arm_slice_bit), a returned join by its arms' bit or-ed with a copy of an arm lending the frame's own (gen_ret, ret_join_bit), a struct literal's slice field copies the join on the runs its arms lent only (__slice_join_lent).
// main 85a31ca: LeakSanitizer reported a slice never released.
// map: §7.6 | A2 | runs-clean | - | agora #903: @ P { ? c a b 3 }, @ P { ? c ( mk ) a 3 }, @ P { ? T ( mk ) a 3 }: copied where the join lent, taken where it is fresh
@ mk → [i { ^ [i | 7 8 9] }
: P { [i s i n }
@ wrap [i a → ?[i { ^ @ ?[i { T a } }
@ main → i { : [i a [i | 1 2] : [i b [i | 4 5 6 7] : b c F : P p @ P { ? c a b 3 } : P q @ P { ? c ( mk ) a 3 } : P r @ P { ? T ( mk ) a 3 } ( nurl_println_int . . p s 1 ) ( nurl_println_int . . q s 1 ) ( nurl_println_int . . r s 1 ) ( nurl_println_int . a 1 ) ( nurl_println_int . b 1 ) ^ 0 }
