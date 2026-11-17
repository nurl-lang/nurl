// slice_binding_given_its_own_value_back_runs_clean: `= x ( id x )`: the new value is the old buffer, which stays
// Closed (agora #891): `= x ( call )` into a `: ~` slice binding goes by the call's answer: x owns the new value where the call says so (always fresh, or per run, a hand-back included), and its old value goes unless the new one lies inside it, decided by the buffer as for a join.
// main 2a7b1153: control: ran clean (kept by the buffer test).
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `= x ( id x )`: the new value is the old buffer, which stays
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ id [i a → [i { ^ a }
@ main → i { : ~ [i x [i | 5 6] = x ( id x ) ( nurl_println_int . x 1 ) ^ 0 }
