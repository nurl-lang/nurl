import A2.DtorWitness

/-!
# A2-drop.3b: dropping a `Vec` of destructor values in place, as code (Agora #607)

`vec_free`, `vec_truncate` and `vec_clear` release elements with no code in
the calculus (`Step.free`, `Step.edit`), so their rules refuse a `Vec` whose
elements own a destructor value (`A2.Dtor.free_dtor_free`,
`edit_drops_dtor_free`).  For such a `Vec` they are code the calculus
already types, with every element's destructor running:

* `vec_free x` is `x` moved into a destructor binding that ends at once
  (`Stmt.vecFreeD`): the binding's frame drains it, in index order
  (`A2.Dtor.scopeD_end_drains`), and leaves the context `StmtT.free` leaves;
* `vec_clear x` is a loop moving element 0 out to a destructor binding
  (`Stmt.vecClearD`), in index order, as nurlc's;
* `vec_truncate x n` is a loop of `vec_pop`s into a destructor binding
  (`Stmt.vecTruncD`): the elements go last first, where nurlc's go in index
  order (the calculus has no `vec_remove x n`).  Each destructor runs once
  either way; the order of their effects differs.

A panic in an element's destructor leaves either loop with the elements not
yet dropped still in `x` (its binding's end drains them); nurlc cuts the
length before it drops (`CLAIM.md`).

Both loops are typed in a context with no live borrow of `x`'s elements,
which is what a truncation leaves, and leave it as it was.
-/

namespace A2.Dtor

/-- `vec_free x` of a `Vec` of destructor values: `x` moves to `y`, a
    destructor binding whose scope is empty; its frame's end drains it. -/
def _root_.A2.Stmt.vecFreeD (y : Var) (f : Nat) (x : Var) : Stmt := .letd y f (.var x) .skip

/-- `vec_truncate x n` (`c` is `n < vec_len x`) of
    a `Vec` of destructor values: while it is longer, its last element moves
    out to `y`, a destructor binding whose scope is empty. -/
def _root_.A2.Stmt.vecTruncD (y : Var) (f : Nat) (x : Var) (c : Expr) : Stmt :=
  .while c (.letd y f (.pop x) .skip)

/-- `vec_clear x` of a `Vec` of destructor values: while it has an element,
    element 0 moves out to `y`, a destructor binding whose scope is empty:
    nurlc's order. -/
def _root_.A2.Stmt.vecClearD (y : Var) (f : Nat) (x : Var) : Stmt :=
  .while (.lt (.lit 0) (.len x)) (.letd y f (.popFront x) .skip)

/-- `EndOK` reads an entry's type, mode, dependencies and whether it may run
    a destructor: a context whose entries are another's in these has it too. -/
theorem endOK_of_same {Γ Γ1 : Ctx} {y : Var}
    (h : ∀ v E1, Γ1 v = some E1 → ∃ E0, Γ v = some E0 ∧ E1.ty = E0.ty ∧ E1.mode = E0.mode ∧
      E1.vdeps = E0.vdeps ∧ (E1.dtor = true → E0.dtor = true) ∧ (E1.dbind = true → E0.dbind = true))
    (he : EndOK Γ y) : EndOK Γ1 y := by
  refine ⟨fun p E1 hp hm d hd hb => ?_, fun v E1 hv hdt hos => ?_, fun v E1 hv hdb hos hn d hd hnm => ?_⟩
  · obtain ⟨E0, h0, _, hmo, hvd, _, _⟩ := h p E1 hp
    exact he.1 p E0 h0 (hmo ▸ hm) d (hvd ▸ hd) hb
  · obtain ⟨E0, h0, hty, hmo, hvd, hd', _⟩ := h v E1 hv
    have := he.2.1 v E0 h0 (hd' hdt) (hmo ▸ hos)
    unfold hitsMem at this ⊢
    rw [hty, hmo, hvd]; exact this
  · obtain ⟨E0, h0, hty, hmo, hvd, _, hb'⟩ := h v E1 hv
    exact he.2.2 v E0 h0 (hb' hdb) (hmo ▸ hos) (by rw [← hty, ← hmo]; exact hn) d (hvd ▸ hd) hnm

/-- A fresh binding that runs no armed destructor and is no borrowed
    parameter may end where the context before it lets it. -/
theorem endOK_bind {Γ : Ctx} {y : Var} {E : Entry} (he : EndOK Γ y) (hy : Γ y = none)
    (hm : E.mode ≠ .rootb) (hd : E.dtor = false) (hb : E.dbind = false) : EndOK (setE Γ y E) y := by
  refine ⟨fun p E1 hp hm1 d hdd hbd => ?_, fun v E1 hv hdt hos => ?_, fun v E1 hv hdb hos hn d hdd hnm => ?_⟩
  · by_cases hpy : p = y
    · subst hpy; simp [setE] at hp; subst hp; exact absurd hm1 hm
    · rw [setE, upd_ne _ _ hpy] at hp; exact he.1 p E1 hp hm1 d hdd hbd
  · by_cases hvy : v = y
    · subst hvy; simp [setE] at hv; subst hv; rw [hd] at hdt; cases hdt
    · rw [setE, upd_ne _ _ hvy] at hv; exact he.2.1 v E1 hv hdt hos
  · by_cases hvy : v = y
    · subst hvy; simp [setE] at hv; subst hv; rw [hb] at hdb; cases hdb
    · rw [setE, upd_ne _ _ hvy] at hv; exact he.2.2 v E1 hv hdb hos hn d hdd hnm

/-- **`vec_free` of a `Vec` of destructor values is typed code.**  Where
    `StmtT.free` would free an owned `Vec` `x` (live, not lent, not pinned,
    viewed by no binding that may run a destructor) but for its elements
    being destructor values, `Stmt.vecFreeD` is typed, and leaves the context
    `free` leaves: `x` moved out, what viewed it ended.  (`y` is a fresh
    name, which nothing in `Γ` speaks of.) -/
theorem vecFreeD_typed {P : Prog} {Γ : Ctx} {F : List Var} {x y : Var} {f : Nat} {t : Ty} {E : Entry}
    (hw : CtxWF Γ) (hx : Γ x = some E) (hl : E.live = true) (hm : E.mode = .own)
    (hty : E.ty = .vec (.dtor f t)) (hxF : x ∉ F) (hnp : NoPin Γ x) (hds : DtorSafe Γ .replace false x)
    (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DtorOK P f (.dtor f t)) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y) :
    StmtT P Γ F (Stmt.vecFreeD y f x)
      (setE (kill .replace false x Γ) x { E with live := false, dtor := false }) := by
  have hxy : y ≠ x := fun h => by rw [h, hx] at hy; cases hy
  let Γ1 : Ctx := setE (kill .replace false x Γ) x { E with live := false, dtor := false }
  have hw1 : CtxWF Γ1 := hw.moveOut hx _ _
  have hy1 : Γ1 y = none := by simp [Γ1, setE, upd_ne _ _ hxy, A2.kill, hy]
  have he1 : EndOK Γ1 y := by
    refine endOK_of_same (fun v E1 hv1 => ?_) he
    by_cases hvx : v = x
    · subst hvx
      simp [Γ1, setE] at hv1; subst hv1
      exact ⟨E, hx, rfl, rfl, rfl, by simp, by simp⟩
    · simp only [Γ1, setE, upd_ne _ _ hvx, A2.kill] at hv1
      cases h0 : Γ v with
      | none => rw [h0] at hv1; cases hv1
      | some E0 =>
        rw [h0] at hv1; simp only [Option.map_some, Option.some.injEq] at hv1; subst hv1
        refine ⟨E0, rfl, ?_, ?_, ?_, ?_, ?_⟩ <;> (unfold killE; split <;> first | rfl | exact id | simp [Entry.vdeps])
  have hr : RhsT Γ F (.var x) ⟨E.ty, .own, true, [], E.held, false, false⟩ Γ1 :=
    RhsT.moveOwn hx hl hm hxF hnp hds
  have hτ : LetdTy f t E.ty (.vec (.dtor f t)) := Or.inr ⟨rfl, hty, hv⟩
  have hdv : (Ty.vec (.dtor f t)).dtorViews = false := by rw [hτ.scopeD.dtorViews, hτ.scopeD.holdsView, hv]
  have hlet := StmtT.letd (P := P) (Γ := Γ) (Γ1 := Γ1) (F := F) (x := y) (f := f) (r := .var x)
    (s := .skip) (E := ⟨E.ty, .own, true, [], E.held, false, false⟩) (t := t) (H := E.held)
    (τ := .vec (.dtor f t)) rfl hy hyF hr rfl hτ hst hfn hok (HeldUp.refl _ _) StmtT.skip
    (endOK_bind he1 hy1 (by simp [Entry.arm]) (by simp [Entry.arm, hdv]) (by simp [Entry.arm, hdv]))
  rw [exitScope_setE_fresh hw1 hy1] at hlet
  exact hlet

/-- **`vec_truncate` of a `Vec` of destructor values is typed code.**  Where the `Vec` `x` may drop elements (it is live, an owner or
    an `inout` parameter that may, not lent; no binding that may run a
    destructor views its elements), in a context with no live borrow of its
    elements (`kill .drop false x Γ = Γ`: what a truncation leaves),
    `Stmt.vecTruncD` is typed and leaves the context as it was. -/
theorem vecTruncD_typed {P : Prog} {Γ : Ctx} {F : List Var} {x y : Var} {f : Nat} {t : Ty} {E : Entry}
    {c : Expr} (hw : CtxWF Γ) (hx : Γ x = some E) (hl : E.live = true) (hcd : canDo E.mode .drop)
    (hty : E.ty = .vec (.dtor f t)) (hxF : x ∉ F) (hds : DtorSafe Γ .drop false x)
    (hfix : kill .drop false x Γ = Γ) (hc : ExprT Γ c)
    (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DtorOK P f (.dtor f t)) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y) :
    StmtT P Γ F (Stmt.vecTruncD y f x c) Γ := by
  have hr : RhsT Γ F (.pop x) (popE x E (.dtor f t)) (kill .drop (Ty.dtor f t).holdsView x Γ) :=
    RhsT.pop hx hl hty hcd hxF (by simpa [Ty.holdsView, hv] using hds)
  have hhv : (Ty.dtor f t).holdsView = false := by simpa [Ty.holdsView] using hv
  rw [hhv, hfix] at hr
  have hτ : LetdTy f t (popE x E (.dtor f t)).ty (.dtor f t) := Or.inl ⟨rfl, Or.inr rfl⟩
  have hdv : (Ty.dtor f t).dtorViews = false := by rw [hτ.scopeD.dtorViews, hτ.scopeD.holdsView, hv]
  have hlet := StmtT.letd (P := P) (Γ := Γ) (Γ1 := Γ) (F := F) (x := y) (f := f) (r := .pop x)
    (s := .skip) (E := popE x E (.dtor f t)) (t := t) (H := (popE x E (.dtor f t)).held)
    (τ := .dtor f t) rfl hy hyF hr rfl hτ hst hfn hok (HeldUp.refl _ _) StmtT.skip
    (endOK_bind he hy (by simp [Entry.arm, popE]) (by simp [Entry.arm, hdv]) (by simp [Entry.arm, hdv]))
  rw [exitScope_setE_fresh hw hy] at hlet
  exact StmtT.while rfl hc hlet

/-- **`vec_clear` of a `Vec` of destructor values is typed code**, its
    elements going in index order, as nurlc's: `vecTruncD_typed`'s premises,
    for `Stmt.vecClearD`. -/
theorem vecClearD_typed {P : Prog} {Γ : Ctx} {F : List Var} {x y : Var} {f : Nat} {t : Ty} {E : Entry}
    (hw : CtxWF Γ) (hx : Γ x = some E) (hl : E.live = true) (hcd : canDo E.mode .drop)
    (hty : E.ty = .vec (.dtor f t)) (hxF : x ∉ F) (hds : DtorSafe Γ .drop false x)
    (hfix : kill .drop false x Γ = Γ)
    (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DtorOK P f (.dtor f t)) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y) :
    StmtT P Γ F (Stmt.vecClearD y f x) Γ := by
  have hr : RhsT Γ F (.popFront x) (popE x E (.dtor f t)) (kill .drop (Ty.dtor f t).holdsView x Γ) :=
    RhsT.popFront hx hl hty hcd hxF (by simpa [Ty.holdsView, hv] using hds)
  have hhv : (Ty.dtor f t).holdsView = false := by simpa [Ty.holdsView] using hv
  rw [hhv, hfix] at hr
  have hτ : LetdTy f t (popE x E (.dtor f t)).ty (.dtor f t) := Or.inl ⟨rfl, Or.inr rfl⟩
  have hdv : (Ty.dtor f t).dtorViews = false := by rw [hτ.scopeD.dtorViews, hτ.scopeD.holdsView, hv]
  have hlet := StmtT.letd (P := P) (Γ := Γ) (Γ1 := Γ) (F := F) (x := y) (f := f) (r := .popFront x)
    (s := .skip) (E := popE x E (.dtor f t)) (t := t) (H := (popE x E (.dtor f t)).held)
    (τ := .dtor f t) rfl hy hyF hr rfl hτ hst hfn hok (HeldUp.refl _ _) StmtT.skip
    (endOK_bind he hy (by simp [Entry.arm, popE]) (by simp [Entry.arm, hdv]) (by simp [Entry.arm, hdv]))
  rw [exitScope_setE_fresh hw hy] at hlet
  exact StmtT.while rfl (ExprT.lt ExprT.lit (ExprT.len hx hl hty)) hlet


end A2.Dtor

namespace A2.DtorWitness
open A2.Dtor
open A2.DynCell (NoRootb noRootb_empty)

/-- No entry views anything. -/
def NoDeps (Γ : Ctx) : Prop := ∀ v E, Γ v = some E → E.vdeps = []

theorem NoDeps.setE {Γ : Ctx} (h : NoDeps Γ) {x : Var} {E : Entry} (hE : E.vdeps = []) :
    NoDeps (A2.setE Γ x E) := fun v E' hv => by
  by_cases hvx : v = x
  · subst hvx; simp [A2.setE] at hv; subst hv; exact hE
  · rw [A2.setE, upd_ne _ _ hvx] at hv; exact h v E' hv

theorem NoDeps.kill {Γ : Ctx} (h : NoDeps Γ) (e : Eff) (hv : Bool) (x : Var) :
    NoDeps (A2.kill e hv x Γ) := fun v E' hv' => by
  simp only [A2.kill] at hv'
  cases h0 : Γ v with
  | none => rw [h0] at hv'; cases hv'
  | some E0 =>
    rw [h0] at hv'; simp only [Option.map_some, Option.some.injEq] at hv'; subst hv'
    have := h v E0 h0
    unfold killE; split
    · simpa [Entry.vdeps] using this
    · exact this

theorem NoDeps.kill_eq {Γ : Ctx} (h : NoDeps Γ) (e : Eff) (hv : Bool) (x : Var) :
    A2.kill e hv x Γ = Γ := by
  funext v
  cases h0 : Γ v with
  | none => simp [A2.kill, h0]
  | some E =>
    simp only [A2.kill, h0, Option.map_some, Option.some.injEq]
    unfold killE
    have : hits e hv x E = false := by simp [hits, h v E h0]
    rw [this]; rfl

theorem wfAdd {Γ : Ctx} (h : CtxWF Γ) {x : Var} (hx : Γ x = none) {E : Entry} (hE : E.vdeps = [])
    (hb : E.dbind = false) (hd : E.dtor = false) : CtxWF (A2.setE Γ x E) :=
  h.add hx (fun _ _ r hr => by simp [hE, roots] at hr) (fun h' => by rw [hb] at h'; cases h')
    (fun h' => by rw [hd] at h'; cases h') (fun h' => by rw [hb] at h'; cases h')

/-! ### The witness: a `Vec` of destructor values truncated, cleared, freed

`main5`'s program, and then `vec_truncate v 0`, `vec_clear v`, `vec_free v`,
as code: the premises of `vecTruncD_typed`, `vecClearD_typed` and
`vecFreeD_typed` hold of a program.  (A witness of the typing: at run time
the truncation already empties the one-element `Vec`.) -/

def main6 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.seq (Stmt.vecTruncD 4 0 3 (.lt (.lit 0) (.len 3)))
        (.seq (Stmt.vecClearD 6 0 3) (Stmt.vecFreeD 5 0 3)))))))

theorem main6_typed : ∃ Δ, StmtT P (fun _ => none) [] main6 Δ := by
  let K1 : Ctx := A2.setE (fun _ => none) 0 intE
  let K2 : Ctx := A2.setE K1 1 intE
  have hK1 : NoRootb K1 := noRootb_empty.setE (by simp [intE])
  have hK2 : NoRootb K2 := hK1.setE (by simp [intE])
  let ED : Entry := Entry.arm { EP with ty := DT, held := [] }
  have hEDe : ED = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [ED, EP, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor, Ty.holdsView]
  let K3 : Ctx := A2.setE K2 2 ED
  have hK3 : NoRootb K3 := hK2.setE (by rw [hEDe]; simp)
  have hpair : RhsT K2 [] (.pair 0 1) EP K2 :=
    RhsT.pair (Ey := intE) (Ez := intE) (by simp [K2, K1, A2.setE, upd]) rfl PushArg.int
      (by simp [K2, K1, A2.setE]) rfl PushArg.int (by simp [intE, Mode.ownSlot]) rfl rfl
  let EN : Entry := ⟨.vec DT, .own, true, [], [], false, false⟩
  have hnew : RhsT K3 [] (.new DT) EN K3 := RhsT.new (by decide)
  let EV : Entry := Entry.arm { EN with ty := .vec DT, held := [] }
  have hEVe : EV = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV, EN, Entry.arm, DT, T, Ty.dtorViews, Ty.hasDtor]
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
  -- the context after the push: every entry holds nothing
  let EV6 : Entry := { EV with held := EV.held ++ ownHeld true DT ED.held }
  let K6 : Ctx := A2.setE (kill .realloc DT.holdsView 3 K5) 3 EV6
  have hK6 : NoRootb K6 := (hK5.kill _ _ _).setE (by simp [EV6, hEVe])
  have hwE : CtxWF (fun _ => none) :=
    ⟨fun _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h)⟩
  have hw4 : CtxWF K4 :=
    wfAdd (wfAdd (wfAdd (wfAdd hwE rfl (by simp [intE, Entry.vdeps, Mode.ownSlot]) rfl rfl)
      (by simp [A2.setE, upd]) (by simp [intE, Entry.vdeps, Mode.ownSlot]) rfl rfl)
      (by simp [A2.setE, upd]) (by rw [hEDe]; rfl) (by rw [hEDe]) (by rw [hEDe]))
      (by simp [A2.setE, upd]) (by rw [hEVe]; rfl) (by rw [hEVe]) (by rw [hEVe])
  have hw6 : CtxWF K6 := StmtT.wf prog_ok hpush hw4
  have h63 : K6 3 = some EV6 := by simp [K6, A2.setE]
  have hEV6 : EV6 = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV6, hEVe, ownHeld, DT, T, Ty.holdsView]
  have hnd0 : NoDeps (fun _ => none) := fun _ _ h => by cases h
  have hnd : NoDeps K6 :=
    (((((((hnd0.setE (by simp [intE, Entry.vdeps, Mode.ownSlot])).setE
      (by simp [intE, Entry.vdeps, Mode.ownSlot])).setE (by rw [hEDe]; rfl)).setE
      (by rw [hEVe]; rfl)).kill _ _ _).setE (by rw [hEDe]; rfl)).kill _ _ _).setE
      (by rw [hEV6]; rfl)
  have hfix : kill .drop false 3 K6 = K6 := hnd.kill_eq _ _ _
  have htr := vecTruncD_typed (P := P) (F := []) (y := 4) (f := 0) (t := T) (c := .lt (.lit 0) (.len 3))
    hw6 h63 (by rw [hEV6]) (Or.inl (by rw [hEV6])) (by rw [hEV6]; rfl) (by simp)
    (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _) hfix
    (ExprT.lt ExprT.lit (ExprT.len h63 (by rw [hEV6]) (by rw [hEV6])))
    rfl rfl rfl dtor_ok (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) (hK6.endOK _)
  have hcl := vecClearD_typed (P := P) (F := []) (y := 6) (f := 0) (t := T)
    hw6 h63 (by rw [hEV6]) (Or.inl (by rw [hEV6])) (by rw [hEV6]; rfl) (by simp)
    (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _) hfix
    rfl rfl rfl dtor_ok (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) (hK6.endOK _)
  have hfr := vecFreeD_typed (P := P) (F := []) (y := 5) (f := 0) (t := T)
    hw6 h63 (by rw [hEV6]) (by rw [hEV6]) (by rw [hEV6]; rfl) (by simp) (hK6.noPin _)
    (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
    rfl rfl rfl dtor_ok (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) (hK6.endOK _)
  have hK7 : NoRootb (A2.setE (kill .replace false 3 K6) 3 { EV6 with live := false, dtor := false }) :=
    (hK6.kill _ _ _).setE (by rw [hEV6]; simp)
  have hbody := StmtT.seq (P := P) rfl hpush (StmtT.seq rfl htr (StmtT.seq rfl hcl hfr))
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨rfl, rfl, rfl⟩) rfl rfl dtor_ok (HeldUp.refl _ _) hbody (hK7.endOK _)
    (by simp [Stmt.assigns, Stmt.vecTruncD, Stmt.vecClearD, Stmt.vecFreeD])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl dtor_ok (HeldUp.refl _ _) hdv
    ((hK7.exitScope 3).endOK _) (by simp [Stmt.assigns, Stmt.vecTruncD, Stmt.vecClearD, Stmt.vecFreeD])
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK7.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((hK7.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program that truncates, clears and frees a `Vec` of destructor values, as
    code, is memory safe. -/
theorem main6_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 7) main6 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main6_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [main6, Stmt.vecTruncD, Stmt.vecClearD, Stmt.vecFreeD, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

end A2.DtorWitness
