import A2.FreshWitness
import A2.EditBVFnWitness

/-! # Agora #916: a destructor of a type that holds views stores a view of its own local through a fresh borrow

    : V { [i s  i k }
    % Drop V { @ drop V d → v {
        : ( Vec i ) w ( vec_new … )
        : ( Vec ( Vec [i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [[i] ) )
        ( vec_push [[i] ( vec_at loc 0 ) ( slice_from_vec w ) )   -- a view stored THROUGH a borrow
    } }
    : v ( vec_new [i] )  : s ( vec_view v )  : k 3  :drop x ( V s k )

The destructor changes elements that hold views (slices) through a borrow,
`( vec_at loc 0 )` of its own local: `StmtT.editBV`.  Before AGORA-916 that was
an `edit true`, through-changing, and a destructor of a type that holds views
(`DtorOK`) may not be one: a call's lift added everything the arguments hold to
what every borrow holds and to every borrow's path, so the stored view counted
as holding the caller's memory (`editBV_ren` needed `S.R = []`).

Now the element borrow is fresh (`RhsT.at` from the owner `loc`), and the
stored view is fresh and held-fresh (`RhsT.view` from the owner `w`, of a type
that holds no views: `FreshSrc`, `HeldSrc`).  The store is an `edit false`
(`editBV` with `hbf`, `hbs`): what it stores holds no memory an argument views,
so the call need not treat it as a change of the caller's (`pushArg_ren_held`).
The destructor is not `ThruFn` (`dtor_not_thru`), and the call passing it the
struct, which holds a view, needs nothing of its argument.

`prog_ok`, `main_typed`, and `memory_safe` / `no_leak_end` applied
(`main_safe`, `main_no_leak`).
-/

namespace A2.StoreViewWitness
open A2.ThruClosureWitness (vi Calm R0 killE_int r0_exit r0_setE r0_killNames body_typed)
open A2.FreshWitness (TV DTV)
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (EN0 EVw endOK_viewing exitScope_setE_same)

def sl : Ty := .slice .int
def vsl : Ty := .vec sl
def vvsl : Ty := .vec vsl

/-- The body: `w` 2, `loc` 3, the inner `Vec` 4, the element borrow `e` 5,
    the view of `w` 6. -/
def storeV : Stmt :=
  .letv 2 (.new .int) (.letv 3 (.new vsl) (.letv 4 (.new sl) (.seq (.push 3 4)
    (.letv 5 (.at 3 (.lit 0)) (.letv 6 (.view 2) (.edit false 5 (.push 6)))))))

def Ew : Entry := ⟨vi, .own, true, [], [], false, false, false, false⟩
def Eloc : Entry := ⟨vvsl, .own, true, [], [], false, false, false, false⟩
def Ein : Entry := ⟨vsl, .own, true, [], [], false, false, false, false⟩
/-- The element borrow, fresh: its path is `loc`'s elements. -/
def Ee : Entry := ⟨vsl, .bor, true, [⟨3, .inner⟩], [], false, false, true, false⟩
/-- The view of `w`, fresh and held-fresh: it reaches `w`'s buffer, and holds nothing. -/
def Ev : Entry := ⟨sl, .bor, true, [⟨2, .view⟩], [], false, false, true, true⟩
/-- What the view depends on, as `PushArg` hands it. -/
def Dv : List Dep := [⟨2, .view⟩]

/-! ### Calm contexts through `editBV` -/

theorem calm_killHv {Γ : Ctx} (h : Calm Γ) : ∀ ks, Calm (A2.killHv ks Γ)
  | [] => h
  | (e, b, r) :: ks => (calm_killHv h ks).kill e b r

theorem calm_killThruV {Γ : Ctx} (h : Calm Γ) (op : Edit) (tx : Ty) (P : List Dep) :
    Calm (A2.killThruV op tx P Γ) := calm_killHv h _

/-- Holding more keeps a calm context calm, when no root that holds more is a
    borrowed parameter. -/
theorem calm_holdThru {Γ : Ctx} (h : Calm Γ) (D Q : List Dep)
    (hr : ∀ r ∈ roots (memDeps Q), ∀ E, Γ r = some E → E.mode ≠ .rootb) :
    Calm (A2.holdThru D Q Γ) := by
  intro v E hv
  obtain ⟨E0, h0, rfl⟩ := holdOn_get hv
  have := h v E0 h0
  split
  · rename_i hm
    exact ⟨fun hrb => absurd hrb (hr v hm E0 h0), by simpa [Entry.hold] using this.2⟩
  · exact this

/-- A kill keeps every binding's mode. -/
theorem killHv_mode {Γ : Ctx} {v : Var} {E : Entry} : ∀ {ks : List (Eff × Bool × Var)},
    A2.killHv ks Γ v = some E → ∃ E0, Γ v = some E0 ∧ E.mode = E0.mode
  | [], h => ⟨E, h, rfl⟩
  | (e, b, r) :: ks, h => by
    simp only [A2.killHv, A2.kill, Option.map_eq_some_iff] at h
    obtain ⟨E1, h1, rfl⟩ := h
    obtain ⟨E0, h0, hm⟩ := killHv_mode h1
    exact ⟨E0, h0, by rw [killE_mode, hm]⟩

/-! ### The store, typed `edit false` -/

/-- `( vec_push [[i] e v )` through the fresh element borrow `e`, storing the
    fresh, held-fresh view `v`: an `edit false`. -/
theorem edit_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ) (h3 : Γ 3 = some Eloc) (h5 : Γ 5 = some Ee)
    (h6 : Γ 6 = some Ev) :
    StmtT Q .none Γ [] (.edit false 5 (.push 6))
      (A2.setE (A2.holdThru (memDeps (derive 6 Ev .self ++ Ev.held)) [⟨3, .inner⟩]
        (A2.killThruV (.push 6) vsl [⟨3, .inner⟩] Γ)) 5
        { Ee with held := Ee.held ++ memDeps (derive 6 Ev .self ++ Ev.held) }) := by
  refine StmtT.editBV (b := false) (Ex := Ee) (Ex1 := Ee) (t := sl) h5 rfl rfl rfl rfl (Or.inl rfl) (by simp)
    (EditArg.push (Ey := Ev) h6 rfl rfl (PushArg.slice (Or.inl rfl)))
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide) h5 rfl
    (by simp [Ee, memDeps, Kind.isName]) ?_ ?_ (fun h => by simp [Edit.drops] at h) (fun _ => rfl) ?_
  · -- the change's effect through `e`, whose path is `loc`'s elements: `loc` is a live owner
    intro d hd
    simp only [Ee, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
      List.mem_singleton] at hd
    subst hd
    refine ⟨by simp, fun y hy => ?_, _, h3, rfl, Or.inl rfl, hc.dtor _ _ _, by simp⟩
    simp [Edit.stored] at hy; subst hy; decide
  · -- ... ends no view a destructor reads, `loc` is no `letd`'s, and what is stored depends on `w`
    intro d hd
    simp only [Ee, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
      List.mem_singleton] at hd
    subst hd
    exact ⟨hc.dtor _ _ _, by simp [argE, h3, Eloc], by simp [roots, memDeps, derive, Ev, Mode.isRoot, comp,
      Kind.isName]⟩
  · -- Agora #916: the stored view is the frame's own, in path and in what it holds
    -- (its right disjunct; the left one holds too, `e` is not held-fresh)
    intro _
    refine Or.inr fun y hy => ?_
    simp [Edit.stored] at hy; subst hy
    exact ⟨⟨Ev, h6, Or.inr ⟨rfl, rfl, rfl, by simp [Ev, sl]⟩⟩, ⟨Ev, h6, Or.inr ⟨rfl, rfl, rfl⟩⟩⟩

/-! ### The body -/

syntax "lkS" : tactic
macro_rules
  | `(tactic| lkS) => `(tactic| simp [A2.setE, upd, A2.kill, killE, hits, A2.exitScope, Entry.vdeps,
      Mode.ownSlot, derive, Mode.isRoot, rootKind, comp, sl, vsl, vvsl, vi, Ew, Eloc, Ein, Ee, Ev, Dv, R0,
      Eff.kills, roots, A2.killThruV, A2.killHv, thruKills, argE, memDeps, Kind.isName, Kind.bound,
      Edit.effAt, elemE, ownHeld, Ty.holdsView, Ty.elem, A2.holdThru, A2.holdOn, Entry.hold,
      List.foldr_cons, List.foldr_nil, List.map_cons, List.map_nil, List.filter_cons, List.filter_nil])

theorem storeV_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ)
    (h2 : Γ 2 = none) (h3 : Γ 3 = none) (h4 : Γ 4 = none) (h5 : Γ 5 = none) (h6 : Γ 6 = none)
    (h1 : Γ 1 = some R0) :
    ∃ Δ, StmtT Q .none Γ [] storeV Δ ∧ Calm Δ ∧ Δ 1 = some R0 := by
  have hR0 : R0.ty = .int := rfl
  have hR0r : R0.mode = .rootb → R0.vdeps = [] := fun h => by simp [R0] at h
  let G2 := A2.setE Γ 2 Ew
  have hG2 : Calm G2 := hc.setE (by simp [Ew])
  let G3 := A2.setE G2 3 Eloc
  have hG3 : Calm G3 := hG2.setE (by simp [Eloc])
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
      (by simp [Ein, roots]) (by simp [G4', G4, G3, G2, A2.setE, upd, A2.kill, killE, hits, Eloc, Entry.vdeps,
        Mode.ownSlot]) rfl (hG4'.dtor _ _ _) (fun h => by simp [Eloc] at h)
  let G5 := A2.setE (A2.kill .realloc vsl.holdsView 3 G4') 3 { Eloc with held := Eloc.held ++ ownHeld true vsl Ein.held }
  have hG5 : Calm G5 := (hG4'.kill _ _ _).setE (by simp [Eloc])
  have hG53 : G5 3 = some Eloc := by simp [G5, A2.setE, Eloc, Ein, ownHeld]
  have hG52 : G5 2 = some Ew := by
    simp [G5, G4', G4, G3, G2, A2.setE, upd, A2.kill, killE, hits, Ew, Entry.vdeps, Mode.ownSlot]
  -- `( vec_at loc 0 )`, fresh: `loc` is an owner
  have hat : RhsT G5 [] (.at 3 (.lit 0)) Ee G5 := by
    have := RhsT.at (Γ := G5) (F := []) (E := Eloc) (t := vsl) (i := .lit 0) (f := true) hG53 rfl rfl ExprT.lit
      (fun _ => ⟨⟨Eloc, hG53, Or.inl (Or.inl rfl)⟩, fun s h => by cases h⟩)
    simpa [elemE, Eloc, Ee, vsl, vvsl, derive, Mode.isRoot, rootKind] using this
  let G6 := A2.setE G5 5 Ee
  have hG6 : Calm G6 := hG5.setE (by simp [Ee])
  have hG62 : G6 2 = some Ew := by simp [G6, A2.setE, hG52]
  -- `( slice_from_vec w )`, fresh and held-fresh: `w` is an owner of a type that holds no views
  have hview : RhsT G6 [] (.view 2) Ev G6 := by
    have := RhsT.view (Γ := G6) (F := []) (y := 2) (E := Ew) (t := .int) (f := true) (h := true) hG62 rfl rfl rfl
      (fun _ => ⟨Ew, hG62, Or.inl rfl⟩) (fun _ => ⟨Ew, hG62, Or.inl ⟨rfl, by simp [Ew, vi, Ty.holdsView]⟩⟩)
    simpa [derive, Mode.isRoot, rootKind, Ew, Ev, vi, sl] using this
  let G7 := A2.setE G6 6 Ev
  have hG7 : Calm G7 := hG6.setE (by simp [Ev])
  have hG73 : G7 3 = some Eloc := by simp [G7, G6, A2.setE, upd, hG53]
  have hed := edit_typed (Q := Q) hG7 hG73 (by simp [G7, G6, A2.setE, upd]) (by simp [G7, A2.setE])
  let Δe := A2.setE (A2.holdThru (memDeps (derive 6 Ev .self ++ Ev.held)) [⟨3, .inner⟩]
        (A2.killThruV (.push 6) vsl [⟨3, .inner⟩] G7)) 5
        { Ee with held := Ee.held ++ memDeps (derive 6 Ev .self ++ Ev.held) }
  have hΔe : Calm Δe := by
    refine (calm_holdThru (calm_killThruV hG7 _ _ _) _ _ ?_).setE (by simp [Ee])
    intro r hr E hE
    simp [roots, memDeps, Kind.isName] at hr; subst hr
    obtain ⟨E0, h0, hm⟩ := killHv_mode hE
    rw [hG73] at h0; cases h0; rw [hm]; simp [Eloc]
  have hΔe1 : Δe 1 = some R0 := by
    have hG71 : G7 1 = some R0 := by
      simp [G7, G6, G5, G4', G4, G3, G2, A2.setE, upd, A2.kill, h1, killE_int hR0 hR0r]
    have hk : A2.killThruV (.push 6) vsl [⟨3, .inner⟩] G7 1 = some R0 := by
      simp only [A2.killThruV, thruKills, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos,
        List.filter_nil, List.map_cons, List.map_nil, A2.killHv, A2.kill, hG71, Option.map_some,
        killE_int hR0 hR0r]
    simp [Δe, A2.setE, A2.holdThru, A2.holdOn, hk, roots, memDeps, Kind.isName]
  have hl6 := StmtT.letv (P := Q) (ξ := .none) (x := 6) (Γ := G6) (Γ1 := G6) (F := []) (E := Ev)
    (s := .edit false 5 (.push 6)) rfl (by simp [G6, G5, G4', G4, G3, G2, A2.setE, upd, A2.kill, h6]) (by simp)
    hview hed.ofNone (hΔe.endOK _) (fun h => by simp [Ev] at h)
  have hl5 := StmtT.letv (P := Q) (ξ := .none) (x := 5) (Γ := G5) (Γ1 := G5) (F := []) (E := Ee)
    rfl (by simp [G5, G4', G4, G3, G2, A2.setE, upd, A2.kill, h5]) (by simp) hat hl6.ofNone
    ((hΔe.exitScope 6).endOK _) (fun h => by simp [Ee] at h)
  have hs := StmtT.seq (P := Q) (ξ := .none) rfl hpush hl5
  have hl4 := StmtT.letv (P := Q) (ξ := .none) (x := 4) (Γ := G3) (Γ1 := G3) (F := []) (E := Ein)
    rfl (by simp [G3, G2, A2.setE, upd, h4]) (by simp) (RhsT.new (t := sl) rfl) hs.ofNone
    (((hΔe.exitScope 6).exitScope 5).endOK _) (fun _ => rfl)
  have hl3 := StmtT.letv (P := Q) (ξ := .none) (x := 3) (Γ := G2) (Γ1 := G2) (F := []) (E := Eloc)
    rfl (by simp [G2, A2.setE, h3]) (by simp) (RhsT.new (t := vsl) rfl) hl4.ofNone
    ((((hΔe.exitScope 6).exitScope 5).exitScope 4).endOK _) (fun _ => rfl)
  have hl2 := StmtT.letv (P := Q) (ξ := .none) (x := 2) (Γ := Γ) (Γ1 := Γ) (F := []) (E := Ew)
    rfl h2 (by simp) (RhsT.new (t := .int) rfl) hl3.ofNone
    (((((hΔe.exitScope 6).exitScope 5).exitScope 4).exitScope 3).endOK _) (fun _ => rfl)
  refine ⟨_, hl2, ((((hΔe.exitScope 6).exitScope 5).exitScope 4).exitScope 3).exitScope 2, ?_⟩
  exact r0_exit (by decide) (r0_exit (by decide) (r0_exit (by decide) (r0_exit (by decide)
    (r0_exit (by decide) hΔe1))))

/-! ### The program: the destructor of a struct that holds a view -/

def dtor : Fn where
  params := [(.inp, DTV)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq storeV (.assign 1 (.expr (.lit 0)))
  nvars := 7

def P : Prog := [dtor]

/-- **The destructor is not through-changing**: its one change through a
    borrow is an `edit false`, through a fresh borrow. -/
theorem dtor_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dtor, storeV, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dtor, storeV, Stmt.calls] at hg

/-- **It is a destructor for a type that holds views.** -/
theorem dtor_ok : DtorOK P 0 DTV :=
  ⟨dtor, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h dtor_not_thru⟩

theorem drop_ok : DropFnOK P 0 TV := Or.inl ⟨dtor_ok, by decide⟩

theorem calm_dtor : Calm (sigCtx dtor) := by
  intro v E h
  rcases v with _ | _ | v <;> simp [↓sigCtx_noRegion (fn := dtor) (by decide), dtor, paramE, DTV, TV, Ty.hasFn, resMode] at h <;>
    subst h <;> simp [Entry.vdeps, Mode.ownSlot]

theorem dtor_body : ∃ Δ, StmtT P .none (sigCtx dtor) [] dtor.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  apply body_typed
  exact storeV_typed (Q := P) calm_dtor (by simp [↓sigCtx_noRegion (fn := dtor) (by decide), dtor]) (by simp [↓sigCtx_noRegion (fn := dtor) (by decide), dtor]) (by simp [↓sigCtx_noRegion (fn := dtor) (by decide), dtor])
    (by simp [↓sigCtx_noRegion (fn := dtor) (by decide), dtor]) (by simp [↓sigCtx_noRegion (fn := dtor) (by decide), dtor]) (by simp [↓sigCtx_noRegion (fn := dtor) (by decide), dtor, R0, resMode])

theorem dtor_fnok : FnOK P dtor := by
  obtain ⟨Δ, hb, hfl, hr⟩ := dtor_body
  refine ⟨rfl, by decide, by decide, rfl, by simp [dtor], ?_, by simp [dtor], by simp [dtor], by simp [dtor],
    by simp [dtor], by simp [dtor], ?_, Δ, hb, hfl, ?_, ?_⟩
  · intro pt hpt; simp [dtor] at hpt; subst hpt; simp [DTV, TV, Ty.ok, Ty.isStruct, Ty.holdsView]
  · refine ⟨fun i hi hs _ => ?_, fun i hi b hb _ => ?_, fun h => by simp [dtor] at h⟩
    · simp [dtor] at hi; subst hi; simp [dtor] at hs
    · simp [dtor] at hi; subst hi; simp [dtor] at hb
  · exact ⟨{ intE with mode := R0.mode }, by simpa [dtor] using hr, rfl, rfl, by simp [R0, resMode, dtor],
      by simp [intE], by simp [intE], by simp [dtor]⟩
  · intro i hi b hb; simp [dtor] at hi; subst hi; simp [dtor] at hb

theorem prog_ok : ProgOK P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; exact dtor_fnok

theorem prog_codes : ProgCodes P := by
  intro fn hfn
  simp only [P, List.mem_cons, List.mem_nil_iff, or_false] at hfn
  subst hfn; simp [dtor, storeV, Stmt.codesOK, Rhs.codeOK]

/-! ### The main program: the struct bound by `letd`, armed -/

/-- `: v ( new int )  : s ( view v )  : k 3  :drop x ( pair s k )` -/
def main : Stmt :=
  .letv 0 (.new .int) (.letv 1 (.view 0) (.letv 2 (.expr (.lit 3)) (.letd 3 0 (.pair 1 2) .skip)))

theorem main_typed : ∃ Δ, StmtT P .none (fun _ => none) [] main Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 EN0
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [EN0])
  let K2 : Ctx := A2.setE K1 1 EVw
  have hK2 : NoRootb K2 := hK1.setE (by simp [EVw])
  let K3 : Ctx := A2.setE K2 2 intE
  have hK3 : NoRootb K3 := hK2.setE (by simp [intE])
  have hview : RhsT K1 [] (.view 0) EVw K1 :=
    RhsT.view (E := EN0) (t := .int) (by simp [K1, A2.setE]) rfl rfl rfl
  have hK31 : K3 1 = some EVw := by simp [K3, K2, A2.setE, upd]
  let EG0 : Entry := ⟨.prod EVw.ty intE.ty, .own, true, [], (derive 1 EVw .self ++ EVw.held) ++ intE.held,
    false, false, false, false⟩
  have hgp : RhsT K3 [] (.pair 1 2) EG0 K3 :=
    RhsT.pair (Ey := EVw) (Ez := intE) hK31 rfl (PushArg.slice (s := .int) (Or.inl rfl))
      (by simp [K3, A2.setE]) rfl PushArg.int (by simp [EVw, EN0, intE, derive, Mode.isRoot, rootKind, roots, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := DTV, held := EG0.held }
  -- armed: it views `v` (binding 0)
  have hEGa : EGa = ⟨DTV, .own, true, [], [⟨0, .view⟩], true, true, false, false⟩ := by
    simp [EGa, EG0, Entry.arm, EVw, EN0, intE, derive, Mode.isRoot, rootKind, comp, DTV, TV,
      Ty.dtorViews, Ty.holdsView]
  have hEnd : EndOK (A2.setE K3 3 EGa) 3 :=
    endOK_viewing hK3 (by rw [hEGa]; simp) (by rw [hEGa]; simp [roots, Entry.vdeps, Mode.ownSlot])
  have hd := StmtT.letd (ξ := .none) (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .pair 1 2)
    (s := .skip) (E := EG0) (t := TV) (H := EG0.held) (τ := DTV) rfl
    (by simp [K3, K2, K1, A2.setE, upd]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, EVw, intE, TV])⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _)
    StmtT.skip hEnd
  rw [exitScope_setE_same] at hd
  have h2 := StmtT.letv (ξ := .none) (P := P) (x := 2) (r := .expr (.lit 3)) (E := intE) (F := []) (Γ := K2)
    (Γ1 := K2) rfl (by simp [K2, K1, A2.setE, upd]) (by simp) (RhsT.expr ExprT.lit) hd.ofNone
    ((hK3.exitScope 3).endOK _)
  have h1 := StmtT.letv (ξ := .none) (P := P) (x := 1) (r := .view 0) (E := EVw) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) hview h2.ofNone (((hK3.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .new .int) (E := EN0) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.new (by decide)) h1.ofNone
    ((((hK3.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- **The program is memory safe**: a struct that holds a view, dropped by a
    destructor that changes elements through a (fresh) borrow. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr


end A2.StoreViewWitness
