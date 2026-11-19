import A2.FreshWitness
import A2.TakeWitness

/-! # AGORA-909 (github#2041), direct call: an `inout` callee changing elements, called with a view

    @ g inout ( Vec ( Vec i ) ) vv ( Slice i ) s → i {
        ( vec_push ( vec_at vv 0 ) 7 )      -- a push THROUGH a borrow of a parameter's element
        ^ 0
    }
    : vv ( vec_new … )  : src ( vec_new [i] )  : s ( slice_from_vec src )
    : r ( g vv s )                          -- the call passes an argument that holds views
    ( slice_at s 0 )                        -- and `s` is read after it

github#2041 asked whether `CallT`'s `ThruFn P f → callR Γ args = []` must keep
refusing such a call. It need not, and no rule changes. The borrow
`( vec_at vv 0 )` is rooted at an `inout` parameter, a binding of the frame's
own (`Mode.frame`), so it is fresh (Agora #909, design e) and the push is an
`edit false`. `g` is not through-changing (`g_not_thru`), so the premise asks
nothing. What keeps `s` from viewing `vv` is `CallT`'s existing exclusivity
of a changed argument: no other argument reaches it in memory. Here `s`
views the unrelated `src`, so the call is typed, `s` survives it, and the
read after it is typed too.

`prog_ok`, `main_typed`, and `memory_safe` / `no_leak_end` applied
(`main_safe`, `main_no_leak`).
-/

namespace A2.InoutViewArgWitness
open A2.ThruClosureWitness (vi vvi Calm killE_int)
open A2.TakeWitness (NoRootb noRootb_empty)

def sl : Ty := .slice .int

/-- `g vv s`: `vv` is 0, `s` 1, the result slot 2, the element borrow `e` 3,
    the number `7` 4. -/
def gBody : Stmt :=
  .seq (.letv 3 (.at 0 (.lit 0)) (.letv 4 (.expr (.lit 7)) (.edit false 3 (.push 4))))
    (.assign 2 (.expr (.lit 0)))

def g : Fn where
  params   := [(.inout .replace, vvi), (.inp, sl)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := gBody
  nvars    := 5

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

/-- `( vec_at vv 0 )`: fresh, `vv` is an `inout` parameter (`Mode.frame`). -/
theorem at_typed : RhsT (ctx R0) [] (.at 0 (.lit 0)) Ee (ctx R0) := by
  have h0 : ctx R0 0 = some Ep := by simp [ctx]
  have := RhsT.at (Γ := ctx R0) (F := []) (E := Ep) (t := vi) (i := .lit 0) (f := true) h0 rfl rfl ExprT.lit
    (fun _ => ⟨⟨Ep, h0, Or.inl (Or.inr ⟨.replace, rfl⟩)⟩, fun s h => by cases h⟩)
  simpa [elemE, Ep, Ee, vi, vvi, derive, Mode.isRoot, rootKind] using this

/-! ### What depends on nothing is ended by nothing -/

theorem killE_nodeps {E : Entry} (h : E.vdeps = []) (e : Eff) (hv : Bool) (x : Var) : killE e hv x E = E := by
  unfold killE hits; simp [h]

theorem keep_kill {Γ : Ctx} {v : Var} {E : Entry} (hv : Γ v = some E) (h : E.vdeps = []) (e : Eff) (b : Bool)
    (x : Var) : A2.kill e b x Γ v = some E := by
  simp [A2.kill, hv, killE_nodeps h]

theorem keep_killNames {Γ : Ctx} {v : Var} {E : Entry} (hv : Γ v = some E) (h : E.vdeps = []) :
    ∀ ds : List Dep, A2.killNames ds Γ v = some E
  | [] => hv
  | d :: ds => by
    simp only [A2.killNames, List.foldr_cons]
    exact keep_kill (keep_killNames hv h ds) h _ _ _

theorem keep_setE {Γ : Ctx} {v x : Var} {E E' : Entry} (hx : x ≠ v) (hv : Γ v = some E) :
    A2.setE Γ x E' v = some E := by
  simp [A2.setE, upd, hv, Ne.symm hx]

theorem keep_exit {Γ : Ctx} {v x : Var} {E : Entry} (hx : x ≠ v) (hv : Γ v = some E) (h : E.vdeps = []) :
    A2.exitScope x Γ v = some E := by
  simp only [A2.exitScope, upd, Ne.symm hx, ite_false]
  exact keep_kill hv h _ _ _

theorem Ep_nodeps : Ep.vdeps = [] := by simp [Ep, Entry.vdeps, Mode.ownSlot]
theorem Es_nodeps : Es.vdeps = [] := by simp [Es, Entry.vdeps, Mode.ownSlot]
theorem R0_nodeps : R0.vdeps = [] := by simp [R0, Entry.vdeps, Mode.ownSlot]

/-! ### The push through `( vec_at vv 0 )`: an `edit false` -/

def G3 : Ctx := A2.setE (ctx R0) 3 Ee
def G4 : Ctx := A2.setE G3 4 intE
def Δe : Ctx := A2.setE (A2.killThru (.push 4) vi [⟨0, .inner⟩] G4) 3 Ee

theorem calm_G4 : Calm G4 := ((calm_ctx rfl rfl rfl).setE (by simp [Ee])).setE (by simp [intE])
theorem G4_0 : G4 0 = some Ep := by simp [G4, G3, A2.setE, upd, ctx]

theorem thru_ok : ThruOK G4 [] (.push 4) vi [⟨0, .inner⟩] := by
  intro d hd
  simp only [memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨by simp, fun y hy => ?_, _, G4_0, rfl, Or.inr ⟨.replace, rfl, by decide⟩, calm_G4.dtor _ _ _, by simp⟩
  simp [Edit.stored] at hy; subst hy; decide

theorem edit_typed : StmtT P .none G4 [] (.edit false 3 (.push 4)) Δe := by
  have h3 : G4 3 = some Ee := by simp [G4, G3, A2.setE, upd]
  have h4 : G4 4 = some intE := by simp [G4, A2.setE]
  have := StmtT.editB (b := false) (P := P) (ξ := .none) (Γ := G4) (Γ1 := G4) (F := []) (x := 3)
    (op := .push 4) (Ex := Ee) (Ex1 := Ee) (t := .int) (D := []) h3 rfl rfl rfl rfl
    (by simp) (EditArg.push (Ey := intE) h4 rfl rfl PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide)
    h3 rfl (by simp [Ee, memDeps, Kind.isName]) thru_ok
    (fun h => by simp [Edit.drops] at h) (fun _ => rfl)
  simpa [Δe, Ee] using this

theorem calm_Δe : Calm Δe := (calm_G4.killThru _ _ _).setE (by simp [Ee])

/-! ### The body -/

def Δ3 : Ctx := A2.exitScope 3 (A2.exitScope 4 Δe)

theorem calm_Δ3 : Calm Δ3 := (calm_Δe.exitScope 4).exitScope 3

theorem Δe_keep {v : Var} {E : Entry} (hv : ctx R0 v = some E) (h : E.vdeps = []) (h3 : v ≠ 3) (h4 : v ≠ 4) :
    Δe v = some E := by
  have : G4 v = some E := keep_setE (Ne.symm h4) (keep_setE (Ne.symm h3) hv)
  exact keep_setE (Ne.symm h3) (keep_killNames this h _)

theorem Δ3_keep {v : Var} {E : Entry} (hv : ctx R0 v = some E) (h : E.vdeps = []) (h3 : v ≠ 3) (h4 : v ≠ 4) :
    Δ3 v = some E :=
  keep_exit (Ne.symm h3) (keep_exit (Ne.symm h4) (Δe_keep hv h h3 h4) h) h

theorem inner_typed : StmtT P .none (ctx R0) []
    (.letv 3 (.at 0 (.lit 0)) (.letv 4 (.expr (.lit 7)) (.edit false 3 (.push 4)))) Δ3 := by
  have hl4 := StmtT.letv (P := P) (ξ := .none) (x := 4) (Γ := G3) (Γ1 := G3) (F := []) (E := intE)
    (r := .expr (.lit 7)) (s := .edit false 3 (.push 4)) rfl (by simp [G3, A2.setE, upd, ctx]) (by simp) (RhsT.expr ExprT.lit)
    edit_typed.ofNone (calm_Δe.endOK _) (fun h => by simp [intE] at h)
  exact StmtT.letv (P := P) (ξ := .none) (x := 3) (Γ := ctx R0) (Γ1 := ctx R0) (F := []) (E := Ee)
    rfl (by simp [ctx]) (by simp) at_typed hl4.ofNone ((calm_Δe.exitScope 4).endOK _) (fun h => by simp [Ee] at h)

def Δf : Ctx := A2.setE (A2.kill .replace false 2 Δ3) 2 { intE with mode := R0.mode }

theorem body_typed : StmtT P .none (sigCtx g) [] g.body Δf := by
  rw [sig_eq]
  have h2 : Δ3 2 = some R0 := Δ3_keep (by simp [ctx]) R0_nodeps (by decide) (by decide)
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
    keep_setE (by decide) (keep_kill (Δ3_keep (by simp [ctx]) Ep_nodeps (by decide) (by decide)) Ep_nodeps _ _ _)
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

/-- `: vv ( new ( Vec i ) )  : src ( new i )  : s ( view src )  : r ( g vv s )
    : x ( slice_at s 0 )`: `vv` 0, `src` 1, `s` 2, `r` 3, `x` 4. -/
def main : Stmt :=
  .letv 0 (.new vi) (.letv 1 (.new .int) (.letv 2 (.view 1)
    (.letcall 3 0 [0, 2] (.letv 4 (.sat 2 (.lit 0)) .skip))))

def Evv : Entry := ⟨vvi, .own, true, [], [], false, false, false, false⟩
def Esrc : Entry := ⟨vi, .own, true, [], [], false, false, false, false⟩
def Esv : Entry := ⟨sl, .bor, true, [⟨1, .view⟩], [], false, false, false, false⟩

def K1 : Ctx := A2.setE (fun _ => none) 0 Evv
def K2 : Ctx := A2.setE K1 1 Esrc
def K3 : Ctx := A2.setE K2 2 Esv

theorem K3_noRootb : NoRootb K3 :=
  ((noRootb_empty.setE (by simp [Evv])).setE (by simp [Esrc])).setE (by simp [Esv])

theorem K3_0 : K3 0 = some Evv := by simp [K3, K2, K1, A2.setE, upd]
theorem K3_2 : K3 2 = some Esv := by simp [K3, A2.setE]

theorem callPost_eq : callPost K3 g [0, 2] = K3 := by
  funext v
  simp only [callPost, callPostAux, g, killNames, mutNames, argNames]
  rcases v with _ | _ | _ | v <;>
    simp [argE, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, Evv, Esrc, Esv, Entry.vdeps, Mode.ownSlot,
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
    simpa [elemE] using this
  have hL4 : NoRootb (A2.setE (A2.setE K3 3 ER) 4 intE) := hL.setE (by simp [intE])
  have h4 := StmtT.letv (ξ := .none) (P := P) (x := 4) (r := .sat 2 (.lit 0)) (s := .skip) (E := intE) (F := [])
    (Γ := A2.setE K3 3 ER) (Γ1 := A2.setE K3 3 ER) rfl (by simp [A2.setE, upd, K3, K2, K1]) (by simp) hsat
    StmtT.skip (hL4.endOK _)
  have hc := StmtT.letcall (ξ := .none) (P := P) (Γ := K3) (F := []) (x := 3) (f := 0) (args := [0, 2])
    (s := .letv 4 (.sat 2 (.lit 0)) .skip) (E := ER) (Γ1 := K3) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) call_ok h4.ofNone ((hL4.exitScope 4).endOK _)
    (fun fn hf ho _ => by simp [P] at hf; subst hf; simp [g] at ho)
  have hK2 : NoRootb K2 := (noRootb_empty.setE (by simp [Evv])).setE (by simp [Esrc])
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [Evv])
  have hview : RhsT K2 [] (.view 1) Esv K2 := by
    have := RhsT.view (Γ := K2) (F := []) (y := 1) (E := Esrc) (t := .int) (by simp [K2, A2.setE]) rfl rfl rfl
    simpa [derive, Mode.isRoot, rootKind, Esrc, Esv, vi, sl] using this
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .view 1) (E := Esv) (F := []) (Γ := K2) (Γ1 := K2)
    rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hview hc.ofNone (((hL4.exitScope 4).exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .new .int) (E := Esrc) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE, upd]) (by simp) (RhsT.new rfl) h2.ofNone
    ((((hL4.exitScope 4).exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new vi) (E := Evv) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new rfl) h1.ofNone
    (((((hL4.exitScope 4).exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

theorem main_codes : main.codesOK P := by simp [main, Stmt.codesOK, Rhs.codeOK]

/-- **The program is memory safe**: an `inout` callee that changes elements
    through a borrow of its parameter, called with an argument that holds a
    view, which is read after the call. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 5) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

end A2.InoutViewArgWitness
