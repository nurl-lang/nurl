// slice_temporary_from_a_closure_call_runs_clean: `( ln ( f ) )`, f a closure that makes a slice
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call by the inner call's answer (always fresh, or per run), as a binding of it is, unless the callee keeps it, sinks it, or hands it back whole; handed back, the result owns it by that bit (mem_arg_temps, mem_own_lendback).
// main 2a7b1153: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( ln ( f ) )`, f a closure that makes a slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ ln [i a → i { ^ . a 1 }
@ main → i { : ( @ [i ) f \ → [i { ^ [i | 4 5] } ( nurl_println_int ( ln ( f ) ) ) ^ 0 }
