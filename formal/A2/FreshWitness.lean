import A2.ThruDtorWitness

/-! # Agora #909: through-changing code handed a value that holds views

    : V { [i s  i k }
    % Drop V { @ drop V d → v {
        : ( Vec ( Vec i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [i] ) )
        ( vec_push [i] ( vec_at loc 0 ) 7 )   -- a push THROUGH a borrow of loc's element
    } }
    : v ( vec_new [i] )  : s ( vec_view v )  : k 3  :drop x ( V s k )

The struct `V` holds a view (`s`, of `v`), so `letd` arms its binding
(`Ty.dtorViews`), and the call its frame's end makes hands the destructor a
value that holds views: `callR ≠ []`.  Its destructor changes elements
through a borrow, of its own local's element.  Before, both were outside the
claim: a destructor that changes elements through a borrow had to run on a
type that holds no views (`DtorOK`), and a call into such code had to pass no
argument holding views (`CallT`'s `ThruFn` premise), because a call's lift
added everything the arguments hold to every borrow's path (`RSetup.liftE`).

Now the borrow `( vec_at loc 0 )` is fresh (`RhsT.at` with the bit set, from
`loc`, an owner: `FreshSrc`), and the push through it is an `edit false`
(`StmtT.editB` with `Ex.fresh`). It reaches only `loc`'s blocks, never
memory an argument views.  So the
destructor is not `ThruFn` (`dtor_not_thru`), and the call needs nothing of
its argument.

`prog_ok`, `main_typed`, and `memory_safe` / `no_leak_end` applied
(`main_safe`, `main_no_leak`).
-/

namespace A2.FreshWitness
open A2.DynCell (NoRootb noRootb_empty)
open A2.ThruClosureWitness (vi vvi Calm R0 Eloc Ein killE_int thru_ok r0_exit r0_setE r0_killNames body_typed)
open A2.DtorWitness (EN0 EVw endOK_viewing exitScope_setE_same)

/-- The through-changing body, its push through the element borrow an
    `edit false`: through a fresh borrow. -/
def thruL (n : Var) : Stmt :=
  .letv 2 (.new vi) (.letv 3 (.new .int) (.seq (.push 2 3)
    (.letv 4 (.at 2 (.lit 0)) (.edit false 4 (.push n)))))

/-- The element borrow, fresh: its path is `loc`'s elements. -/
def EbF : Entry := ⟨vi, .bor, true, [⟨2, .inner⟩], [], false, false, true, false⟩

theorem thruL_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ) {n : Var} {En : Entry} (hn : Γ n = some En)
    (hnl : En.live = true) (hnt : En.ty = .int) (hnv : En.mode = .rootb → En.vdeps = [])
    (hn2 : n ≠ 2) (hn3 : n ≠ 3) (hn4 : n ≠ 4)
    (h2 : Γ 2 = none) (h3 : Γ 3 = none) (h4 : Γ 4 = none) (h1 : Γ 1 = some R0) :
    ∃ Δ, StmtT Q .none Γ [] (thruL n) Δ ∧ Calm Δ ∧ Δ 1 = some R0 := by
  let G2 := A2.setE Γ 2 Eloc
  have hG2 : Calm G2 := hc.setE (by simp [Eloc])
  let G3 := A2.setE G2 3 Ein
  have hG3 : Calm G3 := hG2.setE (by simp [Ein])
  have h3n : G3 n = some En := by simp [G3, G2, A2.setE, upd, hn2, hn3, hn]
  let G3' := A2.setE (A2.kill .replace false 3 G3) 3 { Ein with live := false, dtor := false }
  have hG3' : Calm G3' := (hG3.kill _ _ _).setE (by simp [Ein])
  have hpush : StmtT Q .none G3 [] (.push 2 3)
      (A2.setE (A2.kill .realloc vi.holdsView 2 G3') 2 { Eloc with held := Eloc.held ++ ownHeld true vi Ein.held }) :=
    StmtT.push (Ex := Eloc) (Ey := Ein) (Ex1 := Eloc) (t := vi) (by simp [G3, G2, A2.setE, upd]) rfl rfl
      (Or.inl rfl) (by simp) (by simp [G3, A2.setE]) rfl rfl (by decide)
      (PushArg.move (by simp [vi, Ty.owning]) rfl (by simp) (hG3.noPin _) (hG3.dtor _ _ _))
      (by simp [Ein, roots]) (by simp [G3', G3, G2, A2.setE, upd, A2.kill, killE, hits, Eloc, Entry.vdeps,
        Mode.ownSlot]) rfl (hG3'.dtor _ _ _) (fun h => by simp [Eloc] at h)
  let G4 := A2.setE (A2.kill .realloc vi.holdsView 2 G3') 2 { Eloc with held := Eloc.held ++ ownHeld true vi Ein.held }
  have hG4 : Calm G4 := (hG3'.kill _ _ _).setE (by simp [Eloc])
  have hG42 : G4 2 = some Eloc := by simp [G4, A2.setE, Eloc, ownHeld, vi, Ty.holdsView]
  have hke := killE_int hnt hnv
  have hG4n : G4 n = some En := by
    simp [G4, G3', A2.setE, upd, A2.kill, hn2, hn3, h3n, hke]
  -- `( vec_at loc 0 )`, fresh: `loc` is an owner
  let G5 := A2.setE G4 4 EbF
  have hG5 : Calm G5 := hG4.setE (by simp [EbF])
  have hat : RhsT G4 [] (.at 2 (.lit 0)) EbF G4 := by
    have := RhsT.at (Γ := G4) (F := []) (E := Eloc) (t := vi) (i := .lit 0) (f := true) hG42 rfl rfl ExprT.lit
      (fun _ => ⟨⟨Eloc, hG42, Or.inl (Or.inl rfl)⟩, fun s h => by cases h⟩)
    simpa [elemE, Eloc, EbF, vi, vvi, derive, Mode.isRoot, rootKind] using this
  -- the push through the fresh borrow: an `edit false`
  have hed := StmtT.editB (b := false) (P := Q) (ξ := .none) (Γ := G5) (Γ1 := G5) (F := []) (x := 4)
    (op := .push n) (Ex := EbF) (Ex1 := EbF) (t := .int) (D := []) (by simp [G5, A2.setE]) rfl rfl rfl rfl
    (by simp) (EditArg.push (Ey := En) (by simp [G5, A2.setE, hn4, hG4n]) hnl hnt PushArg.int)
    (fun y hy => by simp [Edit.stored] at hy; subst hy; exact hn4)
    (by simp [G5, A2.setE]) rfl (by simp [EbF, memDeps, Kind.isName])
    (thru_ok hG5 (E := Eloc) (by simp [G5, A2.setE, hG42]) rfl rfl hn2)
    (fun h => by simp [Edit.drops] at h) (fun _ => rfl)
  have hD5 : Calm (A2.setE (A2.killThru (.push n) (Ty.vec .int) [⟨2, .inner⟩] G5) 4 EbF) :=
    (hG5.killThru _ _ _).setE (by simp [EbF])
  have hl4 := StmtT.letv (P := Q) (ξ := .none) (x := 4) (Γ := G4) (Γ1 := G4) (F := []) (E := EbF)
    (s := .edit false 4 (.push n)) rfl (by simp [G4, A2.setE, upd, G3', A2.kill, G3, G2, h4]) (by simp) hat
    hed.ofNone (hD5.endOK _) (fun h => by simp [EbF] at h)
  have hs := StmtT.seq (P := Q) (ξ := .none) rfl hpush hl4
  have hl3 := StmtT.letv (P := Q) (ξ := .none) (x := 3) (Γ := G2) (Γ1 := G2) (F := []) (E := Ein)
    rfl (by simp [G2, A2.setE, h3]) (by simp) (RhsT.new (t := .int) rfl) hs.ofNone
    ((hD5.exitScope 4).endOK _) (fun _ => rfl)
  have hl2 := StmtT.letv (P := Q) (ξ := .none) (x := 2) (Γ := Γ) (Γ1 := Γ) (F := []) (E := Eloc)
    rfl h2 (by simp) (RhsT.new (t := vi) rfl) hl3.ofNone
    (((hD5.exitScope 4).exitScope 3).endOK _) (fun _ => rfl)
  refine ⟨_, hl2, ((hD5.exitScope 4).exitScope 3).exitScope 2, ?_⟩
  have hG51 : G5 1 = some R0 := by
    simp [G5, G4, G3', G3, G2, A2.setE, upd, A2.kill, h1, killE_int (E := R0) rfl (by simp [R0])]
  exact r0_exit (by decide) (r0_exit (by decide) (r0_exit (by decide)
    (r0_setE (by decide) (r0_killNames hG51 _))))

/-! ### The program: the destructor of a struct that holds a view -/

def TV : Ty := .prod (.slice .int) .int
def DTV : Ty := .dtor 0 TV

def dtor : Fn where
  params := [(.inp, DTV)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq (.letv 5 (.expr (.lit 7)) (thruL 5)) (.assign 1 (.expr (.lit 0)))
  nvars := 6

def P : Prog := [dtor]

/-- **The destructor is not through-changing**: its one change through a
    borrow is an `edit false`, through a fresh borrow. -/
theorem dtor_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dtor, thruL, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dtor, thruL, Stmt.calls] at hg

/-- **It is a destructor for a type that holds views.** -/
theorem dtor_ok : DtorOK P 0 DTV :=
  ⟨dtor, rfl, rfl, rfl, rfl, rfl, rfl, rfl, fun h => absurd h dtor_not_thru⟩

theorem drop_ok : DropFnOK P 0 TV := Or.inl ⟨dtor_ok, by decide⟩

theorem calm_dtor : Calm (sigCtx dtor) := by
  intro v E h
  refine ⟨fun hm d hd => ?_, (sigCtx_flags h).1, (sigCtx_flags h).2⟩
  rcases sigCtx_cases h with ⟨hvl, rfl⟩ | ⟨_, rfl⟩ | ⟨_, _, _, _, rfl⟩
  · rcases mem_regionP_vdeps hd with hd | ⟨rfl, _⟩
    · have hv0 : v = 0 := by simp [dtor] at hvl; omega
      subst hv0
      simp [dtor, paramE, DTV, TV, Ty.hasFn, Entry.vdeps, Mode.ownSlot] at hd
    · rfl
  · unfold resMode at hm; split at hm <;> cases hm
  · simp [regionE] at hm

theorem dtor_body : ∃ Δ, StmtT P .none (sigCtx dtor) [] dtor.body Δ ∧
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    Δ 1 = some { intE with mode := R0.mode } := by
  apply body_typed
  let G := A2.setE (sigCtx dtor) 5 intE
  have hG : Calm G := calm_dtor.setE (by simp [intE])
  obtain ⟨Δ, ht, hcΔ, h1⟩ := thruL_typed (Q := P) hG (n := 5) (En := intE) (by simp [G, A2.setE]) rfl rfl (fun h => by simp [intE] at h)
    (by decide) (by decide) (by decide) (by simp [G, A2.setE, sigCtx, isRegionIdx, dtor])
    (by simp [G, A2.setE, sigCtx, isRegionIdx, dtor]) (by simp [G, A2.setE, sigCtx, isRegionIdx, dtor])
    (by simp [G, A2.setE, sigCtx, dtor, R0, resMode])
  refine ⟨_, StmtT.letv (P := P) (ξ := .none) (x := 5) (Γ := sigCtx dtor) (Γ1 := sigCtx dtor) (F := [])
    (E := intE) rfl (by simp [sigCtx, isRegionIdx, dtor]) (by simp) (RhsT.expr ExprT.lit) ht.ofNone (hcΔ.endOK _)
    (fun h => by simp [intE] at h), hcΔ.exitScope 5, ?_⟩
  simp [A2.exitScope, upd, A2.kill, h1, killE, hits, R0]

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
  subst hfn; simp [dtor, thruL, Stmt.codesOK, Rhs.codeOK]

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
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 6) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### Negative witnesses: what `edit false` is refused

An `edit false` is typed only through a fresh borrow (`edit_false_fresh`),
and an element borrowed from a borrowed parameter, or from a borrow that is
not fresh, is never fresh (`at_rootb_not_fresh`, `at_bor_not_fresh`).  So a
destructor that pushes through a borrow of its parameter's memory, which a
caller sees, has no `edit false` typing: it is `edit true`, `ThruFn`, and
`DtorOK` refuses it on a type that holds views, as before. -/

theorem edit_false_fresh' {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {s : Stmt}
    (ht : StmtT Q ξ Γ F s Δ) : ∀ {x op}, s = .edit false x op → ∀ {Ex}, Γ x = some Ex →
      Ex.fresh = true ∧ Ex.mode = .bor ∧ Ex.live = true ∧ Ex.ty ≠ .int := by
  induction ht with
  | sub hw _ _ ih =>
    intro x op hs Ex hx
    obtain ⟨hn, hwE⟩ := hw.1 x
    obtain ⟨Ex0, hx0⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hn.mpr h] at hx; cases hx)
    obtain ⟨hf, hm, hl, hty⟩ := ih hs hx0
    have W := hwE Ex Ex0 hx hx0
    exact ⟨(W.fresh hl hty hm hf).1, W.mode ▸ hm, (W.live hl).1, W.ty ▸ hty⟩
  | editB hx' hm hl hty _ _ _ _ _ _ _ _ hbf =>
    intro x op hs Ex hx; cases hs; rw [hx] at hx'; cases hx'
    exact ⟨hbf rfl, hm, hl, by rw [hty]; simp⟩
  -- (Agora #916: ... or through one storing a value the frame's own)
  | editBV hx' hm hl hty _ _ _ _ _ _ _ _ _ _ _ hbf =>
    intro x op hs Ex hx; cases hs; rw [hx] at hx'; cases hx'
    exact ⟨hbf rfl, hm, hl, by rw [hty]; simp⟩
  | _ => intro x op hs; cases hs

/-- **An `edit false` is through a fresh borrow**: every typing of it. -/
theorem edit_false_fresh {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {x : Var} {op : Edit} {Ex : Entry}
    (ht : StmtT Q ξ Γ F (.edit false x op) Δ) (hx : Γ x = some Ex) : Ex.fresh = true :=
  (edit_false_fresh' ht rfl hx).1

/-- A borrowed parameter is no fresh source. -/
theorem rootb_not_freshSrc {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E) (hm : E.mode = .rootb) :
    ¬ FreshSrc Γ y := by
  rintro ⟨E', hy', hE⟩; rw [hy] at hy'; cases hy'
  rcases hE with (h | ⟨b, h⟩) | ⟨h, _⟩ <;> rw [hm] at h <;> cases h

/-- A borrow that is not fresh is no fresh source. -/
theorem stale_not_freshSrc {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E) (hm : E.mode = .bor)
    (hf : E.fresh = false) : ¬ FreshSrc Γ y := by
  rintro ⟨E', hy', hE⟩; rw [hy] at hy'; cases hy'
  rcases hE with (h | ⟨b, h⟩) | ⟨_, h, _⟩
  · rw [hm] at h; cases h
  · rw [hm] at h; cases h
  · rw [hf] at h; cases h

theorem at_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {i : Expr} {E : Entry}
    (ht : RhsT Γ F (.at y i) E Γ1) (hs : ¬ FreshSrc Γ y) : E.fresh = false := by
  cases ht with
  | @«at» _ _ _ _ f _ _ _ _ hf =>
    cases f
    · rfl
    · exact absurd (hf rfl).1 hs

/-- **An element of a borrowed parameter is never fresh.** -/
theorem at_rootb_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {i : Expr} {E Ey : Entry}
    (ht : RhsT Γ F (.at y i) E Γ1) (hy : Γ y = some Ey) (hm : Ey.mode = .rootb) : E.fresh = false :=
  at_not_fresh ht (rootb_not_freshSrc hy hm)

/-- **Nor is an element of a borrow that is not fresh.** -/
theorem at_bor_not_fresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {i : Expr} {E Ey : Entry}
    (ht : RhsT Γ F (.at y i) E Γ1) (hy : Γ y = some Ey) (hm : Ey.mode = .bor) (hf : Ey.fresh = false) :
    E.fresh = false :=
  at_not_fresh ht (stale_not_freshSrc hy hm hf)

end A2.FreshWitness
