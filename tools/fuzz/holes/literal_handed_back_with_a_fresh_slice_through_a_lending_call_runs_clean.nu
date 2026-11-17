// literal_handed_back_with_a_fresh_slice_through_a_lending_call_runs_clean: `^ @ Bag { ( pick ( pick a f ) F ) 2 }`
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call by the inner call's answer (always fresh, or per run), as a binding of it is, unless the callee keeps it, sinks it, or hands it back whole; handed back, the result owns it by that bit (mem_arg_temps, mem_own_lendback).
// main 2a7b1153: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `^ @ Bag { ( pick ( pick a f ) F ) 2 }`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Bag { [i s i n }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ mkbag [i a b f → Bag { ^ @ Bag { ( pick ( pick a f ) F ) 2 } }
@ run b f → v { : [i a [i | 1 2] : Bag g ( mkbag a f ) ( nurl_println_int . . g s 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
