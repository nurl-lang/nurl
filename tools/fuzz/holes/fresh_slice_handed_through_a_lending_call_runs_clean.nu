// fresh_slice_handed_through_a_lending_call_runs_clean: `: [i x ( pick ( pick a fresh ) F )`: the inner slice is x's on the runs it was fresh
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call by the inner call's answer (always fresh, or per run), as a binding of it is, unless the callee keeps it, sinks it, or hands it back whole; handed back, the result owns it by that bit (mem_arg_temps, mem_own_lendback).
// main 2a7b1153: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `: [i x ( pick ( pick a fresh ) F )`: the inner slice is x's on the runs it was fresh
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ run b fresh → v { : [i a [i | 1 2] : [i x ( pick ( pick a fresh ) F ) ( nurl_println_int . x 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
