import A2.FreshNestWitness
import A2.UnheldFresh

/-! # AGORA-909: a push through an element read through a slice of an `inout` parameter

    @ g inout ( Vec ( Vec i ) ) vv ( Slice i ) s → i {
        : ( Slice ( Vec i ) ) sl ( slice_from_vec vv )
        ( vec_push ( slice_at sl 0 ) 7 )    -- a push THROUGH an element of a view
        ^ 0
    }
    : vv …  : src ( vec_new [i] )  : s ( slice_from_vec src )
    : r ( g vv s )                          -- the call passes an argument that holds views
    ( slice_at s 0 )                        -- and `s` is read after it

`sl` views `vv`, a binding of the frame's own: a fresh view (Agora #916).
An element read through it (`RhsT.sat`) is then fresh as one read through
the `Vec` itself is (`RhsT.at`): its path is `[⟨vv, .inner⟩]`. So the push is
an `edit false`, `g` is not through-changing, and the call is typed, safe and
leak-free.
-/

namespace A2.FreshSatWitness
open A2.ThruClosureWitness (vi vvi Calm killE_int)
open A2.TakeWitness (NoRootb noRootb_empty)
open A2.InoutViewArgWitness (sl killE_nodeps keep_kill keep_killNames keep_setE keep_exit)

/-- `g vv s`: `vv` is 0, `s` 1, the result slot 2, the view `sl` 3, the
    element borrow `e` 4, the number `7` 5. -/
def gBody : Stmt :=
  .seq (.letv 3 (.view 0) (.letv 4 (.sat 3 (.lit 0)) (.letv 5 (.expr (.lit 7)) (.edit false 4 (.push 5)))))
    (.assign 2 (.expr (.lit 0)))

def g : Fn where
  params   := [(.inout .replace, vvi), (.inp, sl)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := gBody
  nvars    := 6

def P : Prog := [g]

/-! ### The callee -/

def Ep : Entry := ⟨vvi, .inout .replace, true, [], [], false, false, false, false⟩
def Es : Entry := ⟨sl, .rootb, true, [], [], false, false, false, false⟩
def R0 : Entry := ⟨.int, .bor, false, [], [], false, false, false, false⟩
/-- The element borrow, fresh: its path is `vv`'s elements. -/
def Ee : Entry := ⟨vi, .bor, true, [⟨0, .inner⟩], [], false, false, true, false⟩

/-- The callee's context, with result slot `r2`. -/
def ctx (r2 : Entry) : Ctx := fun v =>
  if v = 0 then some Ep else if v = 1 then some Es else if v = 2 then some r2 else none

theorem sig_eq : sigCtx g = ctx R0 := by
  funext v
  simp only [sigCtx, ctx, g, paramE, resMode]
  rcases v with _ | _ | _ | v <;> simp [Ep, Es, R0, vvi, vi, sl, Ty.hasFn]

theorem calm_ctx {r : Entry} (hr : r.mode = .bor) (hd : r.dtor = false) (hb : r.dbind = false) :
    Calm (ctx r) := by
  intro v E h
  rcases v with _ | _ | _ | v <;> simp [ctx] at h <;> subst h <;>
    simp [Ep, Es, Entry.vdeps, Mode.ownSlot, hr, hd, hb]

/-- `sl ( slice_from_vec vv )`: a fresh view, `vv` is an `inout` parameter. -/
def Ev : Entry := ⟨.slice vi, .bor, true, [⟨0, .view⟩], [], false, false, true, false⟩

def G3 : Ctx := A2.setE (ctx R0) 3 Ev
def G4 : Ctx := A2.setE G3 4 Ee
def G5 : Ctx := A2.setE G4 5 intE

theorem view_typed : RhsT (ctx R0) [] (.view 0) Ev (ctx R0) := by
  have h0 : ctx R0 0 = some Ep := by simp [ctx]
  have := RhsT.view (Γ := ctx R0) (F := []) (y := 0) (E := Ep) (t := vi) (f := true) (h := false) h0 rfl rfl rfl
    (fun _ => ⟨Ep, h0, Or.inr ⟨.replace, rfl⟩⟩)
  simpa [derive, Mode.isRoot, rootKind, Ep, Ev, vi, vvi] using this

/-- `( slice_at sl 0 )`: fresh, `sl` is a fresh view (AGORA-909). -/
theorem sat_typed : RhsT G3 [] (.sat 3 (.lit 0)) Ee G3 := by
  have h3 : G3 3 = some Ev := by simp [G3, A2.setE, upd]
  have := RhsT.sat (Γ := G3) (F := []) (E := Ev) (t := vi) (i := .lit 0) (f := true) h3 rfl rfl ExprT.lit
    (fun _ => ⟨⟨Ev, h3, Or.inr ⟨rfl, rfl, rfl, by simp [Ev, vi]⟩⟩, fun s h => by cases h⟩)
  simpa [elemE, Ev, Ee, vi, derive, Mode.isRoot, comp] using this

theorem Ep_nodeps : Ep.vdeps = [] := by simp [Ep, Entry.vdeps, Mode.ownSlot]
theorem Es_nodeps : Es.vdeps = [] := by simp [Es, Entry.vdeps, Mode.ownSlot]
theorem R0_nodeps : R0.vdeps = [] := by simp [R0, Entry.vdeps, Mode.ownSlot]

/-! ### The push through `( vec_at vv 0 )`: an `edit false` -/

def Δe : Ctx := A2.setE (A2.killThru (.push 5) vi [⟨0, .inner⟩] G5) 4 Ee

theorem calm_G5 : Calm G5 :=
  (((calm_ctx rfl rfl rfl).setE (by simp [Ev])).setE (by simp [Ee])).setE (by simp [intE])
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
    (.letv 3 (.view 0) (.letv 4 (.sat 3 (.lit 0)) (.letv 5 (.expr (.lit 7)) (.edit false 4 (.push 5))))) Δ3 := by
  have hl5 := StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := G4) (Γ1 := G4) (F := []) (E := intE)
    (r := .expr (.lit 7)) (s := .edit false 4 (.push 5)) rfl (by simp [G4, G3, A2.setE, upd, ctx]) (by simp)
    (RhsT.expr ExprT.lit) edit_typed.ofNone (calm_Δe.endOK _) (fun h => by simp [intE] at h)
  have hl4 := StmtT.letv (P := P) (ξ := .none) (x := 4) (Γ := G3) (Γ1 := G3) (F := []) (E := Ee)
    rfl (by simp [G3, A2.setE, upd, ctx]) (by simp) sat_typed hl5.ofNone ((calm_Δe.exitScope 5).endOK _)
    (fun h => by simp [Ee] at h)
  exact StmtT.letv (P := P) (ξ := .none) (x := 3) (Γ := ctx R0) (Γ1 := ctx R0) (F := []) (E := Ev)
    rfl (by simp [ctx]) (by simp) view_typed hl4.ofNone (((calm_Δe.exitScope 5).exitScope 4).endOK _)
    (fun h => by simp [Ev] at h)

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
    keep_setE (by decide) (keep_kill (Δ3_keep (by simp [ctx]) Ep_nodeps (by decide) (by decide) (by decide)) Ep_nodeps _ _ _)
  refine ⟨rfl, by decide, by decide, rfl, by simp [g], ?_, by simp [g], by simp [g], by simp [g], by simp [g],
    by simp [g], dtorParamsOK_of (by simp [g] <;> decide) (by simp [g]), Δf, body_typed,
    fun v E hE => ⟨(calm_Δf v E hE).2.1, (calm_Δf v E hE).2.2⟩,
    ⟨{ intE with mode := R0.mode }, by simp [Δf, A2.setE, g], rfl, rfl, by simp [R0, resMode, g],
      by simp [intE], by simp [intE], by simp [g]⟩, ?_⟩
  · intro pt hpt
    simp only [g, List.mem_cons, List.mem_nil_iff, or_false] at hpt
    rcases hpt with rfl | rfl <;> simp [vvi, vi, sl, Ty.ok, Ty.owning, Ty.holdsView]
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

/-! ### The caller: `( g vv s )` with `s` a view of `src`, read after the call -/

/-- `: vv ( new ( Vec i ) )  : w ( new i )  ( vec_push vv w )  : src ( new i )  : k 5
    ( vec_push src k )  : s ( view src )  : r ( g vv s )  : x ( slice_at s 0 )`:
    `vv` 0, `src` 1, `s` 2, `r` 3, `x` 4, `w` 5, `k` 6. `vv` and `src` each hold an
    element before they are read, so every read is in bounds and a run can end
    normally. -/
def main : Stmt :=
  .letv 0 (.new vi) (.letv 5 (.new .int) (.seq (.push 0 5) (.letv 1 (.new .int)
    (.letv 6 (.expr (.lit 5)) (.seq (.push 1 6) (.letv 2 (.view 1)
      (.letcall 3 0 [0, 2] (.letv 4 (.sat 2 (.lit 0)) .skip))))))))

def Evv : Entry := ⟨vvi, .own, true, [], [], false, false, false, false⟩
def Esrc : Entry := ⟨vi, .own, true, [], [], false, false, false, false⟩
def Esv : Entry := ⟨sl, .bor, true, [⟨1, .view⟩], [], false, false, false, false⟩

def Ew0 : Entry := { Esrc with live := false, dtor := false }

def K1 : Ctx := A2.setE (fun _ => none) 0 Evv
def K1a : Ctx := A2.setE K1 5 Esrc
def K1b : Ctx := A2.setE (A2.kill .replace false 5 K1a) 5 Ew0
def K1c : Ctx := A2.setE K1 5 Ew0
def K2 : Ctx := A2.setE K1c 1 Esrc
def K2a : Ctx := A2.setE K2 6 intE
def K3 : Ctx := A2.setE K2a 2 Esv

theorem K1c_noRootb : NoRootb K1c := (noRootb_empty.setE (by simp [Evv])).setE (by simp [Ew0, Esrc])

theorem K3_noRootb : NoRootb K3 :=
  ((K1c_noRootb.setE (by simp [Esrc])).setE (by simp [intE])).setE (by simp [Esv])

theorem K3_0 : K3 0 = some Evv := by simp [K3, K2a, K2, K1c, K1, A2.setE, upd]
theorem K3_2 : K3 2 = some Esv := by simp [K3, A2.setE]

theorem callPost_eq : callPost K3 g [0, 2] = K3 := by
  funext v
  simp only [callPost, callPostAux, g, killNames, mutNames, argNames]
  rcases v with _ | _ | _ | _ | _ | _ | _ | v <;>
    simp [argE, K3, K2a, K2, K1c, K1, A2.setE, upd, A2.kill, killE, hits, Evv, Esrc, Ew0, Esv, intE, Entry.vdeps,
      Mode.ownSlot,
      vvi, vi, sl, Ty.holdsView, Ty.elem, nameDeps, Eff.kills, Kind.bound]

/-- **The call is typed**: `vv` is handed `inout`, and no other argument
    reaches it in memory (`s` reaches `src`); `g` is not through-changing,
    so passing the view `s` asks nothing (`callR` need not be empty). -/
theorem call_ok : CallT P K3 [] 0 [0, 2] (callRes K3 g [0, 2]) K3 := by
  refine ⟨g, rfl, rfl, ?_, ?_, CallDtorSafe.of_none (fun v E hE => ⟨(K3_noRootb v E hE).2.1,
      (K3_noRootb v E hE).2.2⟩) _ _, rfl, callPost_eq.symm, fun h => absurd h g_not_thru⟩
  · intro i hi
    rcases i with _ | _ | i
    · refine ⟨Evv, K3_0, rfl, ⟨rfl, Or.inl rfl, rfl⟩, fun _ => ?_,
        fun _ => fun p E hp hm => absurd hm (K3_noRootb p E hp).1⟩
      refine ⟨by simp, by simp [Evv, roots, memDeps, Entry.vdeps, Mode.ownSlot], (fun h => by cases h),
        (fun _ _ d hd => by simp [Evv, Entry.vdeps, Mode.ownSlot] at hd), fun j hj hji => ?_⟩
      rcases j with _ | _ | j
      · exact absurd rfl hji
      · refine ⟨by decide, ?_, ?_, ?_⟩
        · simp [argE, K3_2, Esv, roots, memDeps, Entry.vdeps, Mode.ownSlot, Kind.isName]
        · intro h; simp [g] at h
        · intro b _ d hd hr
          simp [argE, K3_2, Esv, Entry.vdeps, Mode.ownSlot] at hd; subst hd; simp at hr
      · simp [g] at hj; omega
    · exact ⟨Esv, K3_2, rfl, rfl, fun h => by simp [g, PMode.moves] at h,
        fun h => by simp [g] at h⟩
    · simp [g] at hi; omega
  · intro d hd
    simp [mutNames, argNames, argE, K3_0, K3_2, Evv, Esv, nameDeps, Entry.vdeps, Mode.ownSlot, vvi, vi,
      Kind.isName] at hd

theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let ER := callRes K3 g [0, 2]
  have hER : ER.mode ≠ .rootb ∧ ER.dtor = false ∧ ER.dbind = false := by
    simp [ER, callRes, resMode, g]
  have hL : NoRootb (A2.setE K3 3 ER) := K3_noRootb.setE hER
  have hL2 : A2.setE K3 3 ER 2 = some Esv := by simp [A2.setE, upd, K3_2]
  -- `( slice_at s 0 )` after the call: `s` is live
  have hsat : RhsT (A2.setE K3 3 ER) [] (.sat 2 (.lit 0)) intE (A2.setE K3 3 ER) := by
    have := RhsT.sat (Γ := A2.setE K3 3 ER) (F := []) (y := 2) (E := Esv) (t := .int) (i := .lit 0)
      hL2 rfl rfl ExprT.lit
    simpa [elemE, intE] using this
  have hL4 : NoRootb (A2.setE (A2.setE K3 3 ER) 4 intE) := hL.setE (by simp [intE])
  have h4 := StmtT.letv (ξ := .none) (P := P) (x := 4) (r := .sat 2 (.lit 0)) (s := .skip) (E := intE) (F := [])
    (Γ := A2.setE K3 3 ER) (Γ1 := A2.setE K3 3 ER) rfl (by simp [A2.setE, upd, K3, K2a, K2, K1c, K1]) (by simp)
    hsat StmtT.skip (hL4.endOK _)
  have hc := StmtT.letcall (ξ := .none) (P := P) (Γ := K3) (F := []) (x := 3) (f := 0) (args := [0, 2])
    (s := .letv 4 (.sat 2 (.lit 0)) .skip) (E := ER) (Γ1 := K3) rfl
    (by simp [K3, K2a, K2, K1c, K1, A2.setE, upd]) (by simp) call_ok h4.ofNone ((hL4.exitScope 4).endOK _)
    (fun fn hf ho _ => by simp [P] at hf; subst hf; simp [g] at ho)
  have hK2a : NoRootb K2a := (K1c_noRootb.setE (by simp [Esrc])).setE (by simp [intE])
  have hK2 : NoRootb K2 := K1c_noRootb.setE (by simp [Esrc])
  have hview : RhsT K2a [] (.view 1) Esv K2a := by
    have := RhsT.view (Γ := K2a) (F := []) (y := 1) (E := Esrc) (t := .int) (by simp [K2a, K2, A2.setE, upd])
      rfl rfl rfl
    simpa [derive, Mode.isRoot, rootKind, Esrc, Esv, vi, sl] using this
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .view 1) (E := Esv) (F := []) (Γ := K2a) (Γ1 := K2a)
    rfl (by simp [K2a, K2, K1c, K1, A2.setE, upd]) (by simp) hview hc.ofNone
    (((hL4.exitScope 4).exitScope 3).endOK _)
  -- `( vec_push src k )`: a number, so nothing moves and nothing ends
  have hpk : A2.setE (A2.kill .realloc Ty.int.holdsView 1 K2a) 1 { Esrc with held := Esrc.held ++ ownHeld true .int [] }
      = K2a := by
    funext v
    rcases v with _ | _ | _ | _ | _ | _ | _ | v <;>
      simp [K2a, K2, K1c, K1, A2.setE, upd, A2.kill, killE, hits, Evv, Esrc, Ew0, intE, Entry.vdeps,
        Mode.ownSlot, ownHeld, Ty.holdsView]
  have hpush1 : StmtT P .none K2a [] (.push 1 6) K2a := by
    have := StmtT.push (ξ := .none) (P := P) (Γ := K2a) (Γ1 := K2a) (F := []) (x := 1) (y := 6) (Ex := Esrc)
      (Ey := intE) (Ex1 := Esrc) (t := .int) (D := []) (by simp [K2a, K2, A2.setE, upd]) rfl rfl (Or.inl rfl)
      (by simp) (by simp [K2a, A2.setE]) rfl rfl (by decide) PushArg.int (by simp [roots])
      (by simp [K2a, K2, A2.setE, upd]) rfl (DtorSafe.of_none (fun v E h => (hK2a v E h).2.1) _ _ _)
      (fun h => by simp [Esrc] at h)
    rwa [hpk] at this
  have h6 := StmtT.letv (ξ := .none) (P := P) (x := 6) (r := .expr (.lit 5)) (E := intE) (F := []) (Γ := K2)
    (Γ1 := K2) rfl (by simp [K2, K1c, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit)
    (StmtT.seq (ξ := .none) rfl hpush1 h2.ofNone).ofNone ((((hL4.exitScope 4).exitScope 3).exitScope 2).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .new .int) (E := Esrc) (F := []) (Γ := K1c)
    (Γ1 := K1c) rfl (by simp [K1c, K1, A2.setE, upd]) (by simp) (RhsT.new rfl) h6.ofNone
    (((((hL4.exitScope 4).exitScope 3).exitScope 2).exitScope 6).endOK _)
  -- `( vec_push vv w )`: the inner `Vec` moves into `vv`
  have hK1a : NoRootb K1a := (noRootb_empty.setE (by simp [Evv])).setE (by simp [Esrc])
  have hK1b : NoRootb K1b := NoRootb.setE (fun v E h => A2.DynCell.NoRootb.kill (fun v E h => hK1a v E h)
    .replace false 5 v E h) (by simp [Ew0, Esrc])
  have hpv : A2.setE (A2.kill .realloc vi.holdsView 0 K1b) 0 { Evv with held := Evv.held ++ ownHeld true vi Esrc.held }
      = K1c := by
    funext v
    rcases v with _ | _ | _ | _ | _ | _ | v <;>
      simp [K1b, K1a, K1c, K1, A2.setE, upd, A2.kill, killE, hits, Evv, Esrc, Ew0, Entry.vdeps, Mode.ownSlot,
        ownHeld, Ty.holdsView, vi]
  have hpush0 : StmtT P .none K1a [] (.push 0 5) K1c := by
    have := StmtT.push (ξ := .none) (P := P) (Γ := K1a) (Γ1 := K1b) (F := []) (x := 0) (y := 5) (Ex := Evv)
      (Ey := Esrc) (Ex1 := Evv) (t := vi) (D := Esrc.held) (by simp [K1a, K1, A2.setE, upd]) rfl rfl (Or.inl rfl)
      (by simp) (by simp [K1a, A2.setE]) rfl rfl (by decide)
      (PushArg.move (by simp [vi, Ty.owning]) rfl (by simp) (A2.DynCell.NoRootb.noPin (fun v E h => hK1a v E h) _)
        (DtorSafe.of_none (fun v E h => (hK1a v E h).2.1) _ _ _))
      (by simp [Esrc, roots]) (by simp [K1b, K1a, K1, A2.setE, upd, A2.kill, killE, hits, Evv, Entry.vdeps,
        Mode.ownSlot]) rfl (DtorSafe.of_none (fun v E h => (hK1b v E h).2.1) _ _ _) (fun h => by simp [Evv] at h)
    rwa [hpv] at this
  have h5 := StmtT.letv (ξ := .none) (P := P) (x := 5) (r := .new .int) (E := Esrc) (F := []) (Γ := K1)
    (Γ1 := K1) rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.new rfl)
    (StmtT.seq (ξ := .none) rfl hpush0 h1.ofNone).ofNone
    ((((((hL4.exitScope 4).exitScope 3).exitScope 2).exitScope 6).exitScope 1).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new vi) (E := Evv) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new rfl) h5.ofNone
    (((((((hL4.exitScope 4).exitScope 3).exitScope 2).exitScope 6).exitScope 1).exitScope 5).endOK _)⟩

theorem main_codes : main.codesOK P := by simp [main, Stmt.codesOK, Rhs.codeOK]

/-- **The program is memory safe**: an `inout` callee that changes elements
    through a borrow of its parameter, called with an argument that holds a
    view, which is read after the call. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

/-! ### What stays refused -/

/-- **An element read through a slice that is not a `FreshSrc` is never
    fresh**: not through a borrowed slice parameter, not through a view that
    is not fresh. -/
theorem sat_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {i : Expr} {E : Entry}
    (ht : RhsT Γ F (.sat y i) E Γ1) (hs : ¬ FreshSrc Γ y) : E.fresh = false := by
  cases ht with
  | @sat _ _ _ _ f _ _ _ _ hf =>
    cases f
    · rfl
    · exact absurd (hf rfl).1 hs

/-- **Nor through a borrowed slice parameter** (`at_rootb_not_fresh`'s analogue). -/
theorem sat_rootb_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {i : Expr} {E Ey : Entry}
    (ht : RhsT Γ F (.sat y i) E Γ1) (hy : Γ y = some Ey) (hm : Ey.mode = .rootb) : E.fresh = false :=
  sat_not_fresh ht (A2.FreshWitness.rootb_not_freshSrc hy hm)

/-- **Nor through a view that is not fresh.** -/
theorem sat_stale_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {i : Expr} {E Ey : Entry}
    (ht : RhsT Γ F (.sat y i) E Γ1) (hy : Γ y = some Ey) (hm : Ey.mode = .bor) (hf : Ey.fresh = false) :
    E.fresh = false :=
  sat_not_fresh ht (A2.FreshWitness.stale_not_freshSrc hy hm hf)

/-- **An element that is itself a slice is never fresh**: its view reaches
    what the outer slice's element holds, not the frame. -/
theorem sat_slice_elem_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {i : Expr} {E Ey : Entry} {u : Ty}
    (ht : RhsT Γ F (.sat y i) E Γ1) (hy : Γ y = some Ey) (hty : Ey.ty = .slice (.slice u)) :
    E.fresh = false := by
  cases ht with
  | @sat _ _ _ t f hy' _ ht' _ hf =>
    cases f
    · rfl
    · rw [hy] at hy'; cases hy'
      rw [hty] at ht'; cases ht'
      exact absurd rfl ((hf rfl).2 u)

/-- **A slice of a borrowed parameter yields no fresh element**: A2 makes a
    slice only as a view of a `Vec` (`RhsT.view`), as an element read, or as
    a parameter. A view of a borrowed parameter is never fresh
    (`view_rootb_not_fresh`), so an element read through it is not either
    (`sat_stale_not_fresh`); through a borrowed slice parameter itself,
    `sat_rootb_not_fresh`; and an element that is a slice never is
    (`sat_slice_elem_not_fresh`). -/
theorem sat_of_view_of_rootb_not_fresh {Γ Γ1 Γ2 Γ3 : Ctx} {F F' : List Var} {p y : Var} {i : Expr}
    {Ep Ev E : Entry} (hp : Γ p = some Ep) (hm : Ep.mode = .rootb) (hv : RhsT Γ F (.view p) Ev Γ1)
    (hy : Γ2 y = some Ev) (ht : RhsT Γ2 F' (.sat y i) E Γ3) : E.fresh = false := by
  have hf : Ev.fresh = false := A2.view_rootb_not_fresh hp hm hv
  have hb : Ev.mode = .bor := by cases hv; rfl
  exact sat_stale_not_fresh ht hy hb hf

end A2.FreshSatWitness
