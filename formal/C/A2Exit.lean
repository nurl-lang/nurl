import C.A2Call

/-!
# C7x: A2's `exit`, decided by obligations (AGORA-970, AGORA-975)

`checkStmt2` is sound for every exit context `ξ` and never looks at it, so it
cannot give `exit n`'s premise `ξ.up n Γ`. `checkX` returns, beside the end
context, the obligations its exits put on `ξ`: a list of `(n, Γ)`, each to
hold as `ξ n Γ`. Its soundness: for every `ξ` meeting them, `StmtT` holds.
A scope's body hands its obligations out through `Exits.under` (the scope's
end is checked at each one, `EndOK`, and the exit goes on from
`exitScope`); a block discharges its own (`n = 0`, the context is the
block's end) and hands the rest out one level up (`Exits.blk`). An `exit`
ends in its own context; a branch that ends in an `exit` takes the other
branch's end when the exit's rule allows it (`exitToB`), as a panicking
branch does. Any statement `checkStmt2` accepts has no obligation.
-/

namespace C

open A2

/-- The obligations an exit puts on the exits context. -/
abbrev Obl := List (Nat × Ctx)

def OblOK (ξ : Exits) (E : Obl) : Prop := ∀ e ∈ E, ξ e.1 e.2

theorem OblOK.append {ξ : Exits} {E1 E2 : Obl} (h : OblOK ξ (E1 ++ E2)) : OblOK ξ E1 ∧ OblOK ξ E2 :=
  ⟨fun e he => h e (List.mem_append_left _ he), fun e he => h e (List.mem_append_right _ he)⟩

/-- Through a scope of `x`: each exit ends `x`'s scope there. -/
def oblUnder (x : Var) (E : Obl) : Obl := E.map fun e => (e.1, exitScope x e.2)

theorem oblUnder_ok {ξ : Exits} {x : Var} {E : Obl} {D : List Var}
    (hE : ∀ e ∈ E, Supported2 e.2 D) (hend : E.all (fun e => endOK2B D e.2 x) = true)
    (h : OblOK ξ (oblUnder x E)) : OblOK (ξ.under x) E := by
  intro e he
  refine ⟨endOK2B_sound (hE e he) (List.all_eq_true.mp hend e he), ?_⟩
  exact h (e.1, exitScope x e.2) (List.mem_map.mpr ⟨e, he, rfl⟩)

/-- Out of a block whose end is `Δ`: an exit of it (`0`) is from `Δ`
    itself; one further out goes one level up. -/
def oblBlkOKB (D : List Var) (Δ : Ctx) (E : Obl) : Bool :=
  E.all fun e => e.1 != 0 || D.all (fun v => e.2 v == Δ v)

def oblBlk (E : Obl) : Obl := E.filterMap fun e => match e.1 with
  | 0 => none
  | n + 1 => some (n, e.2)

theorem oblBlk_ok {ξ : Exits} {Δ : Ctx} {E : Obl} {D : List Var} (hΔ : Supported2 Δ D)
    (hE : ∀ e ∈ E, Supported2 e.2 D) (hb : oblBlkOKB D Δ E = true) (h : OblOK ξ (oblBlk E)) :
    OblOK (ξ.blk Δ) E := by
  intro ⟨n, Γe⟩ he
  cases n with
  | zero =>
    have := List.all_eq_true.mp hb _ he
    simp only [bne_self_eq_false, Bool.false_or] at this
    exact Or.inl (eq_of_agree2 (hE _ he) hΔ this)
  | succ m =>
    exact h (m, Γe) (List.mem_filterMap.mpr ⟨(m + 1, Γe), he, rfl⟩)

/-- An exit from `Γ` may end in `Δ` (`StmtT.exit`'s conditions on the two),
    decided over the domain. -/
def exitToB (D : List Var) (Γ Δ : Ctx) : Bool :=
  ctxWF2B D Δ && nameWFB D Δ && freshOKB D Δ &&
  D.all fun v => (Γ v).isSome == (Δ v).isSome &&
    (match Δ v, Γ v with
     | some E, some E0 => decide (E.mode = E0.mode) && decide (E.ty = E0.ty) &&
         (!fixedB E0 || decide (E = E0)) &&
         -- DKeep
         (!(E.dbind && E.mode.ownSlot && (decide (E.ty ≠ .int) || decide (E.mode = .rootb))) ||
           (E0.dbind && E0.mode.ownSlot && (decide (E0.ty ≠ .int) || decide (E0.mode = .rootb)) &&
             E.vdeps.all fun d => d.kind.isName || decide (d ∈ E0.vdeps))) &&
         -- DStay
         (!(E0.dbind && E0.mode.ownSlot) || (E.dbind && E.mode.ownSlot))
     | none, none => true
     | _, _ => false)

theorem exitToB_sound {P : Prog} {ξ : Exits} {D : List Var} {Γ Δ : Ctx} {F : List Var} {n : Nat}
    (hs : Supported2 Γ D) (hsΔ : Supported2 Δ D) (h : exitToB D Γ Δ = true) (hx : ξ n Γ) :
    StmtT P ξ Γ F (.exit n) Δ := by
  simp only [exitToB, Bool.and_eq_true, List.all_eq_true] at h
  obtain ⟨⟨⟨hwf, hnw⟩, hfr⟩, hall⟩ := h
  have hv : ∀ v, ((Γ v).isSome == (Δ v).isSome) = true ∧ _ := fun v => by
    by_cases hd : v ∈ D
    · exact hall v hd
    · simp [hs v hd, hsΔ v hd]
  refine .exit (Or.inl hx) (ctxWF2B_sound hsΔ hwf) (nameWFB_sound hsΔ hnw) (fun v => ?_) (fun v E hE => ?_)
    (fun v E hE hdb hos hty _ => ?_) (fun v E0 hE0 hdb hos _ => ?_) (fun _ => freshOKB_sound hsΔ hfr)
  · have := (hv v).1; simpa using this
  · have := (hv v).2; rw [hE] at this
    revert this
    cases hΓ : Γ v with
    | none => intro h; cases h
    | some E0 =>
      intro h
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at h
      obtain ⟨⟨⟨⟨hm, ht⟩, hf⟩, _⟩, _⟩ := h
      refine ⟨E0, rfl, hm, ht, fun hfx => ?_⟩
      rcases hf with h0 | h0
      · exact absurd hfx (fixedB_sound h0)
      · exact h0
  · have := (hv v).2; rw [hE] at this
    revert this
    cases hΓ : Γ v with
    | none => intro h; cases h
    | some E0 =>
      intro h
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true', List.all_eq_true] at h
      obtain ⟨⟨_, hk⟩, _⟩ := h
      rcases hk with hk | hk
      · exfalso; revert hk; simp [hdb, hos]; rcases hty with h0 | h0 <;> simp [h0]
      · obtain ⟨⟨⟨hd0, ho0⟩, ht0⟩, hvd⟩ := hk
        refine ⟨E0, rfl, hd0, ho0, ?_, fun d hd hn => ?_⟩
        · rcases ht0 with h0 | h0
          · exact Or.inl h0
          · exact Or.inr h0
        · have := hvd d hd; simp [hn] at this; exact this
  · have := (hv v).2
    revert this
    cases hΔv : Δ v with
    | none => rw [hE0]; intro h; cases h
    | some E =>
      rw [hE0]
      intro h
      simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at h
      obtain ⟨_, hst⟩ := h
      rcases hst with h0 | h0
      · exfalso; simp [hdb, hos] at h0
      · exact ⟨E, rfl, h0.1, h0.2⟩

end C
