module

public import A2.HeldViewThruWitness

@[expose] public section

/-! AGORA-937, item 3: a change through a region.

AGORA-933's callee `f1` takes `vv : Vec (Slice (Vec i))` lent and grows a
`Vec` it reaches through a slice `vv` holds:

    @ f1 ( Vec ( Slice ( Vec i ) ) ) vv → i {
        : ( Vec i ) e ( slice_at ( vec_at vv 0 ) 0 )   -- reaches π 0 at `.inner`
        ( vec_push e 7 )                               -- a change through the region
        ^ 0
    }

`vv` holds its region by its handle, `⟨π 0, .self⟩` (item 2). The element `e` reaches
the region at `.inner`, the slice's element (`comp .view .inner`). The push is
an `edit true` whose only root is the region. Before, `ThruOK` asked every root
to be a live owner, so A2 refused it. Now `ThruOKR` allows a region whose
effect ends no view. A region is the `DataAt` nodes its argument views, so
`.inner` is strictly inside them (`Entry.rvec`), and the effect is `.dropIn`
(item 1), which ends no view (`push_typed`). The kill it makes keeps `vv`, the
lent parameter, as it was (`push_keeps_vv`). Where the call places the change
(`Rename.editB_ren`), the region is a ghost binding (exact) or stands for
nothing, and then the call's context only knows more (`StmtT.sub`).

What is still to come (3d) is a call of `f1` from a frame that passes `vv`
holding views of real memory: `CallT`'s premise still refuses it
(`HeldViewThruWitness.call_alone_refused`). -/

namespace A2.RegionChangeWitness

open A2.HeldViewThruWitness (vvi svv vsv)

/-- The callee's frame at the push: `vv` (0, lent, holding `π 0`'s view),
    the element `e` (3, reaching `π 0 = 5` at `.inner`), the number 7 (4),
    and the region (5). -/
def Evv : Entry := ⟨vsv, .rootb, true, [], [⟨5, .self⟩], false, false, false, false⟩
def Ee : Entry := ⟨vvi, .bor, true, [⟨5, .inner⟩], [⟨5, .inner⟩], false, false, false, false⟩

def K : Ctx := fun v =>
  if v = 0 then some Evv else if v = 3 then some Ee else if v = 4 then some intE
  else if v = 5 then some regionE else none

/-- The push's effect on the region: strictly inside its nodes. -/
theorem eff_dropIn : (Edit.push 4).effAt .inner (decide (regionE.ty = Ee.ty)) regionE.rvec = .dropIn := by
  decide

/-- **The change through the region is allowed** (`ThruOKR`): the region's
    effect, `.dropIn`, ends no view of it. -/
theorem thru_region : ThruOKR K [] (.push 4) Ee.ty Ee.path := by
  intro d hd
  simp only [Ee, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, regionE, rfl, Or.inr rfl, Or.inr ⟨rfl, ?_⟩, ?_, by simp, ?_⟩
  · simp [Edit.stored] at hy; subst hy; decide
  · exact eff_dropIn
  · intro v E hE hd _
    unfold K at hE
    repeat' split at hE
    all_goals (cases hE <;> simp_all [Evv, Ee, intE, regionE])
  · rw [eff_dropIn]; exact HeldOK.of_kills _ rfl rfl

/-- **`( vec_push e 7 )` is typed**, through the region. -/
theorem push_typed {P : Prog} {ξ : Exits} :
    StmtT P ξ K [] (.edit true 3 (.push 4))
      (A2.setE (A2.killThru (.push 4) Ee.ty Ee.path K) 3 Ee) :=
  StmtT.editB (b := true) (t := .int) (D := []) (Ex := Ee) (Ex1 := Ee) rfl rfl rfl rfl rfl (by simp)
    (EditArg.push (Ey := intE) rfl rfl rfl PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide) rfl rfl thru_region
    (fun h => by simp [Edit.drops] at h) (fun h => by cases h)

/-- **... and the lent parameter `vv` stays as it was**: the change ends no
    view of the region. -/
theorem push_keeps_vv : A2.setE (A2.killThru (.push 4) Ee.ty Ee.path K) 3 Ee 0 = some Evv := by
  simp [A2.setE, upd, A2.killThru, A2.killNames, thruDeps, memDeps, Ee, Kind.isName, argE, K, regionE,
    Kind.bound, A2.kill, killE, hits, Evv, Entry.vdeps, Mode.ownSlot, Eff.kills, Entry.rvec, Ty.isVec,
    Edit.effAt, Edit.inEff, vvi]

/-- Under the old rule a root had to be a live owner, and a region is
    neither. -/
theorem region_not_owner : ¬ (regionE.live = true ∧
    canDo regionE.mode ((Edit.push 4).effAt .inner false regionE.rvec)) := by
  rintro ⟨h, _⟩; cases h

end A2.RegionChangeWitness
