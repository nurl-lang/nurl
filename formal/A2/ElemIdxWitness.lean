import A2.DropInWitness

/-! AGORA-1037 (AGORA-374's example): a change inside one element of a
`Vec` keeps a borrow of another element.

    : ( Vec ( Vec i ) ) vv …
    : ( Vec i ) e1 ( vec_at vv 1 )    -- element 1, lent
    : ( Vec i ) b ( vec_at vv 0 )     -- element 0, lent
    ( vec_set b 0 f )                 -- a change inside element 0
    … e1 …                            -- still valid

Both borrows are typed by `RhsT.atIdx`: an element of an owned `Vec` at a
number lies inside that element (`Kind.innerAt n`). The change through `b`
then has the effect `.dropInAt 0` on `vv` (`Edit.inEff`). That effect ends
what lies inside element 0 and keeps `e1`, which lies inside element 1
(`set_keeps_other`). Its soundness is `MInv.edit_dropE`, which rests on
`vkeepAt` / `hkeepAt`: a rewrite inside element 0 leaves `vv`'s other
elements at their indices.

Typed as before (`RhsT.at`, `.inner`), the change has the effect `.dropIn`,
which ends `e1` too (`inner_would_end`). -/

namespace A2.ElemIdxWitness

open A2.PopWitness
open A2.DynCell (NoRootb)

def E0 : Entry := ⟨vstr, .own, true, [], [], false, false, false, false⟩

/-- `b` (2): element 0 of `vv` (0), lent inside element 0. -/
def Eb0 : Entry := ⟨str, .bor, true, [⟨0, .innerAt 0⟩], [], false, false, false, false⟩

/-- `e1` (1): element 1 of `vv`, lent inside element 1. -/
def Eb1 : Entry := ⟨str, .bor, true, [⟨0, .innerAt 1⟩], [], false, false, false, false⟩

/-- `vv` (0), `e1` (1), `b` (2) and the number `f` (3). -/
def G : Ctx := fun v =>
  if v = 0 then some E0 else if v = 1 then some Eb1 else if v = 2 then some Eb0
  else if v = 3 then some intE else none

theorem G_noRootb : NoRootb G := by
  intro v E h
  unfold G at h
  repeat' split at h
  all_goals (cases h <;> simp [E0, Eb0, Eb1, intE])

/-- The borrows are what `vec_at vv n` gives at a number (`RhsT.atIdx`). -/
theorem at_typed {Γ : Ctx} (h0 : Γ 0 = some E0) (n : Nat) :
    RhsT Γ [] (.at 0 (.lit n)) ⟨str, .bor, true, [⟨0, .innerAt n⟩], [], false, false, false, false⟩ Γ :=
  RhsT.atIdx h0 rfl rfl rfl

/-- The change's effect on `vv`: inside element 0. -/
theorem eff_dropInAt :
    (Edit.set (.lit 0) 3).effAt (.innerAt 0) (decide (vstr = str)) E0.rvec = .dropInAt 0 := by
  decide

/-- **`( vec_set b 0 f )` is typed, and `e1` stays live after it.** -/
theorem set_keeps_other {ξ : Exits} :
    ∃ Γ', StmtT P ξ G [] (.edit true 2 (.set (.lit 0) 3)) Γ' ∧ Γ' 1 = some Eb1 ∧ Γ' 0 = some E0 := by
  have h := StmtT.editB (b := true) (P := P) (ξ := ξ) (F := []) (op := .set (.lit 0) 3) (t := .int) (D := [])
    (show G 2 = some Eb0 from rfl) rfl rfl rfl rfl (by simp)
    (EditArg.set ExprT.lit (show G 3 = some intE from rfl) rfl rfl PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide)
    (show G 2 = some Eb0 from rfl) rfl
    (thru_ok G_noRootb rfl (fun y hy => by simp [Edit.stored] at hy; subst hy; decide) rfl (by simp)).toR
    (fun _ => rfl)
  refine ⟨_, h, ?_, ?_⟩ <;>
  simp [A2.setE, upd, A2.killThru, A2.killNames, thruDeps, memDeps, argE, G, E0, Eb0, Eb1, Kind.isName,
    Kind.bound, A2.kill, killE, hits, Entry.vdeps, Mode.ownSlot, Eff.kills, Entry.rvec, Ty.isVec,
    vstr, str, Edit.effAt, Edit.inEff]

/-- Lent `.inner` (`RhsT.at`), a change inside an element ends `e1` too. -/
theorem inner_would_end :
    hits .dropIn false 0 ⟨str, .bor, true, [⟨0, .inner⟩], [], false, false, false, false⟩ = true := by
  decide

end A2.ElemIdxWitness
