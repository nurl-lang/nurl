import C.A2Chan

/-!
# C8p: A2's closure literal with no captures by name, decided (AGORA-978)

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

theorem fits_any {te : Ty} (h : te.holdsDtor = false) : Cross.Fits .any te [] := by
  unfold Cross.Fits; simp [h]

theorem capsOK_nil (Γ : Ctx) (F : List Var) (D : List Dep) : CapsOK Γ F D [] :=
  ⟨List.nodup_nil, fun _ hc => by cases hc⟩

/-- A2's `RhsT` for a closure literal with no captures by name, computed. -/
def packRhs (D : List Var) (Γ : Ctx) (F : List Var) : Rhs → Option (Entry × Ctx)
  | .pack _ te ms y [] => match liveE2 Γ y with
    | some Ey =>
      if decide (Ey.ty = te) && !te.holdsDtor then
        match pushArg2 D Γ F y Ey te with
        | some (Ds, Γ1) =>
          some (⟨.fn ms .any, .own, true, [], Ds ++ capDeps [], false, false, false, false⟩, Γ1)
        | none => none
      else none
    | none => none
  | _ => none

theorem packRhs_ok {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : packRhs D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  cases r with
  | pack _ te ms y cs =>
    cases cs with
    | nil =>
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
            simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
            exact ⟨.pack hy hyl hty pa (capsOK_nil _ _ _) (fits_any hd), sa (hD y (by simp [Rhs.vars]))⟩
          · cases h
        · cases h
      · cases h
    | cons _ _ => simp [packRhs] at h
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
