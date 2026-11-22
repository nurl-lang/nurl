import A2.StoreViewWitness

/-! # Agora #909's own example: a destructor stores a view of its borrowed parameter through a fresh borrow

    : V { [i s  i k }
    % Drop V { @ drop V d → v {
        : ( Vec ( Vec [i ) ) loc ( vec_new … )
        ( vec_push loc ( vec_new [[i] ) )
        ( vec_push [[i] ( vec_at loc 0 ) . d s )   -- a view of the parameter, stored THROUGH a borrow
    } }
    : v ( vec_new [i] )  : s ( vec_view v )  : k 3  :drop x ( V s k )

The destructor stores `. d s`, a view its caller lent it (what the struct
holds), into an element of its own local `loc`, through the fresh borrow
`( vec_at loc 0 )`.  Before Agora #3932 that store was an `edit true`,
through-changing, and a destructor of a type that holds views may not be one
(`DtorOK`).  The stored view is neither fresh nor held-fresh: what it holds
is its caller's memory.  But the element borrow is not held-fresh either
(`loc` holds views), so a call lifts it with everything the arguments hold
(`RSetup.heldA`), and so it lifts `loc`, an owner of a type that holds views.
Where the call places it, the store's dependencies are what they were,
renamed, and what the arguments hold (`pushArg_ren_sub`): every holder's lift
records them already.  So the store is an `edit false` (`editBV` with `hbf`,
and `hbs` by its left disjunct), and the destructor is not `ThruFn`.

What stays out (`edit_false_unown_unheld`): no `edit false` typing of a
store of a value that is not the frame's own in path and in what it holds
(`¬ (FreshSrc ∧ HeldSrc)`, what `hbs` asks of a held-fresh borrow) leaves its
borrow held-fresh. `edit_false_unfresh_unheld` is its `¬ FreshSrc` half,
which needs nothing of the value's type (a borrowed parameter, a field of
one, a view of one: `param_store_unheld`, `stale_store_unheld`).  A held-fresh borrow
may store such a value only once it is weakened to one that is not
(`EntryWeaker.heldFresh` allows clearing the bit, never setting it), so
the precise lift of a held-fresh borrow (`pushArg_ren_held`) never meets
memory the caller lent.

`prog_ok`, `main_typed`, and `memory_safe` / `no_leak_end` applied
(`main_safe`, `main_no_leak`).
-/

namespace A2.ParamViewWitness
open A2.ThruClosureWitness (vi Calm R0 killE_int r0_exit r0_setE r0_killNames body_typed)
open A2.FreshWitness (TV DTV rootb_not_freshSrc stale_not_freshSrc)
open A2.DynCell (NoRootb noRootb_empty)
open A2.DtorWitness (EN0 EVw endOK_viewing exitScope_setE_same)
open A2.StoreViewWitness (sl vsl vvsl Eloc Ein Ee calm_killThruV calm_holdThru killHv_mode)

/-! ### What stays out: a held-fresh borrow never stores what the caller lent -/

/-- A weakening keeps a fresh source one, read backwards: what is fresh
    where the context is weaker was fresh before. -/
theorem freshSrc_of_weaker {Γ Γ0 : Ctx} (hw : Weaker Γ Γ0) {y : Var} (h : FreshSrc Γ0 y) : FreshSrc Γ y := by
  obtain ⟨E', h0, hc⟩ := h
  obtain ⟨hn, hwE⟩ := hw.1 y
  obtain ⟨E, hE⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hn.mp h] at h0; cases h0)
  have W := hwE E E' hE h0
  refine ⟨E, hE, ?_⟩
  rcases hc with hfr | ⟨hb, hf, hl, hn'⟩
  · left; rw [← W.mode]; exact hfr
  · right
    exact ⟨W.mode ▸ hb, (W.fresh hl hn' hb hf).1, (W.live hl).1, W.ty ▸ hn'⟩

/-- **No `edit false` storing a value that is not the frame's own leaves its
    borrow held-fresh**, of an element type that holds views: every typing. -/
theorem edit_false_unfresh_unheld' {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {s : Stmt}
    (ht : StmtT Q ξ Γ F s Δ) : ∀ {x op y}, s = .edit false x op → op.stored = some y → ¬ FreshSrc Γ y →
      ∀ {Ex t}, Γ x = some Ex → Ex.ty = .vec t → t.holdsView = true →
      ∀ {E}, Δ x = some E → E.ty ≠ .int → E.mode = .bor → E.heldFresh = false := by
  induction ht with
  | sub hw _ hΔ ih =>
    intro x op y hs hy hnf Ex t hx hty hv E hE hn hm
    obtain ⟨hnx, hwE⟩ := hw.1 x
    obtain ⟨Ex0, hx0⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hnx.mpr h] at hx; cases hx)
    have W := hwE Ex Ex0 hx hx0
    have ih' := @ih x op y hs hy (fun h => hnf (freshSrc_of_weaker hw h)) Ex0 t hx0 (by rw [W.ty]; exact hty) hv
    rcases hΔ with rfl | hΔ
    · exact ih' hE hn hm
    · obtain ⟨hnd, hwD⟩ := hΔ.1 x
      obtain ⟨E0, hE0⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hnd.mp h] at hE; cases hE)
      have WD := hwD E0 E hE0 hE
      cases hb : E.heldFresh with
      | false => rfl
      | true =>
        have := WD.heldFresh hn hm hb
        rw [ih' hE0 (WD.ty ▸ hn) (WD.mode ▸ hm)] at this; cases this
  | editB hx' _ _ hty' hv' =>
    intro x op y hs _ _ Ex t hx hty hv
    cases hs; rw [hx] at hx'; cases hx'; rw [hty] at hty'; cases hty'; rw [hv] at hv'; cases hv'
  | editBV hx' _ _ _ _ _ _ harg _ hx1 _ _ _ _ _ _ hbs =>
    intro x op y hs hy hnf Ex t hx _ _ E hE _ _
    cases hs; rw [hx] at hx'; cases hx'
    rw [A2.setE, upd_same] at hE; cases hE
    -- what is stored is not the frame's own, so the borrow was not held-fresh ...
    have hf := (hbs rfl).resolve_right (fun h => hnf (h y hy).1)
    -- ... and storing it changes nothing else: it is copied, not moved
    cases harg with
    | push hy0 _ _ hp | set _ hy0 _ _ hp =>
      simp [Edit.stored] at hy; subst hy
      cases hp with
      | move _ hm _ _ _ => exact absurd ⟨_, hy0, Or.inl (Or.inl hm)⟩ hnf
      | int => rw [hx] at hx1; cases hx1; exact hf
      | slice _ => rw [hx] at hx1; cases hx1; exact hf
    | trunc _ => simp [Edit.stored] at hy
  | _ => intro x op y hs; cases hs

theorem edit_false_unfresh_unheld {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {x y : Var} {op : Edit}
    {Ex E : Entry} {t : Ty} (ht : StmtT Q ξ Γ F (.edit false x op) Δ) (hy : op.stored = some y)
    (hnf : ¬ FreshSrc Γ y) (hx : Γ x = some Ex) (hty : Ex.ty = .vec t) (hv : t.holdsView = true)
    (hE : Δ x = some E) (hn : E.ty ≠ .int) (hm : E.mode = .bor) : E.heldFresh = false :=
  edit_false_unfresh_unheld' ht rfl hy hnf hx hty hv hE hn hm

/-- ... and so does a held-freshness source, of a value that holds memory. -/
theorem heldSrc_of_weaker {Γ Γ0 : Ctx} (hw : Weaker Γ Γ0) {y : Var}
    (hyt : ∀ E, Γ y = some E → E.ty ≠ .int) (h : HeldSrc Γ0 y) : HeldSrc Γ y := by
  obtain ⟨E', h0, hc⟩ := h
  obtain ⟨hn, hwE⟩ := hw.1 y
  obtain ⟨E, hE⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hn.mp h] at h0; cases h0)
  have W := hwE E E' hE h0
  refine ⟨E, hE, ?_⟩
  rcases hc with ⟨hos, hhv⟩ | ⟨hb, hhf, hl⟩
  · left; rw [W.mode] at hos; rw [W.ty] at hhv; exact ⟨hos, hhv⟩
  · right
    exact ⟨W.mode ▸ hb, W.heldFresh (by rw [W.ty]; exact hyt E hE) hb hhf, (W.live hl).1⟩

/-- **The whole negative: no `edit false` storing a value that is not the
    frame's own in path and in what it holds (`¬ (FreshSrc ∧ HeldSrc)`, the
    premise `hbs` asks of a held-fresh borrow) leaves its borrow
    held-fresh**, of an element type that holds views: every typing. A value
    may fail only `HeldSrc`, an owner `Vec` of views moved in, say: the move
    then kills, which keeps the bit (`killE_heldFresh`). -/
theorem edit_false_unown_unheld' {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {s : Stmt}
    (ht : StmtT Q ξ Γ F s Δ) : ∀ {x op y}, s = .edit false x op → op.stored = some y →
      ¬ (FreshSrc Γ y ∧ HeldSrc Γ y) → (∀ Ey, Γ y = some Ey → Ey.ty ≠ .int) →
      ∀ {Ex t}, Γ x = some Ex → Ex.ty = .vec t → t.holdsView = true →
      ∀ {E}, Δ x = some E → E.ty ≠ .int → E.mode = .bor → E.heldFresh = false := by
  induction ht with
  | @sub _ _ G0 _ _ _ _ hw _ hΔ ih =>
    intro x op y hs hy hns hyt Ex t hx hty hv E hE hn hm
    obtain ⟨hnx, hwE⟩ := hw.1 x
    obtain ⟨Ex0, hx0⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hnx.mpr h] at hx; cases hx)
    have W := hwE Ex Ex0 hx hx0
    -- (`y` keeps its type through the weakening)
    have hyt0 : ∀ Ey : Entry, G0 y = some Ey → Ey.ty ≠ .int := fun Ey h0 => by
      obtain ⟨hny, hwy⟩ := hw.1 y
      obtain ⟨Ey1, h1⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hny.mp h] at h0; cases h0)
      rw [(hwy Ey1 Ey h1 h0).ty]; exact hyt Ey1 h1
    have ih' := @ih x op y hs hy
      (fun h => hns ⟨freshSrc_of_weaker hw h.1, heldSrc_of_weaker hw hyt h.2⟩) hyt0 Ex0 t hx0
      (by rw [W.ty]; exact hty) hv
    rcases hΔ with rfl | hΔ
    · exact ih' hE hn hm
    · obtain ⟨hnd, hwD⟩ := hΔ.1 x
      obtain ⟨E0, hE0⟩ := Option.ne_none_iff_exists'.mp (fun h => by rw [hnd.mp h] at hE; cases hE)
      have WD := hwD E0 E hE0 hE
      cases hb : E.heldFresh with
      | false => rfl
      | true =>
        have := WD.heldFresh hn hm hb
        rw [ih' hE0 (WD.ty ▸ hn) (WD.mode ▸ hm)] at this; cases this
  | editB hx' _ _ hty' hv' =>
    intro x op y hs _ _ _ Ex t hx hty hv
    cases hs; rw [hx] at hx'; cases hx'; rw [hty] at hty'; cases hty'; rw [hv] at hv'; cases hv'
  | editBV hx' _ _ _ _ _ _ harg hne hx1 _ _ _ _ _ _ hbs =>
    intro x op y hs hy hns _ Ex t hx _ _ E hE _ _
    cases hs; rw [hx] at hx'; cases hx'
    rw [A2.setE, upd_same] at hE; cases hE
    -- what is stored is not the frame's own, so the borrow was not held-fresh ...
    have hf := (hbs rfl).resolve_right (fun h => hns (h y hy))
    -- ... and storing it keeps the borrow's bit: a copy changes nothing, a move kills
    have hyx := hne y hy
    cases harg with
    | push hy0 _ _ hp | set _ hy0 _ _ hp =>
      simp [Edit.stored] at hy; subst hy
      cases hp with
      | move =>
        simp only [A2.setE, upd, Ne.symm hyx, ite_false, A2.kill, hx, Option.map_some] at hx1
        cases hx1; rw [killE_heldFresh]; exact hf
      | int => rw [hx] at hx1; cases hx1; exact hf
      | slice _ => rw [hx] at hx1; cases hx1; exact hf
    | trunc _ => simp [Edit.stored] at hy
  | _ => intro x op y hs; cases hs

theorem edit_false_unown_unheld {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {x y : Var} {op : Edit}
    {Ex E : Entry} {t : Ty} (ht : StmtT Q ξ Γ F (.edit false x op) Δ) (hy : op.stored = some y)
    (hns : ¬ (FreshSrc Γ y ∧ HeldSrc Γ y)) (hyt : ∀ Ey, Γ y = some Ey → Ey.ty ≠ .int)
    (hx : Γ x = some Ex) (hty : Ex.ty = .vec t) (hv : t.holdsView = true)
    (hE : Δ x = some E) (hn : E.ty ≠ .int) (hm : E.mode = .bor) : E.heldFresh = false :=
  edit_false_unown_unheld' ht rfl hy hns hyt hx hty hv hE hn hm

/-- **A store of a borrowed parameter itself** (a slice the caller lent)
    never leaves its borrow held-fresh. -/
theorem param_store_unheld {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {x y : Var} {op : Edit}
    {Ex Ey E : Entry} {t : Ty} (ht : StmtT Q ξ Γ F (.edit false x op) Δ) (hy : op.stored = some y)
    (hEy : Γ y = some Ey) (hrb : Ey.mode = .rootb) (hx : Γ x = some Ex) (hty : Ex.ty = .vec t)
    (hv : t.holdsView = true) (hE : Δ x = some E) (hn : E.ty ≠ .int) (hm : E.mode = .bor) :
    E.heldFresh = false :=
  edit_false_unfresh_unheld ht hy (rootb_not_freshSrc hEy hrb) hx hty hv hE hn hm

/-- **... nor of a field read of one, or of any borrow that is not fresh**
    (`. d s` of #909's own example: a field read is never fresh, `projE`). -/
theorem stale_store_unheld {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {x y : Var} {op : Edit}
    {Ex Ey E : Entry} {t : Ty} (ht : StmtT Q ξ Γ F (.edit false x op) Δ) (hy : op.stored = some y)
    (hEy : Γ y = some Ey) (hb : Ey.mode = .bor) (hf : Ey.fresh = false) (hx : Γ x = some Ex)
    (hty : Ex.ty = .vec t) (hv : t.holdsView = true) (hE : Δ x = some E) (hn : E.ty ≠ .int)
    (hm : E.mode = .bor) : E.heldFresh = false :=
  edit_false_unfresh_unheld ht hy (stale_not_freshSrc hEy hb hf) hx hty hv hE hn hm

/-! ### The positive side: #909's own destructor -/

/-- The body: `loc` 3, the inner `Vec` 4, the element borrow `e` 5, the field
    read `. d s` 6 (the destructor's parameter `d` is 0). -/
def storeP : Stmt :=
  .letv 3 (.new vsl) (.letv 4 (.new sl) (.seq (.push 3 4)
    (.letv 5 (.at 3 (.lit 0)) (.letv 6 (.fst 0) (.edit false 5 (.push 6))))))

/-- The destructor's parameter: a borrowed struct that holds a view, so
    (AGORA-937, item 2) it holds its region by its handle, `π 0 = nvars = 7`. -/
def Ed : Entry := ⟨DTV, .rootb, true, [], [⟨7, .self⟩], false, false, false, false⟩
/-- `. d s`, a view the caller lent: neither fresh nor held-fresh. -/
def Ef : Entry := ⟨sl, .bor, true, [⟨0, .view⟩, ⟨7, .self⟩], [⟨7, .self⟩], false, false, false, false⟩

/-- `( vec_push [[i] e . d s )` through the fresh element borrow `e`, which is
    not held-fresh: an `edit false`, storing a view of the parameter. -/
theorem edit_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ) (h3 : Γ 3 = some Eloc) (h5 : Γ 5 = some Ee)
    (h6 : Γ 6 = some Ef) :
    StmtT Q .none Γ [] (.edit false 5 (.push 6))
      (A2.setE (A2.holdThru (memDeps (derive 6 Ef .self ++ Ef.held)) [⟨3, .inner⟩]
        (A2.killThruV (.push 6) vsl [⟨3, .inner⟩] Γ)) 5
        { Ee with held := Ee.held ++ memDeps (derive 6 Ef .self ++ Ef.held) }) := by
  refine StmtT.editBV (b := false) (Ex := Ee) (Ex1 := Ee) (t := sl) h5 rfl rfl rfl rfl (Or.inl rfl) (by simp)
    (EditArg.push (Ey := Ef) h6 rfl rfl (PushArg.slice (Or.inl rfl)))
    (fun y hy => by simp [Edit.stored] at hy; subst hy; decide) h5 rfl
    (by simp [Ee, memDeps, Kind.isName]) ?_ ?_ (fun h => by simp [Edit.drops] at h) (fun _ => rfl) ?_
  · -- the change's effect through `e`, whose path is `loc`'s elements: `loc` is a live owner
    intro d hd
    simp only [Ee, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
      List.mem_singleton] at hd
    subst hd
    refine ⟨by simp, fun y hy => ?_, _, h3, rfl, Or.inl rfl, hc.dtor _ _ _, by simp,
      by simp [Edit.effAt, Edit.inEff, Eloc, Entry.rvec, Ty.isVec]; exact HeldOK.of_kills _ rfl rfl⟩
    simp [Edit.stored] at hy; subst hy; decide
  · -- ... ends no view a destructor reads, `loc` is no `letd`'s, and what is stored depends on `d`
    intro d hd
    simp only [Ee, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos, List.filter_nil,
      List.mem_singleton] at hd
    subst hd
    exact ⟨hc.dtor _ _ _, by simp [argE, h3, Eloc], by simp [roots, memDeps, derive, Ef, Mode.isRoot, comp,
      Kind.isName]⟩
  · -- Agora #909's own example: the element borrow is not held-fresh, so it may store
    -- a view of the parameter
    intro _
    exact Or.inl rfl

theorem storeP_typed {Q : Prog} {Γ : Ctx} (hc : Calm Γ)
    (h3 : Γ 3 = none) (h4 : Γ 4 = none) (h5 : Γ 5 = none) (h6 : Γ 6 = none)
    (h0 : Γ 0 = some Ed) (h1 : Γ 1 = some R0) :
    ∃ Δ, StmtT Q .none Γ [] storeP Δ ∧ Calm Δ ∧ Δ 1 = some R0 := by
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
  have hG50 : G5 0 = some Ed := by
    simp [G5, G4', G4, G3, A2.setE, upd, A2.kill, killE, hits, h0, Ed, Entry.vdeps, Mode.ownSlot]
  -- `( vec_at loc 0 )`, fresh: `loc` is an owner
  have hat : RhsT G5 [] (.at 3 (.lit 0)) Ee G5 := by
    have := RhsT.at (Γ := G5) (F := []) (E := Eloc) (t := vsl) (i := .lit 0) (f := true) hG53 rfl rfl ExprT.lit
      (fun _ => ⟨⟨Eloc, hG53, Or.inl (Or.inl rfl)⟩, fun s h => by cases h⟩)
    simpa [elemE, Eloc, Ee, vsl, vvsl, derive, Mode.isRoot, rootKind] using this
  let G6 := A2.setE G5 5 Ee
  have hG6 : Calm G6 := hG5.setE (by simp [Ee])
  have hG60 : G6 0 = some Ed := by simp [G6, A2.setE, hG50]
  -- `. d s`: a field read of the borrowed parameter, lent: it views what the caller lent
  have hfst : RhsT G6 [] (.fst 0) Ef G6 := by
    have := RhsT.fst (Γ := G6) (F := []) (E := Ed) (a := sl) (b := .int) hG60 rfl rfl
    simpa [projE, projDeps, projHeld_bor, Ed, Ef, sl, Mode.ownSlot] using this
  let G7 := A2.setE G6 6 Ef
  have hG7 : Calm G7 := hG6.setE (by simp [Ef])
  have hG73 : G7 3 = some Eloc := by simp [G7, G6, A2.setE, upd, hG53]
  have hed := edit_typed (Q := Q) hG7 hG73 (by simp [G7, G6, A2.setE, upd]) (by simp [G7, A2.setE])
  let Δe := A2.setE (A2.holdThru (memDeps (derive 6 Ef .self ++ Ef.held)) [⟨3, .inner⟩]
        (A2.killThruV (.push 6) vsl [⟨3, .inner⟩] G7)) 5
        { Ee with held := Ee.held ++ memDeps (derive 6 Ef .self ++ Ef.held) }
  have hΔe : Calm Δe := by
    refine (calm_holdThru (calm_killThruV hG7 _ _ _) _ _ ?_).setE (by simp [Ee])
    intro r hr E hE
    simp [roots, memDeps, Kind.isName] at hr; subst hr
    obtain ⟨E0, h0', hm⟩ := killHv_mode hE
    rw [hG73] at h0'; cases h0'; rw [hm]; simp [Eloc]
  have hΔe1 : Δe 1 = some R0 := by
    have hG71 : G7 1 = some R0 := by
      simp [G7, G6, G5, G4', G4, G3, A2.setE, upd, A2.kill, h1, killE_int hR0 hR0r]
    have hk : A2.killThruV (.push 6) vsl [⟨3, .inner⟩] G7 1 = some R0 := by
      simp only [A2.killThruV, thruKills, memDeps, Kind.isName, Bool.not_false, List.filter_cons_of_pos,
        List.filter_nil, List.map_cons, List.map_nil, A2.killHv, A2.kill, hG71, Option.map_some,
        killE_int hR0 hR0r]
    simp [Δe, A2.setE, A2.holdThru, A2.holdOn, hk, roots, memDeps, Kind.isName]
  have hl6 := StmtT.letv (P := Q) (ξ := .none) (x := 6) (Γ := G6) (Γ1 := G6) (F := []) (E := Ef)
    (s := .edit false 5 (.push 6)) rfl (by simp [G6, G5, G4', G4, G3, A2.setE, upd, A2.kill, h6]) (by simp)
    hfst hed.ofNone (hΔe.endOK _) (fun h => by simp [Ef] at h)
  have hl5 := StmtT.letv (P := Q) (ξ := .none) (x := 5) (Γ := G5) (Γ1 := G5) (F := []) (E := Ee)
    rfl (by simp [G5, G4', G4, G3, A2.setE, upd, A2.kill, h5]) (by simp) hat hl6.ofNone
    ((hΔe.exitScope 6).endOK _) (fun h => by simp [Ee] at h)
  have hs := StmtT.seq (P := Q) (ξ := .none) rfl hpush hl5
  have hl4 := StmtT.letv (P := Q) (ξ := .none) (x := 4) (Γ := G3) (Γ1 := G3) (F := []) (E := Ein)
    rfl (by simp [G3, A2.setE, h4]) (by simp) (RhsT.new (t := sl) rfl) hs.ofNone
    (((hΔe.exitScope 6).exitScope 5).endOK _) (fun _ => rfl)
  have hl3 := StmtT.letv (P := Q) (ξ := .none) (x := 3) (Γ := Γ) (Γ1 := Γ) (F := []) (E := Eloc)
    rfl h3 (by simp) (RhsT.new (t := vsl) rfl) hl4.ofNone
    ((((hΔe.exitScope 6).exitScope 5).exitScope 4).endOK _) (fun _ => rfl)
  refine ⟨_, hl3, (((hΔe.exitScope 6).exitScope 5).exitScope 4).exitScope 3, ?_⟩
  exact r0_exit (by decide) (r0_exit (by decide) (r0_exit (by decide) (r0_exit (by decide) hΔe1)))

/-! ### The program: the destructor of a struct that holds a view -/

def dtor : Fn where
  params := [(.inp, DTV)]
  resTy := .int
  resOwn := false
  lends := []
  rholds := []
  outHolds := []
  body := .seq storeP (.assign 1 (.expr (.lit 0)))
  nvars := 7

def P : Prog := [dtor]

/-- **The destructor is not through-changing**: its one change through a
    borrow, storing a view of its parameter, is an `edit false`. -/
theorem dtor_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [dtor, storeP, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [dtor, storeP, Stmt.calls] at hg

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
  exact storeP_typed (Q := P) calm_dtor (by simp [sigCtx, isRegionIdx, dtor]) (by simp [sigCtx, isRegionIdx, dtor])
    (by simp [sigCtx, isRegionIdx, dtor]) (by simp [sigCtx, isRegionIdx, dtor])
    (by simp [sigCtx, dtor, paramE, Ed, DTV, TV, Ty.hasFn, regionP, regioned, Ty.holdsView]) (by simp [sigCtx, dtor, R0, resMode])

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
  subst hfn; simp [dtor, storeP, Stmt.codesOK, Rhs.codeOK]

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
    destructor that stores a view its caller lent it through a (fresh) borrow
    of its own local. -/
theorem main_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-- ... and leaks nothing when it ends. -/
theorem main_no_leak {m' : Mem} (hr : Steps P (emptyMem 7) main (.ok m' .skip)) :
    ∀ i, m'.alloc i = false := by
  obtain ⟨Δ, ht⟩ := main_typed
  exact no_leak_end prog_ok prog_codes ht rfl (by simp [main, Stmt.codesOK, Rhs.codeOK]) (by decide) hr


end A2.ParamViewWitness
