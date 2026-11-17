// option_literal_handed_back_with_a_slice_a_call_hands_back_fresh_or_lent_runs_clean: `^ @ ?[i { T ( pick a fresh ) } }`
// Closed (agora #890): a literal's slice field copied wherever its call lent hands back none of the call's arguments: the call's could-hand-back list (`__last_phi_idents__`) is cleared there, so gen_ret records no returned handle of them and the function's result is its own.
// main 2e1f80b3: LeakSanitizer reported the Bag's slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-890: `^ @ ?[i { T ( pick a fresh ) } }`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
: Two { [i s [i t }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ mk [i a b fresh → ?[i { ^ @ ?[i { T ( pick a fresh ) } }
@ run b fresh → v { : [i a [i | 1 2] ?? ( mk a fresh ) { T q → { ( nurl_println_int . q 1 ) } F → {} } }
@ main → i { ( run T ) ( run F ) ^ 0 }
