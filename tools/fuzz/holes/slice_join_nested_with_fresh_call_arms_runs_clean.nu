// slice_join_nested_with_fresh_call_arms_runs_clean: `: [i x ? c ? d ( mk ) a ( mk2 )`, `( ln ? c ? d ( mk ) ( mk2 ) a )`: an arm that is itself a slice join counts by that join's bit
// Closed (agora #893): a `?` arm that is a slice join hands its own bit to the outer join (`__last_slice_join_own__`, read in the arm's block), as a call arm hands its answer.
// main 34d2577e: LeakSanitizer reported up to five slices never released over the four runs.
// map: §7.6 | A2 | runs-clean | - | AGORA-893: a nested slice join with fresh call arms, bound and handed to a call
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ mk2 → [i { ^ [i | 1 2 3 4] }
@ ln [i a → i { ^ . a 1 }
@ run b c b d → v { : [i a [i | 1 2] : [i x ? c ? d ( mk ) a ( mk2 ) ( nurl_println_int ( ln x ) ) ( nurl_println_int ( ln ? c ? d ( mk ) ( mk2 ) a ) ) }
@ main → i { ( run T T ) ( run T F ) ( run F T ) ( run F F ) ^ 0 }
