import C.A2Chan

/-!
# C8p: A2's closure literal, its captures by name read only, decided (AGORA-978)

`.pack fs te ms y []`: the environment `y` (of type `te`) moves in, as
`vec_push` takes it (`PushArg`, `pushArg2`), and the package captures
nothing by name, so `CapsOK` holds of `[]`. The class is `any`, the one
every closure value of a type shares, whatever environment it carries; it
fits an environment that holds no destructor value (`Cross.Fits`: `any`
allows views, cells and shares, and no destructor values). A closure that
crosses (sent, spawned) needs a class of its own, not decided here.
`inferRhs2p` is `inferRhs2c` with it; `inferRhs2p_ok` is sound and keeps
contexts inside the domain.
-/

namespace C

open A2

theorem fits_any {te : Ty} {cs : List (Var × PMode × Ty)} (h : te.holdsDtor = false) : Cross.Fits .any te cs := by
  unfold Cross.Fits; simp [h]

/-- `CapsOK` for captures by name that are only read (`inp`), decided: the
    names apart; each a live binding that holds nothing, of the recorded
    type, owning its slot, holding no views; and nothing the environment
    holds names it with an effect. -/
def capsInpB (Γ : Ctx) (D : List Dep) (cs : List (Var × PMode × Ty)) : Bool :=
  decide (cs.map (·.1)).Nodup && cs.all fun c => match Γ c.1 with
    | some Ev => Ev.live && Ev.held.isEmpty && decide (Ev.ty = c.2.2) && Ev.mode.ownSlot &&
        !c.2.2.holdsView && decide (c.2.1 = .inp) &&
        D.all (fun d => !(decide (d.root = c.1)) || !d.kind.isName || decide (d.kind.bound = .none))
    | none => false

theorem capsInpB_sound {Γ : Ctx} {F : List Var} {D : List Dep} {cs : List (Var × PMode × Ty)}
    (h : capsInpB Γ D cs = true) : CapsOK Γ F D cs := by
  simp only [capsInpB, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  refine ⟨h.1, fun c hc => ?_⟩
  have h2 := h.2 c hc
  split at h2
  · rename_i Ev hEv
    simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true', List.isEmpty_iff,
      List.all_eq_true, Bool.or_eq_true, decide_eq_false_iff_not] at h2
    obtain ⟨⟨⟨⟨⟨⟨hl, hh⟩, hty⟩, ho⟩, hv⟩, hi⟩, hd⟩ := h2
    refine ⟨Ev, hEv, hl, hh, hty, ho, hv, Or.inl ⟨hi, fun d hdD hr hn => ?_⟩⟩
    rcases hd d hdD with (h0 | h0) | h0
    · exact absurd hr h0
    · rw [hn] at h0; cases h0
    · exact h0
  · cases h2

/-- A2's `RhsT` for a closure literal whose captures by name are only
    read, computed. -/
def packRhs (D : List Var) (Γ : Ctx) (F : List Var) : Rhs → Option (Entry × Ctx)
  | .pack _ te ms y cs => match liveE2 Γ y with
    | some Ey =>
      if decide (Ey.ty = te) && !te.holdsDtor then
        match pushArg2 D Γ F y Ey te with
        | some (Ds, Γ1) =>
          if capsInpB Γ1 Ds cs then
            some (⟨.fn ms .any, .own, true, [], Ds ++ capDeps cs, false, false, false, false⟩, Γ1)
          else none
        | none => none
      else none
    | none => none
  | _ => none

theorem packRhs_ok {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : packRhs D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  cases r with
  | pack _ te ms y cs =>
    simp only [packRhs] at h
    split at h
    · rename_i Ey hEy
      obtain ⟨hy, hyl⟩ := liveE2_some hEy
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc
        obtain ⟨hty, hd⟩ := hc
        split at h
        · rename_i Ds Γa hpa
          obtain ⟨pa, sa⟩ := pushArg2_sound hs hpa
          split at h
          · rename_i hcap
            simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
            exact ⟨.pack hy hyl hty pa (capsInpB_sound hcap) (fits_any hd), sa (hD y (by simp [Rhs.vars]))⟩
          · cases h
        · cases h
      · cases h
    · cases h
  | _ => simp [packRhs] at h

/-- A2's `RhsT` for the core, data, lock, channel and closure forms, computed. -/
def inferRhs2p (D : List Var) (Γ : Ctx) (F : List Var) (r : Rhs) : Option (Entry × Ctx) :=
  match packRhs D Γ F r with
  | some p => some p
  | none => inferRhs2c D Γ F r

theorem inferRhs2p_ok {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : inferRhs2p D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  unfold inferRhs2p at h
  split at h
  · rename_i p hp
    cases h
    exact packRhs_ok hs hD hp
  · exact inferRhs2c_ok hs hD h

end C
