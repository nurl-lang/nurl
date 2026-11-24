import A2.Typing

/-!
# C5: A2's expressions, decided (AGORA-970)

The first step of phase C for A2: `checkExpr2` decides A2's `ExprT`, which
adds the bounded decrement and an enum's tag (`isl`, through a destructor
type too) to A1's. It is proven sound (`checkExpr2_sound`). Rhs and
statements follow, as C0–C4 did for A1.
-/

namespace C

open A2

def checkExpr2 (Γ : Ctx) : Expr → Bool
  | .lit _ => true
  | .var x => match Γ x with
    | some E => E.live && decide (E.ty = .int)
    | none => false
  | .add a b => checkExpr2 Γ a && checkExpr2 Γ b
  | .lt a b => checkExpr2 Γ a && checkExpr2 Γ b
  | .dec a => checkExpr2 Γ a
  | .len x => match Γ x with
    | some E => E.live && (match E.ty with | .vec _ => true | _ => false)
    | none => false
  | .slen x => match Γ x with
    | some E => E.live && (match E.ty with | .slice _ => true | _ => false)
    | none => false
  | .isl x => match Γ x with
    | some E => E.live && (match E.ty.undtor with | .sum _ _ => true | _ => false)
    | none => false

theorem checkExpr2_sound {Γ : Ctx} : ∀ {e : Expr}, checkExpr2 Γ e = true → ExprT Γ e := by
  intro e
  induction e with
  | lit n => intro _; exact .lit
  | var x =>
    intro h; simp only [checkExpr2] at h; split at h
    · rename_i E hE; simp only [Bool.and_eq_true, decide_eq_true_eq] at h; exact .var hE h.1 h.2
    · cases h
  | add a b iha ihb => intro h; simp only [checkExpr2, Bool.and_eq_true] at h; exact .add (iha h.1) (ihb h.2)
  | lt a b iha ihb => intro h; simp only [checkExpr2, Bool.and_eq_true] at h; exact .lt (iha h.1) (ihb h.2)
  | dec a ih => intro h; simp only [checkExpr2] at h; exact .dec (ih h)
  | len x =>
    intro h; simp only [checkExpr2] at h; split at h
    · rename_i E hE; simp only [Bool.and_eq_true] at h; obtain ⟨hl, ht⟩ := h
      split at ht
      · rename_i t hty; exact .len hE hl hty
      · cases ht
    · cases h
  | slen x =>
    intro h; simp only [checkExpr2] at h; split at h
    · rename_i E hE; simp only [Bool.and_eq_true] at h; obtain ⟨hl, ht⟩ := h
      split at ht
      · rename_i t hty; exact .slen hE hl hty
      · cases ht
    · cases h
  | isl x =>
    intro h; simp only [checkExpr2] at h; split at h
    · rename_i E hE; simp only [Bool.and_eq_true] at h; obtain ⟨hl, ht⟩ := h
      split at ht
      · rename_i a b hty; exact .isl hE hl hty
      · cases ht
    · cases h

end C
