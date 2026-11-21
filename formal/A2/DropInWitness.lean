import A2.PopWitness

/-! AGORA-937: a change strictly inside the elements of a `Vec` root keeps
the root's own views (`Eff.dropIn`).

    : ( Vec ( Vec i ) ) vv …
    : ( Slice ( Vec i ) ) sw ( slice_from_vec vv )   -- a view of vv's buffer
    : ( Vec i ) b ( vec_at vv 0 )                    -- an element, lent
    ( vec_set b 0 f )                                -- a change inside it
    … sw …                                           -- still valid

The change moves no element of `vv`: `vv`'s buffer keeps its address and its
length, and only what is inside `vv[0]` changes. MEMORY.md §2.10 says so
("its handles of the elements stay"), and nurlc keeps `sw`. Before this
change A2 gave the edit the effect `.drop` on `vv`, which ends `.view`
borrows, so `sw` ended (`drop_would_end`). It now has the effect `.dropIn`
there (`Edit.inEff`), which ends what is inside the elements and keeps the
root's views (`set_keeps_view`). Its soundness is `MInv.edit_dropE`, which
rests on `vkeep_view_below`.

A field of a struct is lent `.inner` as well (`projDeps`), but it lies at
the struct's top, and a change through it may change its length. So a root
that is not a `Vec` keeps `.drop` (`struct_root_drops`). -/

namespace A2.DropInWitness

open A2.PopWitness
open A2.DynCell (NoRootb)

/-- `sw` (1): a view of `vv`'s (0) own buffer. -/
def Esw : Entry := ⟨.slice str, .bor, true, [⟨0, .view⟩], [], false, false, false, false⟩

def E0 : Entry := ⟨vstr, .own, true, [], [], false, false, false, false⟩

/-- `vv` (0), `sw` (1), `b` (2, `Eb`: `vv`'s element, lent `.inner`) and
    the number `f` (3). -/
def G : Ctx := fun v =>
  if v = 0 then some E0 else if v = 1 then some Esw else if v = 2 then some Eb
  else if v = 3 then some intE else none

theorem G_noRootb : NoRootb G := by
  intro v E h
  unfold G at h
  repeat' split at h
  all_goals (cases h <;> simp [E0, Esw, Eb, intE])

/-- The change's effect on `vv`: inside its elements. -/
theorem eff_dropIn : (Edit.set (.lit 0) 3).effAt .inner (decide (vstr = str)) vstr.isVec = .dropIn := by
  decide

/-- **`( vec_set b 0 f )` is typed, and `sw` stays live after it.** -/
theorem set_keeps_view {ξ : Exits} :
    ∃ Γ', StmtT P ξ G [] (.edit true 2 (.set (.lit 0) 3)) Γ' ∧ Γ' 1 = some Esw ∧ Γ' 0 = some E0 := by
  refine ⟨_, set_typed G_noRootb (x := 2) (f := 3) (E := Eb) rfl rfl rfl rfl (by decide) (by decide), ?_, ?_⟩ <;>
  simp [A2.setE, upd, A2.killThru, A2.killNames, thruDeps, memDeps, argE, G, E0, Esw, Eb, Kind.isName,
    Kind.bound, eff_dropIn, A2.kill, killE, hits, Entry.vdeps, Mode.ownSlot, Eff.kills]

/-- Under `.drop`, A2's effect before, `sw` would have ended. -/
theorem drop_would_end : hits .drop false 0 Esw = true := by decide

/-- A struct root keeps `.drop`: its field is lent `.inner` but lies at its
    top. -/
theorem struct_root_drops (k : Kind) (s : Bool) :
    (Edit.set (.lit 0) 3).effAt k s (Ty.prod str .int).isVec = .drop := by
  simp [Edit.effAt, Edit.inEff, Ty.isVec]

end A2.DropInWitness
