// literal_handed_back_with_a_slice_a_call_hands_back_fresh_or_lent_runs_clean: `^ @ Bag { ( pick a fresh ) 2 }`: the function hands back its own Bag on every run
// Closed (agora #890): a literal's slice field copied wherever its call lent hands back none of the call's arguments: the call's could-hand-back list (`__last_phi_idents__`) is cleared there, so gen_ret records no returned handle of them and the function's result is its own.
// main 2e1f80b3: LeakSanitizer reported the Bag's slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-890: `^ @ Bag { ( pick a fresh ) 2 }`: the function hands back its own Bag on every run
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ mkbag [i a b fresh → Bag { ^ @ Bag { ( pick a fresh ) 2 } }
@ run b fresh → v { : [i a [i | 1 2] : Bag g ( mkbag a fresh ) ( nurl_println_int . . g s 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
