// slice_temporary_handed_to_a_reader_runs_clean: `( ln ( mk ) )`
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call by the inner call's answer (always fresh, or per run), as a binding of it is, unless the callee keeps it, sinks it, or hands it back whole; handed back, the result owns it by that bit (mem_arg_temps, mem_own_lendback).
// main 2a7b1153: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( ln ( mk ) )`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }
@ main → i { ( nurl_println_int ( ln ( mk ) ) ) ^ 0 }
