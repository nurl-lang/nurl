// struct_literal_given_a_slice_a_call_hands_back_fresh_or_lent_pushed_runs_clean: the literal pushed straight into a Vec
// Closed (agora #878): a slice field of a literal that owns it by type takes a call that answers per run by that answer - copied on the runs the call lent, the fresh slice moved in on the others (__slice_field_call_lent). It was copied on every run and the fresh one was nobody's.
// main fcf68942: LeakSanitizer reported the fresh slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-878: the literal pushed straight into a Vec
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ run b fresh → v { : [i a [i | 1 2] : ~ ( Vec Bag ) vs ( vec_new [Bag] ) ( vec_push [Bag] vs @ Bag { ( pick a fresh ) 2 } ) ( nurl_println_int . . ( vec_at [Bag] vs 0 ) s 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
