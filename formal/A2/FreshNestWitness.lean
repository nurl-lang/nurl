import A2.FreshProjWitness

/-! # AGORA-909: a nested projection, fresh at every step

    : Bag { ( Vec i ) items i n }
    : Box { Bag bag i tag }
    @ add inout Box o ( Slice i ) s → i {
        ( vec_push . . o bag items 7 )      -- a push THROUGH a field of a field
        ^ 0
    }
    : ~ Box o …  : src ( vec_new [i] )  : s ( slice_from_vec src )
    : r ( add o s )                         -- the call passes an argument that holds views
    ( slice_at s 0 )                        -- and `s` is read after it

`. o bag` is a field read of an `inout` parameter, of a type that holds no
views: fresh and held-fresh, holding nothing. `. t items`, read through that
borrow, is then fresh too (`RhsT.fst`'s source may be a fresh, held-fresh
borrow): its path is `t`'s, `[⟨o, .inner⟩]`. A call lifts `t` to a borrow that
holds nothing still (`RSetup.heldA`: a type that holds no views holds no
closure by name), so the renamed read is exact (`RSetup.projE_fresh_lift`).
The push is an `edit false`, `add` is not through-changing, and the call is
typed, safe and leak-free. `A2/FreshProjWitness.lean` has the negatives: a
read through a borrow that is not fresh, or of a type that holds views, is
never fresh (`proj_stale_not_fresh`, `nested_view_not_fresh`).
-/

namespace A2.FreshNestWitness
open A2.ThruClosureWitness (vi Calm killE_int)
open A2.TakeWitness (NoRootb noRootb_empty)
open A2.InoutViewArgWitness (sl killE_nodeps keep_kill keep_killNames keep_setE keep_exit)
open A2.FreshProjWitness (bag)

/-- `Box`: a `Bag` and a tag. -/
def box : Ty := .prod bag .int

/-- `add o s`: `o` is 0, `s` 1, the result slot 2, the borrow `. o bag` 3,
    the borrow `. . o bag items` 4, the number `7` 5. -/
def gBody : Stmt :=
  .seq (.letv 3 (.fst 0) (.letv 4 (.fst 3) (.letv 5 (.expr (.lit 7)) (.edit false 4 (.push 5)))))
    (.assign 2 (.expr (.lit 0)))

def g : Fn where
  params   := [(.inout .replace, box), (.inp, sl)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := gBody
  nvars    := 6

def P : Prog := [g]

/-! ### The callee -/

def Ep : Entry := ⟨box, .inout .replace, true, [], [], false, false, false, false⟩
def Es : Entry := ⟨sl, .rootb, true, [], [], false, false, false, false⟩
def R0 : Entry := ⟨.int, .bor, false, [], [], false, false, false, false⟩
/-- `. o bag`: fresh and held-fresh, its path `o`'s fields. -/
def Et : Entry := ⟨bag, .bor, true, [⟨0, .inner⟩], [], false, false, true, true⟩
/-- `. . o bag items`: the same path. -/
def Ee : Entry := ⟨vi, .bor, true, [⟨0, .inner⟩], [], false, false, true, true⟩

def ctx (r2 : Entry) : Ctx := fun v =>
  if v = 0 then some Ep else if v = 1 then some Es else if v = 2 then some r2 else none

theorem sig_eq : sigCtx g = ctx R0 := by
  funext v
  simp only [sigCtx, ctx, g, paramE, resMode]
  rcases v with _ | _ | _ | v <;> simp [Ep, Es, R0, box, bag, vi, sl, Ty.hasFn]

theorem calm_ctx {r : Entry} (hr : r.mode = .bor) (hd : r.dtor = false) (hb : r.dbind = false) :
    Calm (ctx r) := by
  intro v E h
  rcases v with _ | _ | _ | v <;> simp [ctx] at h <;> subst h <;>
    simp [Ep, Es, Entry.vdeps, Mode.ownSlot, hr, hd, hb]

def G3 : Ctx := A2.setE (ctx R0) 3 Et
def G4 : Ctx := A2.setE G3 4 Ee
def G5 : Ctx := A2.setE G4 5 intE

/-- `. o bag`: fresh, `o` is an `inout` parameter. -/
theorem fst0_typed : RhsT (ctx R0) [] (.fst 0) Et (ctx R0) := by
  have h0 : ctx R0 0 = some Ep := by simp [ctx]
  have := RhsT.fst (Γ := ctx R0) (F := []) (E := Ep) (a := bag) (b := .int) (f := true) h0 rfl rfl
    (fun _ => ⟨Or.inl (Or.inr ⟨.replace, rfl⟩), rfl, rfl, fun s h => by cases h⟩)
  simpa [projE, projDeps, Ep, Et, bag, Mode.ownSlot] using this

/-- `. t items`: fresh, `t` is a fresh, held-fresh borrow holding nothing. -/
theorem fst3_typed : RhsT G3 [] (.fst 3) Ee G3 := by
  have h3 : G3 3 = some Et := by simp [G3, A2.setE, upd]
  have := RhsT.fst (Γ := G3) (F := []) (E := Et) (a := vi) (b := .int) (f := true) h3 rfl rfl
    (fun _ => ⟨Or.inr ⟨rfl, rfl, rfl⟩, rfl, rfl, fun s h => by cases h⟩)
  simpa [projE, projDeps, Et, Ee, vi, Mode.ownSlot] using this

theorem Ep_nodeps : Ep.vdeps = [] := by simp [Ep, Entry.vdeps, Mode.ownSlot]
theorem Es_nodeps : Es.vdeps = [] := by simp [Es, Entry.vdeps, Mode.ownSlot]
theorem R0_nodeps : R0.vdeps = [] := by simp [R0, Entry.vdeps, Mode.ownSlot]

/-! ### The push through `. . o bag items`: an `edit false` -/

def Δe : Ctx := A2.setE (A2.killThru (.push 5) vi [⟨0, .inner⟩] G5) 4 Ee

theorem calm_G5 : Calm G5 :=
  (((calm_ctx rfl rfl rfl).setE (by simp [Et])).setE (by simp [Ee])).setE (by simp [intE])
theorem G5_0 : G5 0 = some Ep := by simp [G5, G4, G3, A2.setE, upd, ctx]

theorem thru_ok : ThruOK G5 [] (.push 5) vi [⟨0, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, G5_0, rfl, Or.inr ⟨.replace, rfl, by decide⟩, calm_G5.dtor _ _ _, by simp⟩
  simp [Edit.stored] at hy; subst hy; decide

theorem edit_typed : StmtT P .none G5 [] (.edit false 4 (.push 5)) Δe := by
  have h4 : G5 4 = some Ee := by simp [G5, G4, A2.setE, upd]
  have h5 : G5 5 = some intE := by simp [G5, A2.setE]
  have := StmtT.editB (b := false) (P := P) (ξ := .none) (Γ := G5) (Γ1 := G5) (F := []) (x := 4)
    (op := .push 5) (Ex := Ee) (Ex1 := Ee) (t := .int) (D := []) h4 rfl rfl rfl rfl
    (by simp) (EditArg.push (Ey := intE) h5 rfl rfl PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide)
    h4 rfl (by simp [Ee, memDeps, Kind.isName]) thru_ok
    (fun h => by simp [Edit.drops] at h) (fun _ => rfl)
  simpa [Δe, Ee] using this

theorem calm_Δe : Calm Δe := (calm_G5.killThru _ _ _).setE (by simp [Ee])

/-! ### The body -/

def Δ3 : Ctx := A2.exitScope 3 (A2.exitScope 4 (A2.exitScope 5 Δe))

theorem calm_Δ3 : Calm Δ3 := ((calm_Δe.exitScope 5).exitScope 4).exitScope 3

theorem Δ3_keep {v : Var} {E : Entry} (hv : ctx R0 v = some E) (h : E.vdeps = []) (h3 : v ≠ 3) (h4 : v ≠ 4)
    (h5 : v ≠ 5) : Δ3 v = some E := by
  have : G5 v = some E := keep_setE (Ne.symm h5) (keep_setE (Ne.symm h4) (keep_setE (Ne.symm h3) hv))
  have he : Δe v = some E := keep_setE (Ne.symm h4) (keep_killNames this h _)
  exact keep_exit (Ne.symm h3) (keep_exit (Ne.symm h4) (keep_exit (Ne.symm h5) he h) h) h

theorem inner_typed : StmtT P .none (ctx R0) []
    (.letv 3 (.fst 0) (.letv 4 (.fst 3) (.letv 5 (.expr (.lit 7)) (.edit false 4 (.push 5))))) Δ3 := by
  have hl5 := StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := G4) (Γ1 := G4) (F := []) (E := intE)
    (r := .expr (.lit 7)) (s := .edit false 4 (.push 5)) rfl (by simp [G4, G3, A2.setE, upd, ctx]) (by simp)
    (RhsT.expr ExprT.lit) edit_typed.ofNone (calm_Δe.endOK _) (fun h => by simp [intE] at h)
  have hl4 := StmtT.letv (P := P) (ξ := .none) (x := 4) (Γ := G3) (Γ1 := G3) (F := []) (E := Ee)
    rfl (by simp [G3, A2.setE, upd, ctx]) (by simp) fst3_typed hl5.ofNone ((calm_Δe.exitScope 5).endOK _)
    (fun h => by simp [Ee] at h)
  exact StmtT.letv (P := P) (ξ := .none) (x := 3) (Γ := ctx R0) (Γ1 := ctx R0) (F := []) (E := Et)
    rfl (by simp [ctx]) (by simp) fst0_typed hl4.ofNone (((calm_Δe.exitScope 5).exitScope 4).endOK _)
    (fun h => by simp [Et] at h)

def Δf : Ctx := A2.setE (A2.kill .replace false 2 Δ3) 2 { intE with mode := R0.mode }

theorem body_typed : StmtT P .none (sigCtx g) [] g.body Δf := by
  rw [sig_eq]
  have h2 : Δ3 2 = some R0 := Δ3_keep (by simp [ctx]) R0_nodeps (by decide) (by decide) (by decide)
  have ha := StmtT.assign (ξ := .none) (P := P) (Γ := Δ3) (F := []) (x := 2) (r := .expr (.lit 0)) (Ex := R0)
    (E := intE) (Γ1 := Δ3) h2 (by simp) (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.expr ExprT.lit) rfl (by simp [intE, roots, Entry.vdeps, Mode.ownSlot]) (by simp [h2])
    (calm_Δ3.noPin _) (calm_Δ3.dtor _ _ _) rfl
  exact StmtT.seq rfl inner_typed ha

theorem calm_Δf : Calm Δf := (calm_Δ3.kill _ _ _).setE (by simp [intE, R0])

theorem g_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [g, gBody, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [g, gBody, Stmt.calls] at hg

theorem g_ok : FnOK P g := by
  have hΔ0 : Δf 0 = some Ep :=
    keep_setE (by decide)
      (keep_kill (Δ3_keep (by simp [ctx]) Ep_nodeps (by decide) (by decide) (by decide)) Ep_nodeps _ _ _)
  refine ⟨rfl, by decide, by decide, rfl, by simp [g], ?_, by simp [g], by simp [g], by simp [g], by simp [g],
    by simp [g], dtorParamsOK_of (by simp [g] <;> decide) (by simp [g]), Δf, body_typed,
    fun v E hE => ⟨(calm_Δf v E hE).2.1, (calm_Δf v E hE).2.2⟩,
    ⟨{ intE with mode := R0.mode }, by simp [Δf, A2.setE, g], rfl, rfl, by simp [R0, resMode, g],
      by simp [intE], by simp [intE], by simp [g]⟩, ?_⟩
  · intro pt hpt
    simp only [g, List.mem_cons, List.mem_nil_iff, or_false] at hpt
    rcases hpt with rfl | rfl <;> simp [box, bag, vi, sl, Ty.ok, Ty.owning, Ty.holdsView]
  · intro i hi b hb
    rcases i with _ | i
    · exact ⟨Ep, hΔ0, rfl, by simp [Ep], by simp [Ep]⟩
    · rcases i with _ | i
      · simp [g] at hb
      · simp [g] at hi; omega

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; exact g_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; simp [g, gBody, Stmt.codesOK, Rhs.codeOK]

/-! ### The caller: `( add o s )` with `s` a view of `src`, read after the call -/

/-- `: items ( new i )  : n 5  : bg { items n }  : tag 9  : o { bg tag }
    : src ( new i )  : s ( view src )  : r ( add o s )  : x ( slice_at s 0 )`:
    `items` 0, `n` 1, `bg` 2, `tag` 3, `o` 4, `src` 5, `s` 6, `r` 7, `x` 8. -/
def main : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.expr (.lit 5)) (.letv 2 (.pair 0 1) (.letv 3 (.expr (.lit 9))
    (.letv 4 (.pair 2 3) (.letv 5 (.new .int) (.letv 6 (.view 5)
      (.letcall 7 0 [4, 6] (.letv 8 (.sat 6 (.lit 0)) .skip))))))))

def Ev : Entry := ⟨vi, .own, true, [], [], false, false, false, false⟩
def Ev0 : Entry := { Ev with live := false, dtor := false }
def Eb : Entry := ⟨bag, .own, true, [], [], false, false, false, false⟩
def Eb0 : Entry := { Eb with live := false, dtor := false }
def Eo : Entry := ⟨box, .own, true, [], [], false, false, false, false⟩
def Esv : Entry := ⟨sl, .bor, true, [⟨5, .view⟩], [], false, false, false, false⟩

def K1 : Ctx := A2.setE (fun _ => none) 0 Ev
def K2 : Ctx := A2.setE K1 1 intE
def K2' : Ctx := A2.setE (A2.kill .replace false 0 K2) 0 Ev0
def K3 : Ctx := A2.setE K2' 2 Eb
def K4 : Ctx := A2.setE K3 3 intE
def K4' : Ctx := A2.setE (A2.kill .replace false 2 K4) 2 Eb0
def K5 : Ctx := A2.setE K4' 4 Eo
def K6 : Ctx := A2.setE K5 5 Ev
def K7 : Ctx := A2.setE K6 6 Esv

theorem K2_noRootb : NoRootb K2 := (noRootb_empty.setE (by simp [Ev])).setE (by simp [intE])

theorem K2'_noRootb : NoRootb K2' := by
  intro v E h
  simp only [K2', K2, K1, A2.setE, upd, A2.kill] at h
  rcases v with _ | _ | v <;> simp [killE, hits, Entry.vdeps, Ev, Ev0, intE] at h <;> subst h <;>
    simp [Ev, intE]

theorem K4_noRootb : NoRootb K4 := (K2'_noRootb.setE (by simp [Eb])).setE (by simp [intE])

theorem K4'_noRootb : NoRootb K4' := by
  intro v E h
  simp only [K4', K4, K3, K2', K2, K1, A2.setE, upd, A2.kill] at h
  rcases v with _ | _ | _ | _ | v <;>
    simp [killE, hits, Entry.vdeps, Ev, Ev0, Eb, Eb0, intE, Mode.ownSlot] at h <;> subst h <;>
    simp [Ev, Eb, intE]

theorem K7_noRootb : NoRootb K7 :=
  ((K4'_noRootb.setE (by simp [Eo])).setE (by simp [Ev])).setE (by simp [Esv])

theorem K7_4 : K7 4 = some Eo := by simp [K7, K6, K5, A2.setE, upd]
theorem K7_6 : K7 6 = some Esv := by simp [K7, A2.setE]

theorem callPost_eq : callPost K7 g [4, 6] = K7 := by
  funext v
  simp only [callPost, callPostAux, g, killNames, mutNames, argNames]
  rcases v with _ | _ | _ | _ | _ | _ | _ | v <;>
    simp [argE, K7, K6, K5, K4', K4, K3, K2', K2, K1, A2.setE, upd, A2.kill, killE, hits, Ev, Ev0, Eb, Eb0,
      Eo, Esv, intE, Entry.vdeps, Mode.ownSlot, box, bag, vi, sl, Ty.holdsView, Ty.elem, nameDeps, Eff.kills,
      Kind.bound]

theorem call_ok : CallT P K7 [] 0 [4, 6] (callRes K7 g [4, 6]) K7 := by
  refine ⟨g, rfl, rfl, ?_, ?_, CallDtorSafe.of_none (fun v E hE => ⟨(K7_noRootb v E hE).2.1,
      (K7_noRootb v E hE).2.2⟩) _ _, rfl, callPost_eq.symm, fun h => absurd h g_not_thru⟩
  · intro i hi
    rcases i with _ | _ | i
    · refine ⟨Eo, K7_4, rfl, ⟨rfl, Or.inl rfl, rfl⟩, fun _ => ?_,
        fun _ => fun p E hp hm => absurd hm (K7_noRootb p E hp).1⟩
      refine ⟨by simp, by simp [Eo, roots, memDeps, Entry.vdeps, Mode.ownSlot], (fun h => by cases h),
        (fun _ _ d hd => by simp [Eo, Entry.vdeps, Mode.ownSlot] at hd), fun j hj hji => ?_⟩
      rcases j with _ | _ | j
      · exact absurd rfl hji
      · refine ⟨by decide, ?_, ?_, ?_⟩
        · simp [argE, K7_6, Esv, roots, memDeps, Entry.vdeps, Mode.ownSlot, Kind.isName]
        · intro h; simp [g] at h
        · intro b _ d hd hr
          simp [argE, K7_6, Esv, Entry.vdeps, Mode.ownSlot] at hd; subst hd; simp at hr
      · simp [g] at hj; omega
    · exact ⟨Esv, K7_6, rfl, rfl, fun h => by simp [g, PMode.moves] at h,
        fun h => by simp [g] at h⟩
    · simp [g] at hi; omega
  · intro d hd
    simp [mutNames, argNames, argE, K7_4, K7_6, Eo, Esv, nameDeps, Entry.vdeps, Mode.ownSlot, box, bag, vi,
      Kind.isName] at hd

theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let ER := callRes K7 g [4, 6]
  have hER : ER.mode ≠ .rootb ∧ ER.dtor = false ∧ ER.dbind = false := by
    simp [ER, callRes, resMode, g]
  have hL : NoRootb (A2.setE K7 7 ER) := K7_noRootb.setE hER
  have hL6 : A2.setE K7 7 ER 6 = some Esv := by simp [A2.setE, upd, K7_6]
  have hsat : RhsT (A2.setE K7 7 ER) [] (.sat 6 (.lit 0)) intE (A2.setE K7 7 ER) := by
    have := RhsT.sat (Γ := A2.setE K7 7 ER) (F := []) (y := 6) (E := Esv) (t := .int) (i := .lit 0)
      hL6 rfl rfl ExprT.lit
    simpa [elemE, intE] using this
  have hL8 : NoRootb (A2.setE (A2.setE K7 7 ER) 8 intE) := hL.setE (by simp [intE])
  have h8 := StmtT.letv (ξ := .none) (P := P) (x := 8) (r := .sat 6 (.lit 0)) (s := .skip) (E := intE) (F := [])
    (Γ := A2.setE K7 7 ER) (Γ1 := A2.setE K7 7 ER) rfl
    (by simp [A2.setE, upd, K7, K6, K5, K4', K4, K3, K2', K2, K1, A2.kill]) (by simp) hsat StmtT.skip (hL8.endOK _)
  have hc := StmtT.letcall (ξ := .none) (P := P) (Γ := K7) (F := []) (x := 7) (f := 0) (args := [4, 6])
    (s := .letv 8 (.sat 6 (.lit 0)) .skip) (E := ER) (Γ1 := K7) rfl
    (by simp [K7, K6, K5, K4', K4, K3, K2', K2, K1, A2.setE, upd, A2.kill])
    (by simp) call_ok h8.ofNone ((hL8.exitScope 8).endOK _)
    (fun fn hf ho _ => by simp [P] at hf; subst hf; simp [g] at ho)
  have hK6 : NoRootb K6 := (K4'_noRootb.setE (by simp [Eo])).setE (by simp [Ev])
  have hview : RhsT K6 [] (.view 5) Esv K6 := by
    have := RhsT.view (Γ := K6) (F := []) (y := 5) (E := Ev) (t := .int) (by simp [K6, A2.setE]) rfl rfl rfl
    simpa [derive, Mode.isRoot, rootKind, Ev, Esv, vi, sl] using this
  have h6 := StmtT.letv (ξ := .none) (P := P) (x := 6) (r := .view 5) (E := Esv) (F := []) (Γ := K6) (Γ1 := K6)
    rfl (by simp [K6, K5, K4', K4, K3, K2', K2, K1, A2.setE, upd, A2.kill]) (by simp) hview hc.ofNone
    (((hL8.exitScope 8).exitScope 7).endOK _)
  have h5 := StmtT.letv (ξ := .none) (P := P) (x := 5) (r := .new .int) (E := Ev) (F := []) (Γ := K5) (Γ1 := K5)
    rfl (by simp [K5, K4', K4, K3, K2', K2, K1, A2.setE, upd, A2.kill]) (by simp) (RhsT.new rfl) h6.ofNone
    ((((hL8.exitScope 8).exitScope 7).exitScope 6).endOK _)
  have hpair4 : RhsT K4 [] (.pair 2 3) Eo K4' := by
    have := RhsT.pair (Γ := K4) (F := []) (y := 2) (z := 3) (Ey := Eb) (Ez := intE)
      (by simp [K4, K3, A2.setE, upd]) rfl
      (PushArg.move (by simp [Eb, bag, vi, Ty.owning]) rfl (by simp) (A2.DynCell.NoRootb.noPin
        (fun v E h => K4_noRootb v E h) _) (DtorSafe.of_none (fun v E h => (K4_noRootb v E h).2.1) _ _ _))
      (by simp [A2.setE, upd, A2.kill, killE, hits, K4, intE, Entry.vdeps, Mode.ownSlot]) rfl PushArg.int
      (fun h => by simp [intE, Mode.ownSlot] at h)
    simpa [Eo, Eb, Eb0, K4', intE, box] using this
  have h4 := StmtT.letv (ξ := .none) (P := P) (x := 4) (r := .pair 2 3) (E := Eo) (F := []) (Γ := K4) (Γ1 := K4')
    rfl (by simp [K4, K3, K2', K2, K1, A2.setE, upd, A2.kill]) (by simp) hpair4 h5.ofNone
    (((((hL8.exitScope 8).exitScope 7).exitScope 6).exitScope 5).endOK _)
  have h3 := StmtT.letv (ξ := .none) (P := P) (x := 3) (r := .expr (.lit 9)) (E := intE) (F := []) (Γ := K3)
    (Γ1 := K3) rfl (by simp [K3, K2', K2, K1, A2.setE, upd, A2.kill]) (by simp) (RhsT.expr ExprT.lit) h4.ofNone
    ((((((hL8.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).endOK _)
  have hpair2 : RhsT K2 [] (.pair 0 1) Eb K2' := by
    have := RhsT.pair (Γ := K2) (F := []) (y := 0) (z := 1) (Ey := Ev) (Ez := intE)
      (by simp [K2, K1, A2.setE, upd]) rfl
      (PushArg.move (by simp [Ev, vi, Ty.owning]) rfl (by simp) (A2.DynCell.NoRootb.noPin
        (fun v E h => K2_noRootb v E h) _) (DtorSafe.of_none (fun v E h => (K2_noRootb v E h).2.1) _ _ _))
      (by simp [A2.setE, upd, A2.kill, killE, hits, K2, K1, intE, Entry.vdeps, Mode.ownSlot]) rfl PushArg.int
      (fun h => by simp [intE, Mode.ownSlot] at h)
    simpa [Eb, Ev, Ev0, K2', intE, bag] using this
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .pair 0 1) (E := Eb) (F := []) (Γ := K2) (Γ1 := K2')
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hpair2 h3.ofNone
    (((((((hL8.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .expr (.lit 5)) (E := intE) (F := []) (Γ := K1)
    (Γ1 := K1) rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) h2.ofNone
    ((((((((hL8.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := Ev) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new rfl) h1.ofNone
    (((((((((hL8.exitScope 8).exitScope 7).exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2).exitScope
      1).endOK _)⟩

theorem main_codes : main.codesOK P := by simp [main, Stmt.codesOK, Rhs.codeOK]

/-- **The program is memory safe**: a callee that pushes through a field of
    a field of its `inout` parameter, called with an argument that holds a
    view, which is read after the call. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 9) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 9) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

end A2.FreshNestWitness
