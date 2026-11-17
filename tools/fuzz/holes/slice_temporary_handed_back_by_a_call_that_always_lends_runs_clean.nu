// slice_temporary_handed_back_by_a_call_that_always_lends_runs_clean: `: [i x ( id ( mk ) )`: x owns the temporary its callee hands back
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call by the inner call's answer (always fresh, or per run), as a binding of it is, unless the callee keeps it, sinks it, or hands it back whole; handed back, the result owns it by that bit (mem_arg_temps, mem_own_lendback).
// main 2a7b1153: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `: [i x ( id ( mk ) )`: x owns the temporary its callee hands back
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ id [i a → [i { ^ a }
@ main → i { : [i x ( id ( mk ) ) ( nurl_println_int . x 1 ) ^ 0 }
