import A2.ParamViewWitness
import A2.FreshClosureWitness

/-! # AGORA-909: closure code that stores a view its caller lent it through a borrow of its own local

    : ( Vec i ) v ( vec_new [i] )  : ( Slice i ) s ( slice_from_vec [i] v )
    : ( @ v i ) f \ [s] … → v {
        : ( Vec ( Vec [i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [[i] ) )
        ( vec_push [[i] ( vec_at loc 0 ) s )   -- a view the caller lent, stored THROUGH a borrow
    }
    ( f )

AGORA-909's own program (github#2041): a closure, called through its
package with an argument that holds views, whose code changes elements
through a borrow and stores a view the call passed. Here the view is the
environment (the receiver the call hands the code, lent); in the issue it is
an explicit parameter `x`. Both are a borrowed parameter of the code.

Before, closure code that changed elements through a borrow was
through-changing (`ThruFn`). `Implements` then let it take only an
environment that holds no views, and `CallT` let a call into it pass no
argument that holds views (`callR = []`). Both are refused here.

Now the borrow `( vec_at loc 0 )` is fresh: it is rooted in the code's own
frame (Agora #909, design e). It is not held-fresh, since `loc` holds
views. So the store of a borrowed parameter's view through it is an
`edit false` (Agora #3932, `StmtT.editBV`'s `hbs` by its left disjunct).
The code is not through-changing (`code_not_thru`), and `Implements` and
`CallT` ask nothing.

This is the relaxation the task asked for: "no borrow the body changes
through is rooted in an argument". A borrow rooted in the frame is fresh,
and its edit does not count as a change of the caller's memory. Where the
call places it, a call lifts it, and `loc`, with all the arguments hold
(`RSetup.heldA`, `pushArg_ren_sub`).

`prog_ok`, `main_typed`, and `memory_safe` / `no_leak_end` applied
(`main_safe`, `main_no_leak`).
-/

namespace A2.ClosureParamViewWitness
open A2.DynCell (NoRootb noRootb_empty)
open A2.ThruClosureWitness (Calm R0 killE_int r0_exit body_typed)
open A2.DtorWitness (EN0 EVw)
open A2.FreshWitness (thruL thruL_typed)
open A2.StoreViewWitness (sl vsl vvsl Eloc Ein Ee calm_killThruV calm_holdThru killHv_mode)
open A2.FreshClosureWitness (CT fbody callT_recv)

/-- The code's body: `loc` 3, the inner `Vec` 4, the element borrow `e` 5;
    the environment, parameter 0, pushed through `e`. -/
def storeE : Stmt :=
  .letv 3 (.new vsl) (.letv 4 (.new sl) (.seq (.push 3 4)
    (.letv 5 (.at 3 (.lit 0)) (.edit false 5 (.push 0)))))

/-- The environment, as the code sees it: a borrowed slice. -/
def Es : Entry := ⟨sl, .rootb, true, [], [], false, false, false, false⟩

/-- The interface: it takes the receiver lent (its body is
    `FreshClosureWitness`'s, which changes nothing of the receiver's). -/
def sig : Fn where
  params := [(.inp, CT)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := fbody
  nvars := 6

/-- The closure's code: it takes the environment, a slice, lent, and stores
    it through a borrow of its own local. -/
def code : Fn where
  params := [(.inp, sl)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq storeE (.assign 1 (.expr (.lit 0)))
  nvars := 6

def P : Prog := [sig, code]

/-! ### The store, typed `edit false` -/

/-- `( vec_push [[i] e s )` through the fresh element borrow `e`, which is not
    held-fresh, storing the borrowed parameter `s` (0) itself. -/
theorem edit_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ) (h3 : Γ 3 = some Eloc) (h5 : Γ 5 = some Ee)
    (h0 : Γ 0 = some Es) :
    StmtT Q .none Γ [] (.edit false 5 (.push 0))
      (A2.setE (A2.holdThru (memDeps (derive 0 Es .self ++ Es.held)) [⟨3, .inner⟩]
        (A2.killThruV (.push 0) vsl [⟨3, .inner⟩] Γ)) 5
        { Ee with held := Ee.held ++ memDeps (derive 0 Es .self ++ Es.held) }) := by
  refine StmtT.editBV (b := false) (Ex := Ee) (Ex1 := Ee) (t := sl) h5 rfl rfl rfl rfl (Or.inl rfl) (by simp)
    (EditArg.push (Ey := Es) h0 rfl rfl (PushArg.slice (Or.inr rfl)))
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide) h5 rfl
    (by simp [Ee, memDeps, Kind.isName]) ?_ ?_ (fun h => by simp [Edit.drops] at h) (fun _ => rfl) ?_
  · -- the change's effect through `e`, whose path is `loc`'s elements: `loc` is a live owner
    intro d hd
    simp only [Ee, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
      List.mem_singleton] at hd
    subst hd
    refine ⟨by simp, fun y hy => ?_, _, h3, rfl, Or.inl rfl, hc.dtor _ _ _, by simp [Eloc, vvsl, vsl]⟩
    simp [Edit.stored] at hy; subst hy; decide
  · -- ... ends no view a destructor reads, `loc` is no `letd`'s, and what is stored depends on `s`
    intro d hd
    simp only [Ee, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
      List.mem_singleton] at hd
    subst hd
    exact ⟨hc.dtor _ _ _, by simp [argE, h3, Eloc], by simp [roots, memDeps, derive, Es, Mode.isRoot, rootKind,
      sl, Kind.isName]⟩
  · -- Agora #3932: the element borrow is not held-fresh, so it may store a view of a
    -- borrowed parameter
    intro _
    exact Or.inl rfl

theorem storeE_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ)
    (h3 : Γ 3 = none) (h4 : Γ 4 = none) (h5 : Γ 5 = none)
    (h0 : Γ 0 = some Es) (h1 : Γ 1 = some R0) :
    ∃ Δ, StmtT Q .none Γ [] storeE Δ ∧ Calm Δ ∧ Δ 1 = some R0 := by
  have hR0 : R0.ty = .int := rfl
  have hR0r : R0.mode = .rootb → R0.vdeps = [] := fun h => by simp [R0] at h
  let G3 := A2.setE Γ 3 Eloc
  have hG3 : Calm G3 := hc.setE (by simp [Eloc])
  let G4 := A2.setE G3 4 Ein
  have hG4 : Calm G4 := hG3.setE (by simp [Ein])
  -- `( vec_push loc ( vec_new … ) )`: the inner `Vec` moves into `loc`
  let G4' := A2.setE (A2.kill .replace false 4 G4) 4 { Ein with live := false, dtor := false }
  have hG4' : Calm G4' := (hG4.kill _ _ _).setE (by simp [Ein])
  have hpush : StmtT Q .none G4 [] (.push 3 4)
      (A2.setE (A2.kill .realloc vsl.holdsView 3 G4') 3 { Eloc with held := Eloc.held ++ ownHeld true vsl Ein.held }) :=
    StmtT.push (Ex := Eloc) (Ey := Ein) (Ex1 := Eloc) (t := vsl) (by simp [G4, G3, A2.setE, upd]) rfl rfl
      (Or.inl rfl) (by simp) (by simp [G4, A2.setE]) rfl rfl (by decide)
      (PushArg.move (by simp [vsl, Ty.owning]) rfl (by simp) (hG4.noPin _) (hG4.dtor _ _ _))
      (by simp [Ein, roots]) (by simp [G4', G4, G3, A2.setE, upd, A2.kill, killE, hits, Eloc, Entry.vdeps,
        Mode.ownSlot]) rfl (hG4'.dtor _ _ _) (fun h => by simp [Eloc] at h)
  let G5 := A2.setE (A2.kill .realloc vsl.holdsView 3 G4') 3 { Eloc with held := Eloc.held ++ ownHeld true vsl Ein.held }
  have hG5 : Calm G5 := (hG4'.kill _ _ _).setE (by simp [Eloc])
  have hG53 : G5 3 = some Eloc := by simp [G5, A2.setE, Eloc, Ein, ownHeld]
  have hG50 : G5 0 = some Es := by
    simp [G5, G4', G4, G3, A2.setE, upd, A2.kill, killE, hits, h0, Es, Entry.vdeps, Mode.ownSlot]
  -- `( vec_at loc 0 )`, fresh: `loc` is an owner
  have hat : RhsT G5 [] (.at 3 (.lit 0)) Ee G5 := by
    have := RhsT.at (Γ := G5) (F := []) (E := Eloc) (t := vsl) (i := .lit 0) (f := true) hG53 rfl rfl ExprT.lit
      (fun _ => ⟨⟨Eloc, hG53, Or.inl (Or.inl rfl)⟩, fun s h => by cases h⟩)
    simpa [elemE, Eloc, Ee, vsl, vvsl, derive, Mode.isRoot, rootKind] using this
  let G6 := A2.setE G5 5 Ee
  have hG6 : Calm G6 := hG5.setE (by simp [Ee])
  have hG63 : G6 3 = some Eloc := by simp [G6, A2.setE, upd, hG53]
  have hed := edit_typed (Q := Q) hG6 hG63 (by simp [G6, A2.setE]) (by simp [G6, A2.setE, upd, hG50])
  let Δe := A2.setE (A2.holdThru (memDeps (derive 0 Es .self ++ Es.held)) [⟨3, .inner⟩]
        (A2.killThruV (.push 0) vsl [⟨3, .inner⟩] G6)) 5
        { Ee with held := Ee.held ++ memDeps (derive 0 Es .self ++ Es.held) }
  have hΔe : Calm Δe := by
    refine (calm_holdThru (calm_killThruV hG6 _ _ _) _ _ ?_).setE (by simp [Ee])
    intro r hr E hE
    simp [roots, memDeps, Kind.isName] at hr; subst hr
    obtain ⟨E0, h0', hm⟩ := killHv_mode hE
    rw [hG63] at h0'; cases h0'; rw [hm]; simp [Eloc]
  have hΔe1 : Δe 1 = some R0 := by
    have hG61 : G6 1 = some R0 := by
      simp [G6, G5, G4', G4, G3, A2.setE, upd, A2.kill, h1, killE_int hR0 hR0r]
    have hk : A2.killThruV (.push 0) vsl [⟨3, .inner⟩] G6 1 = some R0 := by
      simp only [A2.killThruV, thruKills, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos,
        List.filter_nil, List.map_cons, List.map_nil, A2.killHv, A2.kill, hG61, Option.map_some,
        killE_int hR0 hR0r]
    simp [Δe, A2.setE, upd, A2.holdThru, A2.holdOn, hk, roots, memDeps, Kind.isName]
  have hl5 := StmtT.letv (P := Q) (ξ := .none) (x := 5) (Γ := G5) (Γ1 := G5) (F := []) (E := Ee)
    (s := .edit false 5 (.push 0)) rfl (by simp [G5, G4', G4, G3, A2.setE, upd, A2.kill, h5]) (by simp) hat
    hed.ofNone (hΔe.endOK _) (fun h => by simp [Ee] at h)
  have hs := StmtT.seq (P := Q) (ξ := .none) rfl hpush hl5
  have hl4 := StmtT.letv (P := Q) (ξ := .none) (x := 4) (Γ := G3) (Γ1 := G3) (F := []) (E := Ein)
    rfl (by simp [G3, A2.setE, upd, h4]) (by simp) (RhsT.new (t := sl) rfl) hs.ofNone
    ((hΔe.exitScope 5).endOK _) (fun _ => rfl)
  have hl3 := StmtT.letv (P := Q) (ξ := .none) (x := 3) (Γ := Γ) (Γ1 := Γ) (F := []) (E := Eloc)
    rfl h3 (by simp) (RhsT.new (t := vsl) rfl) hl4.ofNone
    (((hΔe.exitScope 5).exitScope 4).endOK _) (fun _ => rfl)
  refine ⟨_, hl3, ((hΔe.exitScope 5).exitScope 4).exitScope 3, ?_⟩
  exact r0_exit (by decide) (r0_exit (by decide) (r0_exit (by decide) hΔe1))

/-! ### The program -/

theorem sig_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [sig, fbody, thruL, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [sig, fbody, thruL, Stmt.calls] at hg

/-- **The code is not through-changing**: its one change through a borrow,
    storing a view the call passed, is an `edit false`. -/
theorem code_not_thru : ¬ ThruFn P 1 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [code, storeE, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [code, storeE, Stmt.calls] at hg

theorem calm_sig : Calm (sigCtx sig) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := sig) (by decide), sig, paramE, symNames, CT, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem calm_code : Calm (sigCtx code) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := code) (by decide), code, paramE, sl, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem sig_body : ∃ Δ, StmtT P .none (sigCtx sig) [] sig.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  show ∃ Δ, StmtT P .none (sigCtx sig) [] fbody Δ ∧ _ ∧ _
  apply body_typed
  let G := A2.setE (sigCtx sig) 5 intE
  have hG : Calm G := calm_sig.setE (by simp [intE])
  obtain ⟨Δ, ht, hcΔ, h1'⟩ := thruL_typed (Q := P) hG (n := 5) (En := intE) (by simp [G, A2.setE]) rfl rfl
    (by decide) (by decide) (by decide) (by simp [G, A2.setE, upd, ↓sigCtx_noRegion (fn := sig) (by decide), sig])
    (by simp [G, A2.setE, upd, ↓sigCtx_noRegion (fn := sig) (by decide), sig]) (by simp [G, A2.setE, upd, ↓sigCtx_noRegion (fn := sig) (by decide), sig])
    (by simp [G, A2.setE, upd, ↓sigCtx_noRegion (fn := sig) (by decide), sig, R0, resMode])
  refine ⟨_, StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := sigCtx sig) (Γ1 := sigCtx sig) (F := [])
    (E := intE) rfl (by simp [↓sigCtx_noRegion (fn := sig) (by decide), sig]) (by simp) (RhsT.expr ExprT.lit) ht.ofNone (hcΔ.endOK _)
    (fun h => by simp [intE] at h), hcΔ.exitScope 5, ?_⟩
  simp [A2.exitScope, upd, A2.kill, h1', killE, hits, R0]

theorem code_body : ∃ Δ, StmtT P .none (sigCtx code) [] code.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  apply body_typed
  exact storeE_typed (Q := P) calm_code (by simp [↓sigCtx_noRegion (fn := code) (by decide), code]) (by simp [↓sigCtx_noRegion (fn := code) (by decide), code])
    (by simp [↓sigCtx_noRegion (fn := code) (by decide), code]) (by simp [↓sigCtx_noRegion (fn := code) (by decide), code, paramE, Es, sl, Ty.hasFn])
    (by simp [↓sigCtx_noRegion (fn := code) (by decide), code, R0, resMode, paramE])

theorem code_ok : FnOK P code := by
  obtain ⟨Δ, hb, hfl, hr⟩ := code_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [code], ?_, by simp [code], by simp [code], by simp [code],
    by simp [code], by simp [code], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [code] at hpt; subst hpt; simp [sl, Ty.ok, Ty.isStruct, Ty.holdsView]
  · exact dtorParamsOK_of (by simp [code, sl, Ty.holdsDtor]) (by simp [code])
  · exact ⟨{ intE with mode := R0.mode }, by simpa [code] using hr, rfl, rfl, by simp [R0, resMode, code],
      by simp [intE], by simp [intE], by simp [code]⟩
  · intro i hi b hb; simp [code] at hi; subst hi; simp [code] at hb

theorem sig_ok : FnOK P sig := by
  obtain ⟨Δ, hb, hfl, hr⟩ := sig_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [sig], ?_, by simp [sig], by simp [sig], by simp [sig],
    by simp [sig], by simp [sig], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [sig] at hpt; subst hpt; simp [CT, Ty.ok]
  · exact dtorParamsOK_of (by simp [sig, CT, Ty.holdsDtor]) (by simp [sig])
  · exact ⟨{ intE with mode := R0.mode }, by simpa [sig] using hr, rfl, rfl, by simp [R0, resMode, sig],
      by simp [intE], by simp [intE], by simp [sig]⟩
  · intro i hi b hb; simp [sig] at hi; subst hi; simp [sig] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl
  · exact sig_ok
  · exact code_ok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  rcases hfn with rfl | rfl <;> simp [sig, code, fbody, thruL, storeE, Stmt.codesOK, Rhs.codeOK]

/-- **The code implements its interface on an environment that holds
    views**: it is not through-changing, so `Implements` asks nothing of
    the environment. -/
theorem code_impl : Implements P 1 sl [] 0 :=
  ⟨code, sig, rfl, rfl, rfl, fun h => absurd rfl h, rfl, rfl, fun _ h => h, fun _ h => h, fun _ h => h,
    fun h => absurd h code_not_thru⟩

theorem pack_codes : CodeOK P [1] sl [0] [] := by
  refine ⟨rfl, fun j f σ hf hσ => ?_⟩
  rcases j with _ | j
  · simp at hf hσ; subst hf hσ; exact code_impl
  · simp at hf

/-! ### The caller: the closure over a view, called through its package -/

/-- `: v ( new int )  : s ( view v )  : f \ [s] …  ( f.0 )`: `v` is 0, `s` 1,
    the package 2, the result 3. -/
def main : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.pack [1] sl [0] 1 []) (.callc 3 2 0 0 [] .skip)))

theorem main_typed : ∃ Δ, StmtT P ξ (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  have h21 : K2 1 = some EVw := by simp [K2, A2.setE]
  let EC : Entry := ⟨CT, .own, true, [], (derive 1 EVw .self ++ EVw.held) ++ capDeps [], false, false, false, false⟩
  have hpack : RhsT K2 [] (.pack [1] sl [0] 1 []) EC K2 :=
    RhsT.pack (q := .any) (Ey := EVw) h21 rfl rfl (PushArg.slice (s := .int) (Or.inl rfl))
      ⟨List.nodup_nil, fun _ h => by cases h⟩ (Cross.fits_any _ _ rfl)
  let K3 : Ctx := A2.setE K2 2 EC
  have hK3 : NoRootb K3 := hK2.setE (by simp [EC])
  have h32 : K3 2 = some EC := by simp [K3, A2.setE]
  have hcT : CallT P K3 [] 0 [2] (callRes K3 sig [2]) K3 :=
    callT_recv rfl rfl h32 rfl
      (by simp [mutNames, argNames, nameDeps, argE, h32, EC, EVw, EN0, derive, Mode.isRoot, rootKind,
        Entry.vdeps, Mode.ownSlot, capDeps, comp, Kind.isName])
      (fun h => absurd h sig_not_thru)
  let ER : Entry := recvRes 2 EC (callRes K3 sig [2])
  have hER : ER.mode ≠ .rootb ∧ ER.dtor = false ∧ ER.dbind = false := by
    simp [ER, recvRes, callRes, resMode, sig]
  have hK4 : NoRootb (A2.setE K3 3 ER) := hK3.setE hER
  have hcall := StmtT.callc (ξ := .none) (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (c := 2) (j := 0)
    (zs := []) (k := .skip) (Ec := EC) (E := callRes K3 sig [2]) (ms := [0]) (q := .any) (σ := 0)
    (sig := sig) rfl (by simp [K3, K2, K1, A2.setE, upd]) (by simp) h32 rfl rfl rfl rfl
    (fun o ho => by simp [sig] at ho) hcT (fun _ h => by cases h) StmtT.skip (hK4.endOK _)
    (fun ho => by simp [sig] at ho)
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .pack [1] sl [0] 1 []) (E := EC) (F := [])
    (Γ := K2) (Γ1 := K2) rfl (by simp [K2, K1, A2.setE, upd]) (by simp) hpack hcall.ofNone
    ((hK4.exitScope 3).endOK _) (fun _ => rfl)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2.ofNone (((hK4.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1.ofNone
    ((((hK4.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

theorem main_codes : main.codesOK P := by
  simp only [main, Stmt.codesOK, Rhs.codeOK, true_and, and_true]
  exact pack_codes

/-- **The program is memory safe**: a closure whose environment holds a view
    of the caller's memory, called through its package, whose code stores
    that view through a fresh borrow of its own local. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 4) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact memory_safe prog_ok prog_codes ht rfl main_codes (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 4) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed (ξ := .none)
  exact no_leak_end prog_ok prog_codes ht rfl main_codes (by decide) hr

end A2.ClosureParamViewWitness
