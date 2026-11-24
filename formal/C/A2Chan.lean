import C.A2Data

/-!
# C8c: A3.4's channels and A3.2's locks, decided (AGORA-975)

A `Channel A` is a lock block whose payload is its queue and its closed
flag, `lk (prod (vec A) int)` (`Ty.ChanOf`): `chan_new` is `lockNew` of a
fresh queue and a 0, `Channel_share` is `lockClone`, and `chan_send`,
`chan_recv` / `chan_try_recv` and `chan_close` are one step each on the
payload. `chanRhs` computes A2's `RhsT` for these five forms, exactly as
their rules state them (formal/A2/Typing.lean): a live share of the right
type, and, for `lockNew` and `chanSend`, the value handed over as
`vec_push` takes it (`PushArg`, `pushArg2`). `inferRhs2c` is `inferRhs2d`
with them; `inferRhs2c_ok` is sound and keeps contexts inside the domain.
-/

namespace C

open A2

/-- A lock share's payload type. -/
def lkOf : Ty → Option Ty
  | .lk t => some t
  | _ => none

theorem lkOf_some {τ t : Ty} (h : lkOf τ = some t) : τ = .lk t := by
  cases τ <;> simp [lkOf] at h; subst h; rfl

/-- A channel share's element type (`Ty.ChanOf`): a lock share whose
    payload, under any destructor types, is `prod (vec s) int`. -/
def chanOf : Ty → Option Ty
  | .lk t => match t.undtor with
    | .prod (.vec s) .int => some s
    | _ => none
  | _ => none

theorem chanOf_some {τ s : Ty} (h : chanOf τ = some s) : τ.ChanOf s := by
  cases τ with
  | lk t =>
    simp only [chanOf] at h
    split at h
    · rename_i s' hu
      cases h
      exact ⟨t, rfl, hu⟩
    · cases h
  | _ => simp [chanOf] at h

/-- A2's `RhsT` for A3.2's lock and A3.4's channel forms, computed. -/
def chanRhs (D : List Var) (Γ : Ctx) (F : List Var) : Rhs → Option (Entry × Ctx)
  | .lockNew t y => match liveE2 Γ y with
    | some Ey =>
      if decide (Ey.ty = t) && t.lkPay && !t.holdsView && !t.hasFn && !t.hasGuard then
        match pushArg2 D Γ F y Ey t with
        | some (_, Γ1) => some (⟨.lk t, .own, true, [], [], false, false, false, false⟩, Γ1)
        | none => none
      else none
    | none => none
  | .lockClone a => match liveE2 Γ a with
    | some E => match lkOf E.ty with
      | some t => some (⟨.lk t, .own, true, [], [], false, false, false, false⟩, Γ)
      | none => none
    | none => none
  | .chanSend a y => match liveE2 Γ a with
    | some Ea => match chanOf Ea.ty with
      | some s => match liveE2 Γ y with
        | some Ey =>
          if decide (Ey.ty = s) then
            match pushArg2 D Γ F y Ey s with
            | some (_, Γ1) => some (intE, Γ1)
            | none => none
          else none
        | none => none
      | none => none
    | none => none
  | .chanRecv _ a => match liveE2 Γ a with
    | some E => match chanOf E.ty with
      | some s => some (⟨.sum .int s, .own, true, [], [], false, false, false, false⟩, Γ)
      | none => none
    | none => none
  | .chanClose a => match liveE2 Γ a with
    | some E => match chanOf E.ty with
      | some _ => some (intE, Γ)
      | none => none
    | none => none
  | _ => none

theorem chanRhs_ok {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : chanRhs D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  cases r with
  | lockNew t y =>
    simp only [chanRhs] at h
    split at h
    · rename_i Ey hEy
      obtain ⟨hy, hyl⟩ := liveE2_some hEy
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc
        obtain ⟨⟨⟨⟨hty, hlk⟩, hv⟩, hfn⟩, hg⟩ := hc
        split at h
        · rename_i Ds Γa hpa
          obtain ⟨pa, sa⟩ := pushArg2_sound hs hpa
          simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
          exact ⟨.lockNew hy hyl hty hlk ⟨hv, hfn⟩ hg pa, sa (hD y (by simp [Rhs.vars]))⟩
        · cases h
      · cases h
    · cases h
  | lockClone a =>
    simp only [chanRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨ha, hal⟩ := liveE2_some hE0
      split at h
      · rename_i t ht
        simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        exact ⟨.lockClone ha hal (lkOf_some ht), hs⟩
      · cases h
    · cases h
  | chanSend a y =>
    simp only [chanRhs] at h
    split at h
    · rename_i Ea hEa
      obtain ⟨ha, hal⟩ := liveE2_some hEa
      split at h
      · rename_i s hch
        split at h
        · rename_i Ey hEy
          obtain ⟨hy, hyl⟩ := liveE2_some hEy
          split at h
          · rename_i hty
            simp only [decide_eq_true_eq] at hty
            split at h
            · rename_i Ds Γa hpa
              obtain ⟨pa, sa⟩ := pushArg2_sound hs hpa
              simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
              exact ⟨.chanSend ha hal (chanOf_some hch) hy hyl hty pa, sa (hD y (by simp [Rhs.vars]))⟩
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | chanRecv w a =>
    simp only [chanRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨ha, hal⟩ := liveE2_some hE0
      split at h
      · rename_i s hch
        simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        exact ⟨.chanRecv ha hal (chanOf_some hch), hs⟩
      · cases h
    · cases h
  | chanClose a =>
    simp only [chanRhs] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨ha, hal⟩ := liveE2_some hE0
      split at h
      · rename_i s hch
        simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        exact ⟨.chanClose ha hal (chanOf_some hch), hs⟩
      · cases h
    · cases h
  | _ => simp [chanRhs] at h

/-- A2's `RhsT` for the core, data, lock and channel forms, computed. -/
def inferRhs2c (D : List Var) (Γ : Ctx) (F : List Var) (r : Rhs) : Option (Entry × Ctx) :=
  match chanRhs D Γ F r with
  | some p => some p
  | none => inferRhs2d D Γ F r

theorem inferRhs2c_ok {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : inferRhs2c D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  unfold inferRhs2c at h
  split at h
  · rename_i p hp
    cases h
    exact chanRhs_ok hs hD hp
  · exact inferRhs2d_ok hs hD h

end C
