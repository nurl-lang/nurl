import A2.DtorWitness
import A2.Settle

/-! A2 — Agora #610, a witness: an `Arc` of a destructor value.

`main` makes a destructor value (`DT`, the struct `T` whose destructor is
`dfn`, `A2/DtorWitness.lean`), moves it into an `Arc` (`arc_new`), clones the
share and drops both shares, the clone first:

```
: a 1  : b 2  :drop d ( pair a b )
: s ( arc_new d )  : c ( arc_clone s )      -- c's scope ends, then s's
```

It is typed (`main_typed`, which #544's first cut refused: `Ty.ok` asked an
`Arc`'s payload to own no destructor value), and every run of it is safe
(`main_safe`) and, finished, leaks nothing (`main_no_leak`).  What the
drops do is the marking sweep's, stated of stores, not of this program's
run (which no theorem here traces): while a slot holds a share (`s`, after
the clone's scope ends) the block is kept as it was (`Mem.sweepD_keeps`);
when nothing refers to it any more (after `s`'s scope ends) the marking
sweep marks it `dead`, and the same thread's next step is the reap that
hands the payload to a destructor frame running `dfn` (`last_drop_reaps`,
`settle_reaps`, `Step.reap`). -/

namespace A2.ArcDtorWitness
open A2.DtorWitness
open A2.DynCell (NoRootb noRootb_empty)

/-- `: a 1  : b 2  :drop d ( pair a b )  : s ( arc_new d )  : c ( arc_clone s )` -/
def main : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2)) (.letd 2 0 (.pair 0 1)
    (.letv 3 (.arcNew DT 2) (.letv 4 (.arcClone 3) .skip))))

/-- The share's entry: owned, holding nothing. -/
def ES : Entry := ⟨.arc DT, .own, true, [], [], false, false⟩

theorem ES_flags : ES.mode ≠ .rootb ∧ ES.dtor = false ∧ ES.dbind = false := by simp [ES]

/-- **An `Arc` of a destructor value is typed** (Agora #610: `Ty.ok` admits
    `arc (dtor f u)`, `RhsT.arcNew` takes the value), as its clone is. -/
theorem main_typed : ∃ Δ, StmtT P (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  have hD0 : NoDeps (fun _ => none) := fun _ _ h => by cases h
  have hD1 : NoDeps K1 := hD0.setE rfl
  have hD2 : NoDeps K2 := hD1.setE rfl
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hED : ED.mode ≠ .rootb ∧ ED.dtor = false ∧ ED.dbind = false := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE hED
  have hD3 : NoDeps K3 := hD2.setE (by simp [ED, EP, Entry.arm, Entry.vdeps])
  have hK3d : K3 2 = some ED := by simp [K3, A2.setE]
  -- `arc_new d`: `d` moves into the block
  let ED' : Entry := { ED with live := false, dtor := false }
  let K3' : Ctx := A2.setE K3 2 ED'
  have hkill : A2.kill .replace false 2 K3 = K3 := hD3.kill_eq _ _ _
  have hnew : RhsT K3 [] (.arcNew DT 2) ES K3' := by
    have h := RhsT.arcNew (Γ := K3) (F := []) (t := DT) (y := 2) (Ey := ED) hK3d
      (by simp [ED, Entry.arm, EP]) (by simp [ED, Entry.arm]) (Or.inr rfl)
      ⟨by simp [DT, T, Ty.holdsView], by simp [DT, T, Ty.hasFn]⟩ (by simp [DT, T, Ty.hasCell])
      (PushArg.move (by simp [DT, T, Ty.owning]) (by simp [ED, Entry.arm, EP]) (by simp)
        (hK3.noPin 2) (DtorSafe.of_none (fun v E h => (hK3 v E h).2.1) _ _ _))
    rw [hkill] at h; exact h
  have hK3' : NoRootb K3' := hK3.setE (by simp [ED', ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView])
  let K4 : Ctx := A2.setE K3' 3 ES
  have hK4 : NoRootb K4 := hK3'.setE ES_flags
  have hK4s : K4 3 = some ES := by simp [K4, A2.setE]
  -- `arc_clone s`
  have hclone : RhsT K4 [] (.arcClone 3) ES K4 := RhsT.arcClone hK4s rfl rfl
  let K5 : Ctx := A2.setE K4 4 ES
  have hK5 : NoRootb K5 := hK4.setE ES_flags
  have hc := StmtT.letv (P := P) (x := 4) (r := .arcClone 3) (E := ES) (F := []) (Γ := K4) (Γ1 := K4)
    (s := .skip) rfl (by simp [K4, K3', K3, K2, K1, A2.setE]) (by simp) hclone StmtT.skip
    (hK5.endOK _) (fun _ => rfl)
  have hs := StmtT.letv (P := P) (x := 3) (r := .arcNew DT 2) (E := ES) (F := []) (Γ := K3) (Γ1 := K3')
    rfl (by simp [K3, K2, K1, A2.setE]) (by simp) hnew hc ((hK5.exitScope 4).endOK _) (fun _ => rfl)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE]) (by simp) hpair rfl
    (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hs
    (((hK5.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    ((((hK5.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    (((((hK5.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `arc_new` of the destructor value names the destructor the program
    checked (`Rhs.codeOK`). -/
theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.codesOK, Rhs.codeOK, DT]
  exact ⟨trivial, trivial, trivial, arcNew_codeOK (n := 0) drop_ok, trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **... and leaks nothing**: when it finishes, the payload's destructor has
    been handed its value and every address is freed (no orphan is left,
    `Steps.ok_swept`). -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 5) main (.ok m' .skip)) : ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- **The last share's drop hands the payload to a destructor frame of the
    same thread**: when no slot's value and no block's payload refers to
    the `Arc`'s block (the last share's scope has ended), the marking sweep
    that ends the step marks it `dead`, its payload in it
    (`Mem.sweepD_marks`), so the thread's next step is a reap (`Settle`
    asks one before anything else runs, `settle_reaps`; one can be taken,
    `orphan_reaps`).  `Step.reap` moves the payload to a fresh binding in a
    frame `scopeD _ 0 skip`, whose end calls `dfn` on it
    (`A2.Dtor.scopeD_end_runs_dtor`).  While a share is still in a slot (the
    clone's scope ended first) the block is kept as it was
    (`Mem.sweepD_keeps`). -/
theorem last_drop_reaps {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨DT, .arc, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k)
    {s s' : Stmt} {m' : Mem} (h : Settle P m.sweepD s m' s') :
    m.sweepD.blk k = some ⟨DT, .dead, some p⟩ ∧
      ∃ m1 s1, Step P m.sweepD s (.ok m1 s1) ∧ ReapMem m.sweepD m1 := by
  have hm := Mem.sweepD_marks (n := 0) (f := 0) (u := T) hk hv hb
  exact ⟨hm, settle_reaps h ⟨k, 0, 0, T, p, hm⟩⟩

end A2.ArcDtorWitness
