// slice_temporaries_handed_to_a_two_parameter_callee_runs_clean: `( ln2 ( mk ) ( mk ) )` and `: [i x ( snd ( mk ) ( mk ) )`
// Closed (agora #891): each slice temporary goes by its own call's answer: the one handed back is the result's, the other released after the call.
// main 2a7b1153: LeakSanitizer reported the temporaries never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( ln2 ( mk ) ( mk ) )` and `: [i x ( snd ( mk ) ( mk ) )`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln2 [i a [i b → i { ^ + . a 1 . b 1 }
@ snd [i a [i b → [i { ^ b }
@ main → i { ( nurl_println_int ( ln2 ( mk ) ( mk ) ) ) : [i x ( snd ( mk ) ( mk ) ) ( nurl_println_int . x 1 ) ^ 0 }
