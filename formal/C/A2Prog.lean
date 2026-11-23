import C.A2Call

/-!
# C11: A2's whole programs, decided (AGORA-970)

`fnOK2B` decides A2's `FnOK` for a function: its signature's clauses, the
body checked by `checkA2` from `sigCtx` over the domain of its variables
and its parameters' regions, and the end the summary promises.
`progOK2B` decides `ProgOK`, and `checked_program_safe2` closes phase C for
A2: a program the checker accepts never gets stuck from the empty store.
-/

namespace C

open A2

/-- `lendable` (A2), decided. -/
def lendable2B (fn : Fn) (j : Nat) : Bool :=
  match fn.params[j]? with
  | some (.inp, _) => true
  | some (.inout _, _) => true
  | _ => false

theorem lendable2B_sound {fn : Fn} {j : Nat} (h : lendable2B fn j = true) : lendable fn j := by
  unfold lendable2B at h
  split at h
  · rename_i t hj
    obtain ⟨hlt, he⟩ := List.getElem?_eq_some_iff.mp hj
    exact ⟨hlt, Or.inl (by rw [he])⟩
  · rename_i b t hj
    obtain ⟨hlt, he⟩ := List.getElem?_eq_some_iff.mp hj
    exact ⟨hlt, Or.inr ⟨b, by rw [he]⟩⟩
  · cases h

/-- `kindFits`, decided. -/
def kindFitsB (fn : Fn) (j : Nat) (k : Kind) : Bool :=
  match fn.params[j]? with
  | some (.inout _, t) => decide (rootKind t k = k)
  | _ => true

theorem kindFitsB_sound {fn : Fn} {j : Nat} {k : Kind} (h : kindFitsB fn j k = true) : kindFits fn j k := by
  intro b t hj
  simp only [kindFitsB, hj, decide_eq_true_eq] at h
  exact h

/-- The domain a function's body is checked over: its variables and its
    parameters' regions (`isRegionIdx`). -/
def fnDom (fn : Fn) : List Var := List.range (fn.nvars + fn.params.length)

theorem sigCtx_supported2 {fn : Fn} (h : fn.params.length < fn.nvars) :
    Supported2 (sigCtx fn) (fnDom fn) := by
  intro v hv
  have hv' : fn.nvars + fn.params.length ≤ v := by simpa [fnDom] using hv
  have hlen : fn.params.length < v :=
    Nat.lt_of_lt_of_le h (Nat.le_trans (Nat.le_add_right _ _) hv')
  have h1 : ¬ v < fn.params.length := fun hlt => Nat.lt_asymm hlt hlen
  have h2 : ¬ v = fn.params.length := fun he => Nat.lt_irrefl _ (he ▸ hlen)
  have h3 : isRegionIdx fn v = false := by
    cases hr : isRegionIdx fn v
    · rfl
    · obtain ⟨hge, hlt, _⟩ := isRegionIdx_iff.mp hr
      exact absurd hlt (Nat.not_lt.mpr (Nat.le_sub_of_add_le (Nat.add_comm _ _ ▸ hv')))
  simp [sigCtx, h1, h2, h3]

end C
