// slice_binding_given_a_call_that_always_lends_runs_clean: `= x ( id t )` over a `: ~ [i x` that owns a literal
// Closed (agora #891): `= x ( call )` into a `: ~` slice binding goes by the call's answer: x owns the new value where the call says so (always fresh, or per run, a hand-back included), and its old value goes unless the new one lies inside it, decided by the buffer as for a join.
// main 2a7b1153: ASan reported a double free.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `= x ( id t )` over a `: ~ [i x` that owns a literal
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ id [i a → [i { ^ a }
@ main → i { : ~ [i x [i | 5] : [i t ( mk ) = x ( id t ) ( nurl_println_int . x 1 ) ^ 0 }
