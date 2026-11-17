// slice_temporary_from_callees_defined_later_runs_clean: `( ln2 ( mk2 ) )` and `( pick2 ( pick2 a T ) F )`, every callee defined below its caller
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call by the inner call's answer (always fresh, or per run), as a binding of it is, unless the callee keeps it, sinks it, or hands it back whole; handed back, the result owns it by that bit (mem_arg_temps, mem_own_lendback).
// main 2a7b1153: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( ln2 ( mk2 ) )` and `( pick2 ( pick2 a T ) F )`, every callee defined below its caller
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i { : [i a [i | 1 2] ( nurl_println_int ( ln2 ( mk2 ) ) ) : [i x ( pick2 ( pick2 a T ) F ) ( nurl_println_int . x 1 ) ^ 0 }
@ mk2 → [i { ^ [i | 7 8 9] }
@ ln2 [i a → i { ^ . a 1 }
@ pick2 [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
