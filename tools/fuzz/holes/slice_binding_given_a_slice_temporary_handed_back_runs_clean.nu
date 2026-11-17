// slice_binding_given_a_slice_temporary_handed_back_runs_clean: `= x ( id ( mk ) )` and `= x ( pick ( mk ) f )`
// Closed (agora #891): `= x ( call )` into a `: ~` slice binding goes by the call's answer: x owns the new value where the call says so (always fresh, or per run, a hand-back included), and its old value goes unless the new one lies inside it, decided by the buffer as for a join.
// main 2a7b1153: LeakSanitizer reported the temporary and x's literal never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `= x ( id ( mk ) )` and `= x ( pick ( mk ) f )`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ id [i a → [i { ^ a }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 4 5] } {} ^ a }
@ run b f → v { : ~ [i x [i | 5] = x ( id ( mk ) ) ( nurl_println_int . x 1 ) = x ( pick ( mk ) f ) ( nurl_println_int . x 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
