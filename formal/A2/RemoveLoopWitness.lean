module

public import A2.PopWitness

@[expose] public section

/-!
  A2 — `vec_remove b i` through a borrow at a general index, as a loop
  (AGORA-889's second part; the first, AGORA-888, typed it unrolled).

      : ( Vec ( Vec i ) ) vv …            -- one element Vec of three numbers
      : ( Vec i ) b ( vec_at vv 0 )
      ( vec_remove b i )                  -- for every index i

  through the borrow `b` is, in the calculus's own steps (`StmtT.editB`):

      : j i
      ? < j ( vec_len b ) {
        ~ < + j 1 ( vec_len b ) {         -- each later element one place down
          : t ( vec_at b + j 1 )
          b[j] := t
          = j + j 1
        }
        vec_pop b                         -- and one less: the truncation to the last index
      } {}

  `main_safe i` and `main_no_leak i` hold for every `i`.  Out of range
  (`i ≥ vec_len b`) the program here leaves `b` as it is, where nurlc's
  `vec_remove` panics; both are memory-safe, and the encoding of the
  in-range case is the one the claim reads `vec_remove` of a number as.
-/

namespace A2.RemoveLoop

open A2.PopWitness
open A2.DynCell (NoRootb noRootb_empty)

/-! ### The program

    `vv` is 0, `w` 1, the number `z` 2, the borrow `b` 3, the index `j` 4
    and the moved number `t` 5. -/

/-- One round: the element after `j` is moved one place down. -/
def step : Stmt :=
  .letv 5 (.at 3 (.add (.var 4) (.lit 1)))
    (.seq (.edit true 3 (.set (.var 4) 5)) (.assign 4 (.expr (.add (.var 4) (.lit 1)))))

/-- `vec_remove b j` of a number, through the borrow `b`. -/
def removeAt : Stmt :=
  .ite (.lt (.var 4) (.len 3))
    (.seq (.while (.lt (.add (.var 4) (.lit 1)) (.len 3)) step) (popB 3))
    .skip

def main (i : Nat) : Stmt :=
  .letv 0 (.new str) (.letv 1 (.new .int) (.letv 2 (.expr (.lit 7))
    (.seq (.push 1 2) (.seq (.push 1 2) (.seq (.push 1 2)
      (.seq (.push 0 1)
        (.letv 3 (.at 0 (.lit 0)) (.letv 4 (.expr (.lit i)) removeAt))))))))

/-! ### A context the loop keeps -/

/-- An effect on a variable no entry depends on ends nothing. -/
theorem kill_noop {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var}
    (h : ∀ v E, Γ v = some E → ∀ d ∈ E.vdeps, d.root ≠ x) : A2.kill e hv x Γ = Γ := by
  funext v
  simp only [A2.kill]
  cases hv' : Γ v with
  | none => rfl
  | some E =>
    simp only [Option.map, A2.killE]
    rw [ite_eq_right]
    simp only [A2.hits, Bool.and_eq_true, List.any_eq_true, Bool.and_eq_true, beq_iff_eq, not_and,
      not_exists]
    intro _ d hd hr
    exact absurd hr (h v E hv' d hd)

/-- What the loop's body may assume of its context, and keeps. -/
structure LoopCtx (Γ : Ctx) : Prop where
  nr : NoRootb Γ
  h0 : Γ 0 = some Evv
  h3 : Γ 3 = some Eb
  h4 : Γ 4 = some intE
  dep : ∀ v E, Γ v = some E → ∀ d ∈ E.vdeps, (d.root = 0 → v = 3) ∧ d.root ≠ 4 ∧ d.root ≠ 5

/-- A change through `b` ends only what depends on `vv`: `b` itself, which
    the rule keeps. -/
theorem thru_keeps {Γ : Ctx} (hc : LoopCtx Γ) (op : Edit) :
    A2.setE (A2.killThru op str [⟨0, .inner⟩] Γ) 3 Eb = Γ := by
  funext v
  by_cases hv : v = 3
  · subst hv; simp [A2.setE, upd, hc.h3]
  · simp only [A2.setE, upd, ite_eq_right hv, A2.killThru, A2.thruDeps, memDeps, Kind.isName,
      Bool.not_false, List.filter_cons_of_pos, List.filter_nil, List.map_cons, List.map_nil,
      A2.killNames, List.foldr_cons, List.foldr_nil, A2.kill]
    cases hg : Γ v with
    | none => rfl
    | some E =>
      simp only [Option.map, A2.killE]
      rw [ite_eq_right]
      simp only [A2.hits, Bool.and_eq_true, List.any_eq_true, beq_iff_eq, not_and, not_exists]
      intro _ d hd hr
      exact fun _ => hv ((hc.dep v E hg d hd).1 hr)

theorem LoopCtx.set5 {Γ : Ctx} (hc : LoopCtx Γ) : ∀ v E, A2.setE Γ 5 intE v = some E →
    ∀ d ∈ E.vdeps, (d.root = 0 → v = 3) ∧ d.root ≠ 4 ∧ d.root ≠ 5 := by
  intro v E hv d hd
  by_cases h5 : v = 5
  · subst h5; simp [A2.setE, upd] at hv; subst hv; simp [intE, Entry.vdeps, Mode.ownSlot] at hd
  · simp only [A2.setE, upd, ite_eq_right h5] at hv; exact hc.dep v E hv d hd

/-- The loop's body ends in the context it starts in. -/
theorem step_typed {ξ : Exits} {Γ : Ctx} (hc : LoopCtx Γ) (h5 : Γ 5 = none) : StmtT P ξ Γ [] step Γ := by
  have nr5 : NoRootb (A2.setE Γ 5 intE) :=
    A2.DynCell.NoRootb.setE hc.nr (by simp [intE])
  have c5 : LoopCtx (A2.setE Γ 5 intE) :=
    ⟨nr5, by simp [A2.setE, upd, hc.h0], by simp [A2.setE, upd, hc.h3],
      by simp [A2.setE, upd, hc.h4], hc.set5⟩
  -- `b[j] := t`
  have hset := StmtT.editB (b := true) (P := P) (ξ := ξ.under 5) (F := []) (op := .set (.var 4) 5) (t := .int)
    (D := []) (Ex := Eb) (Ex1 := Eb) (Γ := A2.setE Γ 5 intE) (Γ1 := A2.setE Γ 5 intE) (x := 3)
    c5.h3 rfl rfl rfl rfl (by simp)
    (EditArg.set (Ey := intE) (ExprT.var c5.h4 rfl rfl) (by simp [A2.setE, upd]) rfl rfl PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide)
    c5.h3 rfl
    (thru_ok nr5 c5.h0 (fun y hy => by simp [Edit.stored] at hy; subst hy; decide) rfl (by simp)).toR
    (fun _ => rfl)
  have k5 : A2.setE (A2.killThru (.set (.var 4) 5) Eb.ty Eb.path (A2.setE Γ 5 intE)) 3 Eb
      = A2.setE Γ 5 intE := thru_keeps c5 _
  rw [k5] at hset
  -- `= j + j 1`
  have hasg := StmtT.assign (P := P) (ξ := ξ.under 5) (F := []) (Γ := A2.setE Γ 5 intE)
    (Γ1 := A2.setE Γ 5 intE) (x := 4) (r := .expr (.add (.var 4) (.lit 1))) (Ex := intE) (E := intE)
    c5.h4 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr (ExprT.add (ExprT.var c5.h4 rfl rfl) ExprT.lit)) rfl
    (by simp [intE, Entry.vdeps, Mode.ownSlot, roots]) (by simp [c5.h4])
    (nrPin nr5 _) (nrDtor nr5 _ _ _) rfl
  have hk4 : A2.kill .replace false 4 (A2.setE Γ 5 intE) = A2.setE Γ 5 intE :=
    kill_noop (fun v E hv d hd => (c5.dep v E hv d hd).2.1)
  have he4 : A2.setE (A2.kill .replace false 4 (A2.setE Γ 5 intE)) 4 { intE with mode := intE.mode }
      = A2.setE Γ 5 intE := by
    rw [hk4]; funext v
    by_cases hv : v = 4
    · subst hv; simp [A2.setE, upd, hc.h4]; rfl
    · simp [A2.setE, upd, hv]
  rw [he4] at hasg
  -- the round
  have hl := StmtT.letv (P := P) (ξ := ξ) (F := []) (x := 5) (E := intE) (Γ := Γ) (Γ1 := Γ)
    (r := .at 3 (.add (.var 4) (.lit 1))) rfl h5 (by simp)
    (RhsT.at (E := Eb) (t := .int) hc.h3 rfl rfl (ExprT.add (ExprT.var hc.h4 rfl rfl) ExprT.lit))
    (StmtT.seq rfl hset hasg) (nrEnd nr5 _)
  have hx5 : A2.exitScope 5 (A2.setE Γ 5 intE) = Γ := by
    have hk5 : A2.kill .replace false 5 (A2.setE Γ 5 intE) = A2.setE Γ 5 intE :=
      kill_noop (fun v E hv d hd => (c5.dep v E hv d hd).2.2)
    simp only [A2.exitScope, hk5]
    funext v
    by_cases hv : v = 5
    · subst hv; simp [upd, h5]
    · simp [A2.setE, upd, hv]
  rw [hx5] at hl
  exact hl

/-- `vec_remove b j` through the borrow, in range: the loop, then the pop. -/
theorem removeAt_typed {ξ : Exits} {Γ : Ctx} (hc : LoopCtx Γ) (h5 : Γ 5 = none) :
    StmtT P ξ Γ [] removeAt Γ := by
  have hw : StmtT P ξ Γ [] (.while (.lt (.add (.var 4) (.lit 1)) (.len 3)) step) Γ :=
    StmtT.while rfl (ExprT.lt (ExprT.add (ExprT.var hc.h4 rfl rfl) ExprT.lit) (ExprT.len hc.h3 rfl rfl))
      (step_typed hc h5)
  have hp := pop_typed (ξ := ξ) (u := .int) (k := .inner) hc.nr hc.h3 rfl hc.h0 rfl rfl rfl (by simp)
  have hp' : StmtT P ξ Γ [] (popB 3) Γ := by
    have k : A2.setE (A2.killThru (.trunc (.dec (.len 3))) (.vec .int) [⟨0, .inner⟩] Γ) 3 Eb = Γ :=
      thru_keeps hc _
    rw [k] at hp; exact hp
  exact StmtT.ite rfl rfl (ExprT.lt (ExprT.var hc.h4 rfl rfl) (ExprT.len hc.h3 rfl rfl))
    (StmtT.seq rfl hw hp') StmtT.skip

theorem main_typed (i : Nat) : ∃ Δ, StmtT P .none (fun _ => none) [] (main i) Δ := by
  apply Exists.intro
  refine' StmtT.letv (x := 0) rfl rfl (by simp) (RhsT.new (t := str) rfl) ?_ ?_
  rotate_left
  · refine' StmtT.letv (x := 1) rfl (by look) (by simp) (RhsT.new (t := .int) rfl) ?_ ?_
    rotate_left
    · refine' StmtT.letv (x := 2) rfl (by look) (by simp) (RhsT.expr ExprT.lit) ?_ ?_
      rotate_left
      · refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Ew) (Ey := intE) (Ex1 := Ew) (t := .int) (D := [])
          all_goals fin
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Ew) (Ey := intE) (Ex1 := Ew) (t := .int) (D := [])
          all_goals fin
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Ew) (Ey := intE) (Ex1 := Ew) (t := .int) (D := [])
          all_goals fin
        refine' StmtT.seq rfl ?_ ?_
        rotate_left 2
        · apply StmtT.push (Ex := Evv) (Ey := Ew) (Ex1 := Evv) (t := str) (D := [])
          · look
          · rfl
          · rfl
          · exact Or.inl rfl
          · simp
          · look
          · rfl
          · rfl
          · decide
          · exact PushArg.move (by simp [str, Ty.owning]) rfl (by simp) (nrPin (by noroot) _)
              (nrDtor (by noroot) _ _ _)
          all_goals fin
        · -- `: ( Vec i ) b ( vec_at vv 0 )`
          refine' StmtT.letv (x := 3) (E := Eb) rfl (by look) (by simp)
            (RhsT.at (E := Evv) (t := str) (by look) rfl rfl ExprT.lit) ?_ ?_
          rotate_left
          · -- `: i j i`
            refine' StmtT.letv (x := 4) (E := intE) rfl (by look) (by simp) (RhsT.expr ExprT.lit) ?_ ?_
            rotate_left
            · refine removeAt_typed ⟨by noroot, by look, by look, by look, ?_⟩ (by look)
              intro v E hv d hd
              rcases v with _ | _ | _ | _ | _ | _ | v <;>
                simp [A2.setE, upd, A2.kill, killE, hits, Entry.vdeps, Mode.ownSlot, str, vstr, intE,
                  Evv, Ew, Eb] at hv <;>
                (try subst hv) <;>
                (first
                  | (simp [Entry.vdeps, Mode.ownSlot, ownHeld, Ty.holdsView] at hd; done)
                  | (simp [Entry.vdeps, Mode.ownSlot] at hd; subst hd; decide)
                  | skip)
            · exact nrEnd (by noroot) _
          · exact nrEnd (by noroot) _
      · exact nrEnd (by noroot) _
    · exact nrEnd (by noroot) _
  · exact nrEnd (by noroot) _

theorem main_vars (i : Nat) : (main i).vars = (main 0).vars := rfl

theorem main_vars_lt (i : Nat) : ∀ v ∈ (main i).vars, v < 6 := by
  rw [main_vars]; decide

/-- A run of the program, from the empty store, for every index `i`, never
    touches memory it may not: each read through `b` sees its current
    length. -/
theorem main_safe (i : Nat) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) (main i) (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed i
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main, removeAt, step, popB, Stmt.codesOK, Rhs.codeOK]) (main_vars_lt i) hr

/-- ... and when it ends, everything it allocated is freed. -/
theorem main_no_leak (i : Nat) {m' : Mem} (hr : Steps P (emptyMem 6) (main i) (.ok m' .skip)) :
    ∀ k, m'.alloc k = false := by
  obtain ⟨Δ, ht⟩ := main_typed i
  exact no_leak_end prog_ok prog_codes ht rfl
    (by simp [main, removeAt, step, popB, Stmt.codesOK, Rhs.codeOK]) (main_vars_lt i) hr

end A2.RemoveLoop
