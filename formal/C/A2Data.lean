module

public import C.A2Stmt

@[expose] public section

/-!
# C8: A2's struct and enum right-hand sides, decided (AGORA-970)

`inferRhs2d` extends C6 with A2's data forms. A struct literal (`pair`,
each field through `PushArg`), a field read (`fst` / `snd`, not fresh), an
enum literal (`inl` / `inr`), a payload read (`getl` / `getr`, not fresh),
and a match by value (`takel` / `taker`, the payload moving out). It is
proven sound (`inferRhs2d_sound`), and it keeps contexts inside the domain
(`inferRhs2d_supported`).
-/

namespace C

open A2

def prodOf : Ty → Option (Ty × Ty)
  | .prod a b => some (a, b)
  | _ => none

def sumOf : Ty → Option (Ty × Ty)
  | .sum a b => some (a, b)
  | _ => none

theorem prodOf_some {t a b : Ty} (h : prodOf t = some (a, b)) : t = .prod a b := by
  cases t <;> simp [prodOf] at h; obtain ⟨rfl, rfl⟩ := h; rfl

theorem sumOf_some {t a b : Ty} (h : sumOf t = some (a, b)) : t = .sum a b := by
  cases t <;> simp [sumOf] at h; obtain ⟨rfl, rfl⟩ := h; rfl

/-- `takel`'s type premise: an enum, or an enum under its destructor type
    whose first payload holds a destructor value. -/
def takeTyL : Ty → Option (Ty × Ty)
  | .sum a b => some (a, b)
  | .dtor _ (.sum a b) => if a.holdsDtor then some (a, b) else none
  | _ => none

/-- `taker`'s: the same for the second payload. -/
def takeTyR : Ty → Option (Ty × Ty)
  | .sum a b => some (a, b)
  | .dtor _ (.sum a b) => if b.holdsDtor then some (a, b) else none
  | _ => none

theorem takeTyL_some {t a b : Ty} (h : takeTyL t = some (a, b)) :
    t = .sum a b ∨ ∃ f, t = .dtor f (.sum a b) ∧ a.holdsDtor = true := by
  cases t with
  | sum a' b' => simp [takeTyL] at h; obtain ⟨rfl, rfl⟩ := h; exact Or.inl rfl
  | dtor f u =>
    cases u with
    | sum a' b' =>
      by_cases hd : a'.holdsDtor = true
      · simp [takeTyL, hd] at h; obtain ⟨rfl, rfl⟩ := h; exact Or.inr ⟨f, rfl, hd⟩
      · simp [takeTyL, hd] at h
    | _ => simp [takeTyL] at h
  | _ => simp [takeTyL] at h

theorem takeTyR_some {t a b : Ty} (h : takeTyR t = some (a, b)) :
    t = .sum a b ∨ ∃ f, t = .dtor f (.sum a b) ∧ b.holdsDtor = true := by
  cases t with
  | sum a' b' => simp [takeTyR] at h; obtain ⟨rfl, rfl⟩ := h; exact Or.inl rfl
  | dtor f u =>
    cases u with
    | sum a' b' =>
      by_cases hd : b'.holdsDtor = true
      · simp [takeTyR, hd] at h; obtain ⟨rfl, rfl⟩ := h; exact Or.inr ⟨f, rfl, hd⟩
      · simp [takeTyR, hd] at h
    | _ => simp [takeTyR] at h
  | _ => simp [takeTyR] at h

/-- A2's `RhsT` for the core and data forms, computed. -/
def inferRhs2d (D : List Var) (Γ : Ctx) (F : List Var) : Rhs → Option (Entry × Ctx)
  | .pair y z => match liveE2 Γ y with
    | some Ey => match pushArg2 D Γ F y Ey Ey.ty with
      | some (Dy, Γ1) => match liveE2 Γ1 z with
        | some Ez => match pushArg2 D Γ1 F z Ez Ez.ty with
          | some (Dz, Γ2) =>
            if !Ez.mode.ownSlot || !(decide (z ∈ roots Dy)) then
              some (⟨.prod Ey.ty Ez.ty, .own, true, [], Dy ++ Dz, false, false, false, false⟩, Γ2)
            else none
          | none => none
        | none => none
      | none => none
    | none => none
  | .fst y => match liveE2 Γ y with
    | some E => match prodOf E.ty.undtor with
      | some (a, _) => some ({ projE y E a with fresh := false, heldFresh := false }, Γ)
      | none => none
    | none => none
  | .snd y => match liveE2 Γ y with
    | some E => match prodOf E.ty.undtor with
      | some (_, b) => some ({ projE y E b with fresh := false, heldFresh := false }, Γ)
      | none => none
    | none => none
  | .getl y => match liveE2 Γ y with
    | some E => match sumOf E.ty.undtor with
      | some (a, _) => some ({ projE y E a with fresh := false, heldFresh := false }, Γ)
      | none => none
    | none => none
  | .getr y => match liveE2 Γ y with
    | some E => match sumOf E.ty.undtor with
      | some (_, b) => some ({ projE y E b with fresh := false, heldFresh := false }, Γ)
      | none => none
    | none => none
  | .inl y b => match liveE2 Γ y with
    | some Ey => if b.ok then (match pushArg2 D Γ F y Ey Ey.ty with
        | some (Ds, Γ1) => some (⟨.sum Ey.ty b, .own, true, [], Ds, false, false, false, false⟩, Γ1)
        | none => none) else none
    | none => none
  | .inr a y => match liveE2 Γ y with
    | some Ey => if a.ok then (match pushArg2 D Γ F y Ey Ey.ty with
        | some (Ds, Γ1) => some (⟨.sum a Ey.ty, .own, true, [], Ds, false, false, false, false⟩, Γ1)
        | none => none) else none
    | none => none
  | .takel y => match liveE2 Γ y with
    | some E => match takeTyL E.ty with
      | some (a, _) =>
        if decide (E.mode = .own) && decide (y ∉ F) && noPinB D Γ y && dtorSafeB D Γ .replace false y then
          some (compE E a, setE (kill .replace false y Γ) y { E with live := false, dtor := false })
        else none
      | none => none
    | none => none
  | .taker y => match liveE2 Γ y with
    | some E => match takeTyR E.ty with
      | some (_, b) =>
        if decide (E.mode = .own) && decide (y ∉ F) && noPinB D Γ y && dtorSafeB D Γ .replace false y then
          some (compE E b, setE (kill .replace false y Γ) y { E with live := false, dtor := false })
        else none
      | none => none
    | none => none
  | r => inferRhs2 D Γ F r

theorem inferRhs2d_ok {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : inferRhs2d D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  cases r with
  | pair y z =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i Ey hEy
      obtain ⟨hy, hyl⟩ := liveE2_some hEy
      split at h
      · rename_i Dy Γa hpa
        obtain ⟨pa, sa⟩ := pushArg2_sound hs hpa
        have sa' := sa (hD y (by simp [Rhs.vars]))
        split at h
        · rename_i Ez hEz
          obtain ⟨hz, hzl⟩ := liveE2_some hEz
          split at h
          · rename_i Dz Γb hpb
            obtain ⟨pb, sb⟩ := pushArg2_sound sa' hpb
            split at h
            · rename_i hc
              simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
              refine ⟨.pair hy hyl pa hz hzl pb (fun ho => ?_), sb (hD z (by simp [Rhs.vars]))⟩
              simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at hc
              rcases hc with h0 | h0
              · rw [ho] at h0; cases h0
              · exact h0
            · cases h
          · cases h
        · cases h
      · cases h
    · cases h
  | fst y =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i a b hp
        simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        exact ⟨.fst (f := false) hy hl (prodOf_some hp) (fun e => by cases e), hs⟩
      · cases h
    · cases h
  | snd y =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i a b hp
        simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        exact ⟨.snd (f := false) hy hl (prodOf_some hp) (fun e => by cases e), hs⟩
      · cases h
    · cases h
  | getl y =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i a b hp
        simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        exact ⟨.getl (f := false) hy hl (sumOf_some hp) (fun e => by cases e), hs⟩
      · cases h
    · cases h
  | getr y =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i a b hp
        simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
        exact ⟨.getr (f := false) hy hl (sumOf_some hp) (fun e => by cases e), hs⟩
      · cases h
    · cases h
  | inl y b =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i Ey hEy
      obtain ⟨hy, hyl⟩ := liveE2_some hEy
      split at h
      · rename_i hb
        split at h
        · rename_i Ds Γa hpa
          obtain ⟨pa, sa⟩ := pushArg2_sound hs hpa
          simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
          exact ⟨.inl hy hyl pa hb, sa (hD y (by simp [Rhs.vars]))⟩
        · cases h
      · cases h
    · cases h
  | inr a y =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i Ey hEy
      obtain ⟨hy, hyl⟩ := liveE2_some hEy
      split at h
      · rename_i ha
        split at h
        · rename_i Ds Γa hpa
          obtain ⟨pa, sa⟩ := pushArg2_sound hs hpa
          simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
          exact ⟨.inr hy hyl pa ha, sa (hD y (by simp [Rhs.vars]))⟩
        · cases h
      · cases h
    · cases h
  | takel y =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i a b ht
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          obtain ⟨⟨⟨hm, hF⟩, hp⟩, hd⟩ := hc
          simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
          have hty := takeTyL_some ht
          exact ⟨.takel hy hl hm hty hF (noPinB_sound hs hp) (dtorSafeB_sound hs hd),
            supported2_setE (supported2_kill hs _ _ _) (hD y (by simp [Rhs.vars])) _⟩
        · cases h
      · cases h
    · cases h
  | taker y =>
    simp only [inferRhs2d] at h
    split at h
    · rename_i E0 hE0
      obtain ⟨hy, hl⟩ := liveE2_some hE0
      split at h
      · rename_i a b ht
        split at h
        · rename_i hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          obtain ⟨⟨⟨hm, hF⟩, hp⟩, hd⟩ := hc
          simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
          have hty := takeTyR_some ht
          exact ⟨.taker hy hl hm hty hF (noPinB_sound hs hp) (dtorSafeB_sound hs hd),
            supported2_setE (supported2_kill hs _ _ _) (hD y (by simp [Rhs.vars])) _⟩
        · cases h
      · cases h
    · cases h
  | _ =>
    simp only [inferRhs2d] at h
    exact ⟨inferRhs2_sound hs h, inferRhs2_supported hs hD h⟩

end C
