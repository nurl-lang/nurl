import A2.Soundness

/-! A context with no borrowed parameter and no binding that runs a
destructor (`NoRootb`), and what typing such a context needs no more than.
Lemmas about every context, first proved for `A2/DynCell.lean`'s witness
(the names stay in `A2.DynCell`); apart from it so that a module that uses
them, `A2/Dtor.lean` among them, loads no witness program (AGORA-1013). -/

namespace A2.DynCell
open A2

/-- A context with no borrowed parameter and no binding that runs a
    destructor: nothing in it can be pinned, and ending a binding ends no
    destructor's view. -/
def NoRootb (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false

theorem NoRootb.noPin {Γ : Ctx} (h : NoRootb Γ) (x : Var) : NoPin Γ x :=
  fun p E hp hm => absurd hm (h p E hp).1

theorem NoRootb.endOK {Γ : Ctx} (h : NoRootb Γ) (x : Var) : EndOK Γ x :=
  ⟨h.noPin x, DtorSafe.of_none (fun v E hv => (h v E hv).2.1) _ _ _,
    DbindSafe.of_none (fun v E hv => (h v E hv).2.2) x⟩

theorem NoRootb.setE {Γ : Ctx} (h : NoRootb Γ) {x : Var} {E : Entry}
    (hE : E.mode ≠ .rootb ∧ E.dtor = false ∧ E.dbind = false) :
    NoRootb (A2.setE Γ x E) := by
  intro v E' hv
  simp only [A2.setE, upd] at hv
  split at hv
  · cases hv; exact hE
  · exact h v E' hv

theorem NoRootb.kill {Γ : Ctx} (h : NoRootb Γ) (e : Eff) (hv : Bool) (x : Var) :
    NoRootb (A2.kill e hv x Γ) := by
  intro v E' h'
  simp only [A2.kill] at h'
  cases hg : Γ v with
  | none => rw [hg] at h'; cases h'
  | some E =>
    rw [hg] at h'; simp only [Option.map_some, Option.some.injEq] at h'; subst h'
    rw [killE_mode, killE_dtor, killE_dbind]; exact h v E hg

theorem NoRootb.exitScope {Γ : Ctx} (h : NoRootb Γ) (x : Var) : NoRootb (A2.exitScope x Γ) := by
  intro v E' h'
  simp only [A2.exitScope, upd] at h'
  split at h'
  · cases h'
  · exact h.kill .replace false x v E' h'

theorem noRootb_empty : NoRootb (fun _ => none) := fun _ _ h => by cases h

end A2.DynCell
