// slice_temporary_through_two_lending_calls_read_runs_clean: `( ln ( pick ( pick a f ) F ) )` and `( ln ( pick ( mk ) f ) )`
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call by the inner call's answer (always fresh, or per run), as a binding of it is, unless the callee keeps it, sinks it, or hands it back whole; handed back, the result owns it by that bit (mem_arg_temps, mem_own_lendback).
// main 2a7b1153: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( ln ( pick ( pick a f ) F ) )` and `( ln ( pick ( mk ) f ) )`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 4 5] } {} ^ a }
@ ln [i a → i { ^ . a 1 }
@ run b f → v { : [i a [i | 1 2] ( nurl_println_int ( ln ( pick ( pick a f ) F ) ) ) ( nurl_println_int ( ln ( pick ( mk ) f ) ) ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
