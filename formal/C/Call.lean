module

public import C.Join

@[expose] public section

/-!
# C3: calls, decided (AGORA-970)

`CallT` checks a call against the callee's summary. Every argument must be
live and of its parameter's type. One that moves or may change must not be
frozen, and the callee must not reach it through another argument. The
result entry and the context after (`callRes`, `callPost`) are functions
already. `callB` decides the rest with loops over the parameters, and is
proven sound (`callB_sound`). `callPost` keeps a context inside its domain
when the arguments are in it (`callPost_supported`).
-/

namespace C

open A1

def isVecB : Ty → Bool
  | .vec _ => true
  | _ => false

theorem isVecB_sound {t : Ty} (h : isVecB t = true) : ∃ s, t = .vec s := by
  cases t <;> simp [isVecB] at h; exact ⟨_, rfl⟩

/-- `paramOK`, decided. -/
def paramOKB : PMode → Ty → Entry → Bool
  | .inp, t, E => decide (E.ty = t)
  | .sink, t, E => decide (E.ty = t) && decide (E.mode = .own) && isVecB t
  | .inout b, t, E => decide (E.ty = t) && canDoB E.mode b && isVecB t

theorem paramOKB_sound {m : PMode} {t : Ty} {E : Entry} (h : paramOKB m t E = true) : paramOK m t E := by
  cases m with
  | inp => simpa [paramOKB, paramOK] using h
  | sink =>
    simp only [paramOKB, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨h.1.1, h.1.2, isVecB_sound h.2⟩
  | inout b =>
    simp only [paramOKB, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨h.1.1, canDoB_sound h.1.2, isVecB_sound h.2⟩

/-- The checks on argument `i`. -/
def argOKB (Γ : Ctx) (F : List Var) (fn : Fn) (args : List Var) (i : Nat) : Bool :=
  match fn.params[i]?, Γ (args.getD i 0) with
  | some (m, t), some Ea =>
    Ea.live && paramOKB m t Ea &&
      (!m.moves || (!decide (args.getD i 0 ∈ F) && !decide (args.getD i 0 ∈ roots Ea.vdeps) &&
        (List.range fn.params.length).all fun j => j == i ||
          (args.getD j 0 != args.getD i 0 && !decide (args.getD i 0 ∈ roots (argE Γ (args.getD j 0)).vdeps))))
  | _, _ => false

/-- `CallT`, decided: the result entry and the context after, or a refusal. -/
def callB (P : Prog) (Γ : Ctx) (F : List Var) (f : Nat) (args : List Var) : Option (Entry × Ctx) :=
  match P[f]? with
  | some fn =>
    if args.length = fn.params.length ∧ (List.range fn.params.length).all (argOKB Γ F fn args) then
      some (callRes Γ fn args, callPost Γ fn args)
    else none
  | none => none

theorem callB_sound {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry} {Γ' : Ctx}
    (h : callB P Γ F f args = some (E, Γ')) : CallT P Γ F f args E Γ' := by
  unfold callB at h
  split at h
  · rename_i fn hfn
    split at h
    · rename_i hc
      obtain ⟨hlen, hall⟩ := hc
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨fn, hfn, hlen, fun i hi => ?_, rfl, rfl⟩
      have ha := List.all_eq_true.mp hall i (List.mem_range.mpr hi)
      unfold argOKB at ha
      rw [List.getElem?_eq_getElem hi] at ha
      split at ha
      · rename_i m t Ea hp hEa
        simp only [Option.some.injEq] at hp
        simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at ha
        obtain ⟨⟨hl, hpo⟩, hmv⟩ := ha
        refine ⟨Ea, hEa, hl, by rw [hp]; exact paramOKB_sound hpo, fun hm => ?_⟩
        rw [hp] at hm
        rcases hmv with hmv | ⟨⟨hF, hr⟩, hj⟩
        · simp only at hm; rw [hm] at hmv; cases hmv
        · refine ⟨hF, hr, fun j hj' hne => ?_⟩
          have := List.all_eq_true.mp hj j (List.mem_range.mpr hj')
          simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, bne_iff_ne, ne_eq,
            Bool.not_eq_true', decide_eq_false_iff_not] at this
          rcases this with e | ⟨h1, h2⟩
          · exact absurd e hne
          · exact ⟨h1, h2⟩
      · cases ha
    · cases h
  · cases h

theorem callPostAux_supported {Γ0 : Ctx} {fn : Fn} {args : List Var} {D : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx), Supported Γ D → (∀ a ∈ as, a ∈ D) →
      Supported (callPostAux Γ0 fn args ps as i Γ) D := by
  intro ps
  induction ps with
  | nil => intro as i Γ hs _; cases as <;> simpa [callPostAux] using hs
  | cons p ps ih =>
    intro as i Γ hs hD
    cases as with
    | nil => obtain ⟨m, t⟩ := p; cases m <;> simpa [callPostAux] using hs
    | cons a as =>
      obtain ⟨m, t⟩ := p
      cases m with
      | inp => exact ih as (i + 1) Γ hs (fun x hx => hD x (by simp [hx]))
      | sink =>
        exact ih as (i + 1) _ (supported_setE (supported_kill hs _ _ _) (hD a (by simp)) _)
          (fun x hx => hD x (by simp [hx]))
      | inout b =>
        exact ih as (i + 1) _ (supported_setE (supported_kill hs _ _ _) (hD a (by simp)) _)
          (fun x hx => hD x (by simp [hx]))

theorem callPost_supported {Γ : Ctx} {fn : Fn} {args D : List Var} (hs : Supported Γ D)
    (hD : ∀ a ∈ args, a ∈ D) : Supported (callPost Γ fn args) D :=
  callPostAux_supported fn.params args 0 Γ hs hD

end C
