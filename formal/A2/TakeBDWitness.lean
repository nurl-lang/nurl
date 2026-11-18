import A2.DtorWitness
import A2.TakeBWitness

/-!
  A2 — a destructor value moved out through a borrow (AGORA-900).

      : a 1  : b 2  :drop x ( pair a b )        -- x of the destructor type DT
      :drop v ( vec_new DT )  ( vec_push v x )
      :drop vv ( vec_new ( Vec DT ) )  ( vec_push vv v )
      : ( Vec DT ) b ( vec_at vv 0 )
      : DT y ( vec_pop b )                       -- the destructor value moves out
      :drop z y                                  -- ... to its `letd`, first thing

  `StmtT.takeB` takes an element that holds a destructor value out through a
  borrow, when the new binding hands it to its `letd` first thing and is
  assigned nothing.  This is what a call's owned result does (A2-drop.3a,
  `takeB_typed`).  `z`'s frame runs the destructor.  This module types the
  program with A2's rules, on `A2.DtorWitness`'s program (the destructor
  `dfn`), and applies `memory_safe` and `no_leak_end`.
-/

namespace A2.TakeBDWitness

open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (P T DT EP drop_ok prog_ok prog_codes)

def body12 : Stmt :=
  .letv 5 (.at 4 (.lit 0)) (.takeB 5 (.dec (.len 5)) 6 (.letd 7 0 (.var 6) .skip))

def main12 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.seq (.push 4 3) body12))))))

theorem main12_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main12 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int (by simp [intE, Mode.ownSlot])
  -- the inner `Vec`, as in `main5`
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false, false⟩ := by
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
  have hpush := StmtT.push (ξ := .none) (P := P) (Γ := K4) (Γ1 := K5) (F := []) (x := 3) (y := 2) (Ex := EV) (Ey := ED)
    (Ex1 := EV) (t := DT) (D := ED.held) (by simp [K4, A2.setE, upd]) (by rw [hEVe]) (by rw [hEVe])
    (Or.inl (by rw [hEVe])) (by simp) (by simp [K4, K3, A2.setE, upd]) (by rw [hEDe]) (by rw [hEDe])
    (by decide) hmove (by rw [hEDe]; simp [roots]) hK53 (by rw [hEVe])
    (DtorSafe.of_none (fun v E h => (hK5 v E h).2.1) _ _ _) (by rw [hEVe]; simp)
  let E3 : Entry := { EV with held := EV.held ++ ownHeld true DT ED.held }
  have hE3e : E3 = ⟨.vec DT, .own, true, [], [], false, false, false⟩ := by
    simp [E3, hEVe, hEDe, ownHeld]
  let K6 : Ctx := A2.setE (kill .realloc DT.holdsView 3 K5) 3 E3
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by rw [hE3e]; simp)
  -- the outer `Vec`, bound by `letd` at `vec (vec DT)`
  let EN2 : Entry := ⟨.vec (.vec DT), .own, true, [], [], false, false, false⟩
  have hnew2 : RhsT K6 [] (.new (.vec DT)) EN2 K6 := RhsT.new (by decide)
  let EW : Entry := Entry.arm { EN2 with ty := .vec (.vec DT), held := [] }
  have hEWe : EW = ⟨.vec (.vec DT), .own, true, [], [], false, false, false⟩ := by
    simp [EW, EN2, Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  let K7 : Ctx := A2.setE K6 4 EW
  have hK7 : NoRootb K7 := hK6.setE (by rw [hEWe]; simp)
  -- the inner `Vec` moves into it
  let K8 : Ctx := A2.setE (kill .replace false 3 K7) 3 { E3 with live := false, dtor := false }
  have hK8 : NoRootb K8 := (hK7.kill _ _ _).setE (by rw [hE3e]; simp)
  have hmove2 : PushArg K7 [] 3 E3 (.vec DT) E3.held K8 :=
    PushArg.move (Γ := K7) (F := []) (y := 3) (E := E3) (t := .vec DT) rfl (by rw [hE3e]) (by simp)
      (hK7.noPin _) (DtorSafe.of_none (fun v E h => (hK7 v E h).2.1) _ _ _)
  have hK84 : K8 4 = some EW := by
    simp [K8, K7, A2.setE, upd, A2.kill, killE, hits, hEWe, Entry.vdeps, Mode.ownSlot]
  have hpush2 := StmtT.push (ξ := .none) (P := P) (Γ := K7) (Γ1 := K8) (F := []) (x := 4) (y := 3) (Ex := EW) (Ey := E3)
    (Ex1 := EW) (t := .vec DT) (D := E3.held) (by simp [K7, A2.setE, upd]) (by rw [hEWe]) (by rw [hEWe])
    (Or.inl (by rw [hEWe])) (by simp) (by simp [K7, K6, A2.setE, upd]) (by rw [hE3e]) (by rw [hE3e])
    (by decide) hmove2 (by rw [hE3e]; simp [roots]) hK84 (by rw [hEWe])
    (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _) (by rw [hEWe]; simp)
  let E4 : Entry := { EW with held := EW.held ++ ownHeld true (.vec DT) E3.held }
  have hE4e : E4 = ⟨.vec (.vec DT), .own, true, [], [], false, false, false⟩ := by
    simp [E4, hEWe, hE3e, ownHeld]
  let K9 : Ctx := A2.setE (kill .realloc (Ty.vec DT).holdsView 4 K8) 4 E4
  have hK9 : NoRootb K9 := (hK8.kill _ _ _).setE (by rw [hE4e]; simp)
  have hK94 : K9 4 = some E4 := by simp [K9, A2.setE]
  -- `: ( Vec DT ) b ( vec_at vv 0 )`
  let Eb : Entry := elemE 4 E4 (.vec DT)
  have hEbe : Eb = ⟨.vec DT, .bor, true, [⟨4, .inner⟩], [], false, false, false⟩ := by
    simp [Eb, hE4e, elemE, derive, Mode.isRoot, rootKind]
  have hat : RhsT K9 [] (.at 4 (.lit 0)) Eb K9 :=
    RhsT.at hK94 (by rw [hE4e]) (by rw [hE4e]) ExprT.lit
  let K10 : Ctx := A2.setE K9 5 Eb
  have hK10 : NoRootb K10 := hK9.setE (by rw [hEbe]; simp)
  have hK105 : K10 5 = some Eb := by simp [K10, A2.setE]
  have hK104 : K10 4 = some E4 := by simp [K10, A2.setE, upd, hK94]
  -- the move-out through `b`: a truncation's effect on `vv`
  have hthru : ThruOK K10 [] (.trunc (.dec (.len 5))) Eb.ty Eb.path := by
    rw [hEbe]
    intro d hd
    simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
      List.mem_singleton] at hd
    subst hd
    refine ⟨by simp, fun y hy => ?_, _, hK104, by rw [hE4e], Or.inl (by rw [hE4e]),
      DtorSafe.of_none (fun v E h => (hK10 v E h).2.1) _ _ _, by simp⟩
    simp [Edit.stored] at hy
  -- the body: `y` handed to its `letd` first thing
  let Kt : Ctx := A2.setE (A2.setE (A2.killThru (.trunc (.dec (.len 5))) Eb.ty Eb.path K10) 5 Eb) 6
    (compE Eb DT)
  have hKt : NoRootb Kt := ((A2.PopWitness.NoRootb.killThru hK10 _ _ _).setE (by rw [hEbe]; simp)).setE
    (by simp [compE, DT, ownHeld])
  have hcE : compE Eb DT = ⟨DT, .own, true, [], [], false, false, false⟩ := by
    simp [compE, DT, ownHeld, hEbe]
  let Ku : Ctx := A2.setE (kill .replace false 6 Kt) 6 { compE Eb DT with live := false, dtor := false }
  have hKu : NoRootb Ku := (hKt.kill _ _ _).setE (by rw [hcE]; simp)
  have hmv : RhsT Kt [] (.var 6) ⟨(compE Eb DT).ty, .own, true, [], (compE Eb DT).held, false, false, false⟩ Ku :=
    RhsT.moveOwn (by simp [Kt, A2.setE, upd]) (by rw [hcE]) (by rw [hcE]) (by simp) (hKt.noPin _)
      (DtorSafe.of_none (fun v E h => (hKt v E h).2.1) _ _ _)
  let EZ : Entry := Entry.arm { (⟨(compE Eb DT).ty, .own, true, [], (compE Eb DT).held, false, false, false⟩ : Entry)
    with ty := DT, held := (compE Eb DT).held }
  have hEZ : EZ = ⟨DT, .own, true, [], [], false, false, false⟩ := by
    simp only [EZ]; rw [hcE]; simp [Entry.arm, DT, T, Ty.dtorViews, Ty.holdsView]
  have hKv : NoRootb (A2.setE Ku 7 EZ) := hKu.setE (by rw [hEZ]; simp)
  have hlet := StmtT.letd (ξ := Exits.none.under 6) (P := P) (Γ := Kt) (Γ1 := Ku) (F := []) (x := 7) (f := 0)
    (r := .var 6) (s := .skip) (t := T) (H := (compE Eb DT).held) (τ := DT) rfl
    (by
      have h7 : K10 7 = none := by simp [K10, K9, K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]
      simp only [Kt, A2.setE, upd, show (7 : Var) ≠ 6 by decide, show (7 : Var) ≠ 5 by decide, ↓reduceIte,
        A2.killThru]
      exact killNames_none h7 _)
    (by simp) hmv rfl
    (Or.inl ⟨rfl, Or.inr ⟨0, by rw [hcE]; rfl⟩⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) StmtT.skip (hKv.endOK _)
    (by simp [Stmt.assigns])
  have htake := StmtT.takeB (ξ := .none) (P := P) (Γ := K10) (F := []) (x := 5) (y := 6) (i := .dec (.len 5))
    (s := .letd 7 0 (.var 6) .skip) (Ex := Eb) (t := DT) rfl
    (by simp [K10, K9, K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hK105 (by rw [hEbe])
    (by rw [hEbe]) (by rw [hEbe]) (by simp [DT, T, Ty.holdsView]) (by simp)
    (ExprT.dec (ExprT.len hK105 (by rw [hEbe]) (by rw [hEbe]))) (by rw [hEbe]; simp [memDeps, Kind.isName])
    hthru (fun _ => ⟨by simp [Stmt.movedFirst], by simp [Stmt.assigns]⟩) hlet
    (((hKv.exitScope 7)).endOK _)
  have hK11 : NoRootb (A2.exitScope 6 (A2.exitScope 7 (A2.setE Ku 7 EZ))) :=
    (hKv.exitScope 7).exitScope 6
  have hb := StmtT.letv (ξ := .none) (P := P) (x := 5) (r := .at 4 (.lit 0)) (E := Eb) (F := []) (Γ := K9)
    (Γ1 := K9) rfl (by simp [K9, K8, K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hat
    htake.ofNone (hK11.endOK _)
  have hbody := StmtT.seq (P := P) rfl hpush2 hb
  have hK12 := hK11.exitScope 5
  have hdw := StmtT.letd (ξ := .none) (P := P) (Γ := K6) (Γ1 := K6) (F := []) (x := 4) (f := 0) (r := .new (.vec DT))
    (s := .seq (.push 4 3) body12) (E := EN2) (t := T) (H := []) (τ := .vec (.vec DT)) rfl
    (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill])
    (by simp) hnew2 rfl (Or.inr ⟨1, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hbody.ofNone
    (hK12.endOK _) (by simp [Stmt.assigns, body12])
  have hseq := StmtT.seq (P := P) rfl hpush hdw
  have hdv := StmtT.letd (ξ := .none) (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (s := .seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.seq (.push 4 3) body12))) (E := EN) (t := T) (H := [])
    (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hseq.ofNone
    ((hK12.exitScope 4).endOK _) (by simp [Stmt.assigns, body12])
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (s := .letd 3 0 (.new DT) (.seq (.push 3 2) (.letd 4 0 (.new (.vec DT)) (.seq (.push 4 3) body12))))
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv.ofNone
    (((hK12.exitScope 4).exitScope 3).endOK _) (by simp [Stmt.assigns, body12])
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    ((((hK12.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1.ofNone
    (((((hK12.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- A run of the program never touches memory it may not: the destructor
    value moved out through `b` is its `letd`'s, whose frame runs `dfn`. -/
theorem main12_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 8) main12 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main12_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main12, body12, Stmt.codesOK, Rhs.codeOK])
    (by decide) hr

/-- ... and when it ends, everything it allocated is freed. -/
theorem main12_no_leak {m' : Mem} (hr : Steps P (emptyMem 8) main12 (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main12_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main12, body12, Stmt.codesOK, Rhs.codeOK])
    (by decide) hr

/-- The typing's guarantee, read off the program: `y` (6) is handed to its
    `letd` first thing. -/
theorem main12_hands_over : 6 ∈ (Stmt.letd 7 0 (.var 6) .skip).movedFirst ∧
    6 ∉ (Stmt.letd 7 0 (.var 6) .skip).assigns := by
  simp [Stmt.movedFirst, Stmt.assigns]

end A2.TakeBDWitness
