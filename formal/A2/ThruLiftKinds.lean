import A2.Typing

/-! A2 — AGORA-932: what a change through a callee borrow kills, seen from the
caller.

A callee changes elements through a borrow `b` whose path reaches its
parameter `p` by kind `kb`; another callee binding `c` reaches `p` by kind
`kc`. Where the call places the body, an argument that reaches a caller
root `r` by kind `a` makes the change also reach `r`, by `comp a kb`, and `c`
reach `r` by `comp a kc`. These lemmas compare the two kills: the callee's
on `p`, and the caller's on `r`.

* A hop through the root's own handle (`a = .self`) is exact
  (`kills_comp_self`).
* A hop through a view or an element is not: the caller's kill may end a
  binding the callee's keeps live (`comp_view_overkills`,
  `comp_inner_overkills`). A lift that types the body where the call places
  it must therefore not take the callee's kill on `p` at its own kind.
* The kill of every kind on `p` (`.replace`) covers the caller's, whatever
  the hop (`replace_covers`). -/

namespace A2

/-- Through the root's own handle the caller kills exactly what the callee
    does. -/
theorem kills_comp_self (op : Edit) (kb kc : Kind) (s : Bool) (hv : Bool) :
    (op.effAt (comp .self kb) s).kills hv (comp .self kc) = (op.effAt kb s).kills hv kc := rfl

/-- Through a view the caller's kill is coarser: a truncation through the
    parameter's own handle keeps a borrow of that handle live in the callee
    (the parameter's elements hold no views), but ends it in the caller. -/
theorem comp_view_overkills :
    ((Edit.trunc (.lit 0)).effAt .self true).kills false .self = false ∧
    ((Edit.trunc (.lit 0)).effAt (comp .view .self) true).kills false (comp .view .self) = true := by
  decide

/-- ... and through an element, the same. -/
theorem comp_inner_overkills :
    ((Edit.trunc (.lit 0)).effAt .self true).kills false .self = false ∧
    ((Edit.trunc (.lit 0)).effAt (comp .inner .self) true).kills false (comp .inner .self) = true := by
  decide

/-- A push through the parameter's own handle reallocates it in the callee,
    which keeps a borrow of an element's inside live; in the caller, through an
    element hop, it is a drop, which ends it (AGORA-933's shape). -/
theorem comp_inner_push_overkills :
    ((Edit.push 0).effAt .self true).kills false .inner = false ∧
    ((Edit.push 0).effAt (comp .inner .self) true).kills false (comp .inner .inner) = true := by
  decide

/-- Killing every kind on the parameter covers whatever the caller kills. -/
theorem replace_covers (op : Edit) (a kb kc : Kind) (s hv hv' : Bool)
    (_h : (op.effAt (comp a kb) s).kills hv (comp a kc) = true) : Eff.replace.kills hv' kc = true := by
  cases kc <;> rfl

/-! ### Ending the frame's views of a changed root before the call

A call through which the callee changes a caller root `r` ends, before the
body runs, every frame binding that views `r` (`kill .replace false r`). The
callee cannot reach the frame, so nothing typed in its body changes; and a
later kill of any effect on `r` changes nothing more there. -/

/-- Whether a kill hits a binding does not read whether it is live. -/
@[simp] theorem hits_with_live (e : Eff) (hv : Bool) (r : Var) (E : Entry) (l : Bool) :
    hits e hv r { E with live := l } = hits e hv r E := rfl

/-- `.replace` ends every binding any effect ends. -/
theorem hits_replace_of_hits {e : Eff} {hv hv' : Bool} {r : Var} {E : Entry}
    (h : hits e hv r E = true) : hits .replace hv' r E = true := by
  unfold hits at h ⊢
  simp only [Bool.and_eq_true, List.any_eq_true, beq_iff_eq] at h ⊢
  obtain ⟨hn, d, hd, hr, _⟩ := h
  exact ⟨hn, d, hd, hr, by cases d.kind <;> rfl⟩

/-- A kill ends nothing that a `.replace` on the same root has not ended. -/
theorem killE_after_replace (e : Eff) (hv hv' : Bool) (r : Var) (E : Entry) :
    killE e hv r (killE .replace hv' r E) = killE .replace hv' r E := by
  unfold killE
  by_cases hR : hits .replace hv' r E = true
  · simp only [hR, ↓reduceIte, hits_with_live]
    split <;> rfl
  · have he : hits e hv r E = false := by
      cases h : hits e hv r E
      · rfl
      · exact absurd (hits_replace_of_hits h) hR
    simp [hR, he]

theorem kill_after_replace (e : Eff) (hv hv' : Bool) (r : Var) (Γ : Ctx) :
    kill e hv r (kill .replace hv' r Γ) = kill .replace hv' r Γ := by
  funext v
  unfold kill
  cases Γ v <;> simp [killE_after_replace]

end A2
