// slice_join_handed_back_lending_a_parameter_or_a_local_runs_clean: `^ ? c ( mk ) a` over a parameter and `^ ? c ( mk ) l` over a local, both runs: fresh released, the parameter kept, the local copied
// Closed (agora #903): a slice join's fresh arm is the caller's wherever the join lands: a block arm answers by its tail's call or join (__arm_slice_bit), a returned join by its arms' bit or-ed with a copy of an arm lending the frame's own (gen_ret, ret_join_bit), a struct literal's slice field copies the join on the runs its arms lent only (__slice_join_lent).
// main 85a31ca: LeakSanitizer reported a slice never released.
// map: §7.6 | A2 | runs-clean | - | agora #903: ^ ? c ( mk ) a over a parameter and ^ ? c ( mk ) l over a local, both runs: fresh released, the parameter kept, the local copied
@ mk → [i { ^ [i | 7 8 9] }
@ f b c [i a → [i { ^ ? c ( mk ) a }
@ g b c → [i { : [i l [i | 4 5] ^ ? c ( mk ) l }
@ main → i { : [i a [i | 1 2] : [i x ( f T a ) : [i y ( f F a ) ( nurl_println_int . x 1 ) ( nurl_println_int . y 1 ) : [i z ( g F ) : [i w ( g T ) ( nurl_println_int . z 1 ) ( nurl_println_int . w 1 ) ( nurl_println_int . a 1 ) ^ 0 }
