// struct_literal_given_a_parameters_slice_a_call_may_hand_back_runs_clean: pick handed the caller's parameter, the literal local to the callee
// Closed (agora #878): a slice field of a literal that owns it by type takes a call that answers per run by that answer - copied on the runs the call lent, the fresh slice moved in on the others (__slice_field_call_lent). It was copied on every run and the fresh one was nobody's.
// main fcf68942: LeakSanitizer reported the fresh slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-878: pick handed the caller's parameter, the literal local to the callee
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ use [i a b fresh → i { : Bag g @ Bag { ( pick a fresh ) 2 } ^ . . g s 1 }
@ run b fresh → v { : [i a [i | 1 2] ( nurl_println_int ( use a fresh ) ) ( nurl_println_int . a 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
