// slice_temporary_handed_back_by_a_closure_runs_clean: `: [i x ( f ( mk ) )` with `f` = `\ [i a → [i { ^ a }`: the slice `mk` made is released
// Closed (agora #894): a call through a closure value whose result is an owned slice of elements that hold no view hands its caller a slice of its own on every run, the closure's where it said so at its return, else a copy (mem_clo_ret_copies_slc); a slice a call made, handed to it, goes after the call.
// main 977a74c: LeakSanitizer reported the 24-byte slice never released.
// map: §7.6 | A2 | runs-clean | - | agora #894: : [i x ( f ( mk ) ) with f = \ [i a → [i { ^ a }: the slice mk made is released
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ main → i { : ( @ [i [i ) f \ [i a → [i { ^ a } : [i x ( f ( mk ) ) ( nurl_println_int . x 1 ) ^ 0 }
