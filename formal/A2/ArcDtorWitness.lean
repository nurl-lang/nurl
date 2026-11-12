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
  have hm := Mem.sweepD_marks (n := 0) (f := 0) (u := T) (Or.inl rfl) hk hv hb
  exact ⟨hm, settle_reaps h ⟨k, 0, 0, T, p, hm⟩⟩

/-! ### Agora #755: an `Arc` of a `Vec` of destructor values

`mainV` makes a destructor value, pushes it into a `Vec` of them (bound by
`letd` at `vec DT`, as `A2.DtorWitness.main5`), moves the `Vec` into an `Arc`,
clones the share and drops both shares, the clone first:

```
: a 1  : b 2  :drop x ( pair a b )  :drop v ( vec_new DT )  ( vec_push v x )
: s ( arc_new v )  : c ( arc_clone s )      -- c's scope ends, then s's
```

It is typed (`mainV_typed`; before Agora #755 `Ty.ok` refused `arc (vec DT)`:
a drained `Vec` as a share's payload), safe (`mainV_safe`) and, finished,
leaks nothing (`mainV_no_leak`).  When nothing refers to the block any more,
the marking sweep marks it `dead`, its payload in it, and the thread's next
step is the reap (`last_dropV_reaps`), which binds the `Vec` at its own type
in a destructor frame of `dfn` (`scopeD _ 0 skip`): that frame's end drains
the `Vec`, element 0 first, each element to a `letd` frame of its own that
runs `dfn` (`reapV_drains`, over `Step.scopeDDrain`), as nurlc's drop of the
last `Arc<Vec<D>>` share drops the `Vec`'s elements in index order.  As for
`main`, the theorems are of stores and steps; none traces the program's run. -/

/-- `: a 1  : b 2  :drop x ( pair a b )  :drop v ( vec_new DT )  ( vec_push v x )
     : s ( arc_new v )  : c ( arc_clone s )` -/
def mainV : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letv 4 (.arcNew (.vec DT) 3) (.letv 5 (.arcClone 4) .skip))))))

/-- The share's entry: owned, holding nothing. -/
def ESV : Entry := ⟨.arc (.vec DT), .own, true, [], [], false, false⟩

theorem ESV_flags : ESV.mode ≠ .rootb ∧ ESV.dtor = false ∧ ESV.dbind = false := by simp [ESV]

/-- **An `Arc` of a `Vec` of destructor values is typed** (Agora #755:
    `Ty.ok` admits `arc (vec (dtor f u))`, `RhsT.arcNew` takes the `Vec`). -/
theorem mainV_typed : ∃ Δ, StmtT P (fun _ => none) [] mainV Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  -- the `Vec`, as in `A2.DtorWitness.main5`
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K4 : Ctx := A2.setE K3 3 EV
  have hK4 : NoRootb K4 := hK3.setE (by rw [hEVe]; simp)
  let K5 : Ctx := A2.setE (kill .replace false 2 K4) 2 { ED with live := false, dtor := false }
  have hK5 : NoRootb K5 := (hK4.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove : PushArg K4 [] 2 ED DT ED.held K5 :=
    PushArg.move (Γ := K4) (F := []) (y := 2) (E := ED) (t := DT) rfl (by rw [hEDe]) (by simp)
      (hK4.noPin _) (DtorSafe.of_none (fun v E h => (hK4 v E h).2.1) _ _ _)
  have hK53 : K5 3 = some EV := by
    simp [K5, K4, A2.setE, upd, A2.kill, killE, hits, hEVe, Entry.vdeps, Mode.ownSlot]
  have hpush := StmtT.push (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 3) (y := 2) (Ex := EV) (Ey := ED)
    (Ex1 := EV) (t := DT) (D := ED.held) (by simp [K4, A2.setE]) (by rw [hEVe]) (by rw [hEVe])
    (Or.inl (by rw [hEVe])) (by simp) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) (by rw [hEDe])
    (by decide) hmove (by rw [hEDe]; simp [roots]) hK53 (by rw [hEVe])
    (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _) (by rw [hEVe]; simp)
  let E3 : Entry := { EV with held := EV.held ++ ownHeld true DT ED.held }
  have hE3e : E3 = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [E3, hEVe, hEDe, ownHeld]
  let K6 : Ctx := A2.setE (kill .realloc DT.holdsView 3 K5) 3 E3
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hE3e]; simp)
  -- `arc_new v`: the `Vec` moves into the block
  let K7 : Ctx := A2.setE (kill .replace false 3 K6) 3 { E3 with live := false, dtor := false }
  have hK7 : NoRootb K7 := (hK6.kill _ _ _).setE (by rw [hE3e]; simp)
  have hmove2 : PushArg K6 [] 3 E3 (.vec DT) E3.held K7 :=
    PushArg.move (Γ := K6) (F := []) (y := 3) (E := E3) (t := .vec DT) rfl (by rw [hE3e]) (by simp)
      (hK6.noPin _) (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
  have hK63 : K6 3 = some E3 := by simp [K6, A2.setE]
  have hnewA : RhsT K6 [] (.arcNew (.vec DT) 3) ESV K7 :=
    RhsT.arcNew hK63 (by rw [hE3e]) (by rw [hE3e]) (Or.inr rfl)
      ⟨by simp [DT, T, Ty.holdsView], by simp [DT, T, Ty.hasFn]⟩ (by simp [DT, T, Ty.hasCell]) hmove2
  let K8 : Ctx := A2.setE K7 4 ESV
  have hK8 : NoRootb K8 := hK7.setE ESV_flags
  -- `arc_clone s`
  have hK84 : K8 4 = some ESV := by simp [K8, A2.setE]
  have hclone : RhsT K8 [] (.arcClone 4) ESV K8 := RhsT.arcClone hK84 rfl rfl
  let K9 : Ctx := A2.setE K8 5 ESV
  have hK9 : NoRootb K9 := hK8.setE ESV_flags
  have hc := StmtT.letv (P := P) (x := 5) (r := .arcClone 4) (E := ESV) (F := []) (Γ := K8) (Γ1 := K8)
    (s := .skip) rfl (by simp [K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hclone
    StmtT.skip (hK9.endOK _) (fun _ => rfl)
  have hs := StmtT.letv (P := P) (x := 4) (r := .arcNew (.vec DT) 3) (E := ESV) (F := []) (Γ := K6)
    (Γ1 := K7) (s := .letv 5 (.arcClone 4) .skip) rfl
    (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hnewA hc
    ((hK9.exitScope 5).endOK _) (fun _ => rfl)
  have hseq := StmtT.seq (P := P) rfl hpush hs
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (s := .seq (.push 3 2) (.letv 4 (.arcNew (.vec DT) 3) (.letv 5 (.arcClone 4) .skip))) (E := EN)
    (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hseq
    (((hK9.exitScope 5).exitScope 4).endOK _)
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letv 4 (.arcNew (.vec DT) 3) (.letv 5 (.arcClone 4) .skip))))
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv
    ((((hK9.exitScope 5).exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    (((((hK9.exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((((hK9.exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- `arc_new` of the `Vec` names the elements' destructor, one the program
    checked (`Rhs.codeOK`). -/
theorem mainV_codes : mainV.codesOK P := by
  simp only [mainV, Stmt.codesOK, Rhs.codeOK]
  exact ⟨trivial, trivial, trivial, trivial, trivial, arcNew_codeOK (n := 1) drop_ok, trivial, trivial⟩

/-- **Every run of it is safe.** -/
theorem mainV_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) mainV (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := mainV_typed
  exact memory_safe prog_ok prog_codes ht rfl mainV_codes (by decide) hr

/-- **... and leaks nothing**: when it finishes, every address is freed
    (`no_leak_end`; that the `Vec` was reaped and drained on the way is read
    off the steps, `last_dropV_reaps` / `reapV_drains`, not stated here). -/
theorem mainV_no_leak {m' : Mem} (hr : Steps P (emptyMem 6) mainV (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := mainV_typed
  exact no_leak_end prog_ok prog_codes ht rfl mainV_codes (by decide) hr

/-- **The last share's drop hands the `Vec` to a destructor frame of the same
    thread**: when no slot's value and no block's payload refers to the
    `Arc`'s block, the marking sweep marks it `dead`, its payload in it
    (`Mem.sweepD_marks`, at the nest `vec (dtor 0 T)`), and the thread's next
    step is a reap (`settle_reaps`). -/
theorem last_dropV_reaps {m : Mem} {k : Nat} {p : Val} (hk : m.blk k = some ⟨.vec DT, .arc, some p⟩)
    (hv : ∀ x o v, m.st x = some ⟨o, some v⟩ → ¬ Refers m.blk v k)
    (hb : ∀ k' bl', m.blk k' = some bl' → ¬ Refers m.blk bl'.keeps k)
    {s s' : Stmt} {m' : Mem} (h : Settle P m.sweepD s m' s') :
    m.sweepD.blk k = some ⟨.vec DT, .dead, some p⟩ ∧
      ∃ m1 s1, Step P m.sweepD s (.ok m1 s1) ∧ ReapMem m.sweepD m1 := by
  have hm := Mem.sweepD_marks (n := 1) (f := 0) (u := T) (Or.inl rfl) hk hv hb
  exact ⟨hm, settle_reaps h ⟨k, 1, 0, T, p, hm⟩⟩

/-- **The reap binds the `Vec` at its own type, and its frame drains it**: at
    a redex `r`, `Step.reap` of the `dead` block moves the `Vec` to the fresh
    slot `m.nv`, owned, and puts the frame `scopeD m.nv 0 skip` before `r`;
    from a store where that slot still holds it (and no orphan awaits), the
    frame's end is the drain and nothing else (`A2.Dtor.scopeD_end_drains`):
    element 0 moves out to a `letd` frame of `dfn` of its own. -/
theorem reapV_drains {m : Mem} {k : Nat} {t : Ty} {c d : Nat} {e : Val} {es : List Val}
    (hk : m.blk k = some ⟨.vec DT, .dead, some (.node t c d (e :: es))⟩)
    (hnc : ∀ c', ¬ Sub (.cell c') (.node t c d (e :: es))) {r : Stmt} (hr : r.src = true) :
    ∃ m1, Step P m r (.ok m1 (.seq (.scopeD m.nv 0 .skip) r)) ∧
      m1.st m.nv = some ⟨true, some (.node t c d (e :: es))⟩ ∧
      ∀ m2 : Mem, m2.st m.nv = some ⟨true, some (.node t c d (e :: es))⟩ → ¬ Orphan m2 →
        ∀ r', Step P m2 (.scopeD m.nv 0 .skip) r' ↔
          r' = .ok { m2 with nv := m2.nv + 1 } (.scopeD m.nv 0 (.letd m2.nv 0 (.remove m.nv (.lit 0)) .skip)) := by
  refine ⟨_, Step.reap (n := 1) (f := 0) (u := T) hr hk hnc, by simp [Mem.set, upd], fun m2 hx hno r' => ?_⟩
  obtain ⟨h1, h2⟩ := A2.Dtor.scopeD_end_drains (P := P) (f := 0) hx hno
  exact ⟨h2 r', fun h => h ▸ h1⟩

end A2.ArcDtorWitness
