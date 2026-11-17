// slice_binding_given_a_call_that_answers_per_run_runs_clean: `= x ( pick a f )` over a `: ~ [i x` that owns a literal
// Closed (agora #891): `= x ( call )` into a `: ~` slice binding goes by the call's answer: x owns the new value where the call says so (always fresh, or per run, a hand-back included), and its old value goes unless the new one lies inside it, decided by the buffer as for a join.
// main 2a7b1153: ASan reported a double free: x kept its old flag and released a's buffer under a.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `= x ( pick a f )` over a `: ~ [i x` that owns a literal
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ pick [i a b fresh → [i { ? fresh { ^ [i | 4 5] } {} ^ a }
@ run b f → v { : [i a [i | 1 2] : ~ [i x [i | 5] = x ( pick a f ) ( nurl_println_int . x 1 ) }
@ main → i { ( run T ) ( run F ) ^ 0 }
