// option_literal_given_a_slice_a_call_hands_back_fresh_or_lent_runs_clean: `@ ?[i { T ( pick a fresh ) }`
// Closed (agora #878): a slice field of a literal that owns it by type takes a call that answers per run by that answer - copied on the runs the call lent, the fresh slice moved in on the others (__slice_field_call_lent). It was copied on every run and the fresh one was nobody's.
// main fcf68942: LeakSanitizer reported the fresh slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-878: `@ ?[i { T ( pick a fresh ) }`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ run b fresh → v { : [i a [i | 1 2] : ?[i o @ ?[i { T ( pick a fresh ) } ?? o { T q → { ( nurl_println_int . q 1 ) } F → {} } }
@ main → i { ( run T ) ( run F ) ^ 0 }
