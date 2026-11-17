// slice_temporary_lent_in_part_by_a_recursive_forwarder_runs_clean: `: [i x ( walk ( mk ) 3 )`, walk forwarding its parameter through itself
// Closed (agora #891): a slice copies as a String does (__clone_supported: its buffer and its elements, where they copy), so a result its callee lends in part out of a temporary is copied and the temporary released; taken for one that cannot be copied, the program would be refused.
// main 2a7b1153: LeakSanitizer reported the temporary never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `: [i x ( walk ( mk ) 3 )`, walk forwarding its parameter through itself
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ walk [i a i n → [i { ? == n 0 { ^ a } {} ^ ( walk a - n 1 ) }
@ main → i { : [i x ( walk ( mk ) 3 ) ( nurl_println_int . x 1 ) ( nurl_println_int ( ln ( walk ( mk ) 2 ) ) ) ^ 0 }
