// struct_literal_given_a_slice_a_closure_hands_back_fresh_or_lent_runs_clean: the slice from a closure that hands back a fresh slice or its parameter
// Closed (agora #878): a slice field of a literal that owns it by type takes a call that answers per run by that answer - copied on the runs the call lent, the fresh slice moved in on the others (__slice_field_call_lent). It was copied on every run and the fresh one was nobody's.
// main fcf68942: LeakSanitizer reported the fresh slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-878: the slice from a closure that hands back a fresh slice or its parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }

@ run b fresh → v { : [i a [i | 1 2] : ( @ [i [i b ) pk \ [i x b f → [i { ? f { ^ [i | 7 8 9] } {} ^ x } : Bag g @ Bag { ( pk a fresh ) 2 } ( nurl_println_int . . g s 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
