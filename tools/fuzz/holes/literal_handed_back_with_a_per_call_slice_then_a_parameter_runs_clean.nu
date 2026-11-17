// literal_handed_back_with_a_per_call_slice_then_a_parameter_runs_clean: `^ @ Two { ( pick a fresh ) a }`
// Closed (agora #890): a literal's slice field copied wherever its call lent hands back none of the call's arguments: the call's could-hand-back list (`__last_phi_idents__`) is cleared there, so gen_ret records no returned handle of them and the function's result is its own.
// main 2e1f80b3: LeakSanitizer reported the Bag's slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-890: `^ @ Two { ( pick a fresh ) a }`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
: Two { [i s [i t }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ mk [i a b fresh → Two { ^ @ Two { ( pick a fresh ) a } }
@ run b fresh → v { : [i a [i | 1 2] : Two g ( mk a fresh ) ( nurl_println_int . . g s 1 ) ( nurl_println_int . . g t 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
