// slice_join_with_a_block_arm_lending_a_binding_runs_clean: `? c { a } { ( mk ) }` bound and handed straight to a call: the fresh arm's slice is released, the binding stays its owner's
// Closed (agora #903): a slice join's fresh arm is the caller's wherever the join lands: a block arm answers by its tail's call or join (__arm_slice_bit), a returned join by its arms' bit or-ed with a copy of an arm lending the frame's own (gen_ret, ret_join_bit), a struct literal's slice field copies the join on the runs its arms lent only (__slice_join_lent).
// main 85a31ca: LeakSanitizer reported a slice never released.
// map: §7.6 | A2 | runs-clean | - | agora #903: ? c { a } { ( mk ) } bound and handed straight to a call: the fresh arm's slice is released, the binding stays its owner's
@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ main → i { : [i a [i | 1 2] : b c F : [i x ? c { a } { ( mk ) } ( nurl_println_int . x 1 ) : [i y ? c { ( mk ) } { a } ( nurl_println_int . y 1 ) ( nurl_println_int ( ln ? T { a } { ( mk ) } ) ) ( nurl_println_int . a 1 ) ^ 0 }
