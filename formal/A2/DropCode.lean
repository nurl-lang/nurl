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
* `vec_truncate x n` is a loop moving element `n` out to a destructor
  binding while `x` is longer (`Stmt.vecTruncD`), in index order, as nurlc's;
* `vec_set x i z` is element `i` moved out to a destructor binding that ends
  at once, then `z`'s value inserted at `i` (`Stmt.vecSetD`): the old
  element's destructor runs before the new one is stored, as nurlc's
  `vec_set` drops it.  Out of range, `vec_remove` panics where nurlc's
  `vec_set` answers `F`; `z` is dropped, its destructor running, either way.
* `withElem v i x s` (an element handed to a callee that changes it) is
  element `i` moved out to a destructor binding `x` for `s`, then put back
  at `i` (`Stmt.withElemD`): a panic in `s` runs the element's destructor
  in `x`'s frame, where nurlc's element stays in the `Vec`, dropped with it.

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

/-- `vec_truncate x n` of a `Vec` of destructor values: while it is longer
    than `n`, element `n` moves out to `y`, a destructor binding whose scope
    is empty: nurlc's order. -/
def _root_.A2.Stmt.vecTruncD (y : Var) (f : Nat) (x : Var) (n : Expr) : Stmt :=
  .while (.lt n (.len x)) (.letd y f (.remove x n) .skip)

/-- `vec_set x i z` over a `Vec` of destructor values: element `i` moves out
    to `y`, a destructor binding whose scope is empty, so its destructor
    runs; then `z`'s value goes in at `i`. -/
def _root_.A2.Stmt.vecSetD (y : Var) (f : Nat) (x : Var) (i : Expr) (z : Var) : Stmt :=
  .seq (.letd y f (.remove x i) .skip) (.insert x i z)

/-- `vec_clear x` of a `Vec` of destructor values: while it has an element,
    element 0 moves out to `y`, a destructor binding whose scope is empty:
    nurlc's order. -/
def _root_.A2.Stmt.vecClearD (y : Var) (f : Nat) (x : Var) : Stmt :=
  .while (.lt (.lit 0) (.len x)) (.letd y f (.remove x (.lit 0)) .skip)

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
    (hok : DropFnOK P f t) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y) :
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
  have hτ : LetdTy f t E.ty (.vec (.dtor f t)) := Or.inr ⟨0, rfl, hty⟩
  have hdv : (Ty.vec (.dtor f t)).dtorViews = false := by rw [hτ.scopeD.dtorViews, hτ.scopeD.holdsView, hv]
  have hlet := StmtT.letd (P := P) (Γ := Γ) (Γ1 := Γ1) (F := F) (x := y) (f := f) (r := .var x)
    (s := .skip) (E := ⟨E.ty, .own, true, [], E.held, false, false⟩) (t := t) (H := E.held)
    (τ := .vec (.dtor f t)) rfl hy hyF hr rfl hτ hst hfn (letd_fn hok) (HeldUp.refl _ _) StmtT.skip
    (endOK_bind he1 hy1 (by simp [Entry.arm]) (by simp [Entry.arm, hdv]) (by simp [Entry.arm, hdv]))
  rw [exitScope_setE_fresh hw1 hy1] at hlet
  exact hlet

/-- Element `i` of a `Vec` of destructor values moved out to a destructor
    binding whose scope is empty is typed, and leaves the context as it was
    (`vecTruncD_typed`'s premises). -/
theorem removeD_typed {P : Prog} {Γ : Ctx} {F : List Var} {x y : Var} {f : Nat} {t : Ty} {E : Entry}
    {i : Expr} (hw : CtxWF Γ) (hx : Γ x = some E) (hl : E.live = true) (hcd : canDo E.mode .drop)
    (hty : E.ty = .vec (.dtor f t)) (hxF : x ∉ F) (hds : DtorSafe Γ .drop false x)
    (hfix : kill .drop false x Γ = Γ) (hi : ExprT Γ i)
    (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DropFnOK P f t) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y) :
    StmtT P Γ F (.letd y f (.remove x i) .skip) Γ := by
  have hr : RhsT Γ F (.remove x i) (popE x E (.dtor f t)) (kill .drop (Ty.dtor f t).holdsView x Γ) :=
    RhsT.remove hx hl hty hcd hxF (by simpa [Ty.holdsView, hv] using hds) hi
  have hhv : (Ty.dtor f t).holdsView = false := by simpa [Ty.holdsView] using hv
  rw [hhv, hfix] at hr
  have hτ : LetdTy f t (popE x E (.dtor f t)).ty (.dtor f t) := Or.inl ⟨rfl, Or.inr ⟨f, rfl⟩⟩
  have hdv : (Ty.dtor f t).dtorViews = false := by rw [hτ.scopeD.dtorViews, hτ.scopeD.holdsView, hv]
  have hlet := StmtT.letd (P := P) (Γ := Γ) (Γ1 := Γ) (F := F) (x := y) (f := f) (r := .remove x i)
    (s := .skip) (E := popE x E (.dtor f t)) (t := t) (H := (popE x E (.dtor f t)).held)
    (τ := .dtor f t) rfl hy hyF hr rfl hτ hst hfn (letd_fn hok) (HeldUp.refl _ _) StmtT.skip
    (endOK_bind he hy (by simp [Entry.arm, popE]) (by simp [Entry.arm, hdv]) (by simp [Entry.arm, hdv]))
  rw [exitScope_setE_fresh hw hy] at hlet
  exact hlet

/-- **`vec_truncate` of a `Vec` of destructor values is typed code**, its
    elements going in index order, as nurlc's.  Where the `Vec` `x` may drop elements (it is live, an owner or
    an `inout` parameter that may, not lent; no binding that may run a
    destructor views its elements), in a context with no live borrow of its
    elements (`kill .drop false x Γ = Γ`: what a truncation leaves),
    `Stmt.vecTruncD` is typed and leaves the context as it was. -/
theorem vecTruncD_typed {P : Prog} {Γ : Ctx} {F : List Var} {x y : Var} {f : Nat} {t : Ty} {E : Entry}
    {n : Expr} (hw : CtxWF Γ) (hx : Γ x = some E) (hl : E.live = true) (hcd : canDo E.mode .drop)
    (hty : E.ty = .vec (.dtor f t)) (hxF : x ∉ F) (hds : DtorSafe Γ .drop false x)
    (hfix : kill .drop false x Γ = Γ) (hn : ExprT Γ n)
    (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DropFnOK P f t) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y) :
    StmtT P Γ F (Stmt.vecTruncD y f x n) Γ :=
  StmtT.while rfl (ExprT.lt hn (ExprT.len hx hl hty))
    (removeD_typed hw hx hl hcd hty hxF hds hfix hn hv hst hfn hok hy hyF he)

/-- **`vec_clear` of a `Vec` of destructor values is typed code**, its
    elements going in index order, as nurlc's: `vecTruncD_typed`'s premises,
    for `Stmt.vecClearD`. -/
theorem vecClearD_typed {P : Prog} {Γ : Ctx} {F : List Var} {x y : Var} {f : Nat} {t : Ty} {E : Entry}
    (hw : CtxWF Γ) (hx : Γ x = some E) (hl : E.live = true) (hcd : canDo E.mode .drop)
    (hty : E.ty = .vec (.dtor f t)) (hxF : x ∉ F) (hds : DtorSafe Γ .drop false x)
    (hfix : kill .drop false x Γ = Γ)
    (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DropFnOK P f t) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y) :
    StmtT P Γ F (Stmt.vecClearD y f x) Γ :=
  vecTruncD_typed hw hx hl hcd hty hxF hds hfix ExprT.lit hv hst hfn hok hy hyF he

/-- **`vec_set` over an element of a `Vec` of destructor values is typed
    code.**  Where `vec_push x z` is typed (`hpush`), and the `Vec` may drop
    an element (`vecTruncD_typed`'s premises), `Stmt.vecSetD` is typed and
    leaves the context the push leaves: the old element moves out to a
    destructor binding that ends at once, its destructor running, and `z`'s
    value goes in at `i`, typed as the push (`StmtT.insert`). -/
theorem vecSetD_typed {P : Prog} {Γ Δ : Ctx} {F : List Var} {x y z : Var} {f : Nat} {t : Ty}
    {E : Entry} {i : Expr} (hw : CtxWF Γ) (hx : Γ x = some E) (hl : E.live = true)
    (hcd : canDo E.mode .drop)
    (hty : E.ty = .vec (.dtor f t)) (hxF : x ∉ F) (hds : DtorSafe Γ .drop false x)
    (hfix : kill .drop false x Γ = Γ) (hi : ExprT Γ i)
    (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DropFnOK P f t) (hy : Γ y = none) (hyF : y ∉ F) (he : EndOK Γ y)
    (hpush : StmtT P Γ F (.push x z) Δ) :
    StmtT P Γ F (Stmt.vecSetD y f x i z) Δ :=
  StmtT.seq rfl (removeD_typed hw hx hl hcd hty hxF hds hfix hi hv hst hfn hok hy hyF he)
    (StmtT.insert hi hxF hpush)

/-- `withElem v i x s` over a `Vec` of destructor values (an element handed
    to a callee that changes it): element `i` moves out to `x`, a destructor
    binding, for `s`; then `x`'s value goes back in at `i`, and `x`'s frame
    ends with nothing to drop.  A panic in `s` reaches `x`'s frame, which runs
    the element's destructor (`Step.scopeDP`). -/
def _root_.A2.Stmt.withElemD (v : Var) (i : Expr) (x : Var) (f : Nat) (s : Stmt) : Stmt :=
  .letd x f (.remove v i) (.seq s (.insert v i x))

/-- **An element of a `Vec` of destructor values handed over is typed
    code.**  Where the `Vec` `v` may drop an element (`vecTruncD_typed`'s
    premises), the body `s` is typed with `x` bound to the element as a
    destructor binding, and `vec_push v x` is typed after it, `Stmt.withElemD`
    is typed and leaves the push's context with `x`'s scope ended.  The
    runtime passes a pointer to the element in place, and three premises keep
    the model faithful to it, as `StmtT.withElem`'s do: the body names
    neither `v` nor what the index reads (`v ∉ s.vars`, `hiv`), so the
    element goes back where it was, and no borrowed parameter changes `v` by
    name (`NoPin`).  The body gives `x` no other value (`x ∉ s.assigns`: the
    old one's drop would run no destructor). -/
theorem withElemD_typed {P : Prog} {Γ Δ1 Δ : Ctx} {F : List Var} {v x : Var} {f : Nat} {t : Ty}
    {E : Entry} {i : Expr} {s : Stmt} {H : List Dep}
    (hx : Γ v = some E) (hl : E.live = true) (hcd : canDo E.mode .drop)
    (hty : E.ty = .vec (.dtor f t)) (hvF : v ∉ F) (hds : DtorSafe Γ .drop false v)
    (hi : ExprT Γ i) (hv : t.holdsView = false) (hst : t.isStruct = true) (hfn : t.hasFn = false)
    (hok : DropFnOK P f t) (hxn : Γ x = none) (hxF : x ∉ F)
    (hss : s.src = true) (hH : HeldUp (kill .drop false v Γ) (popE v E (.dtor f t)) H)
    (hs : StmtT P (setE (kill .drop false v Γ) x
      (Entry.arm { popE v E (.dtor f t) with ty := .dtor f t, held := H })) F s Δ1)
    (hi1 : ExprT Δ1 i) (hpush : StmtT P Δ1 F (.push v x) Δ) (he : EndOK Δ x)
    (hna : x ∉ s.assigns)
    -- faithful to the in-place pass (unused by the typing)
    (_hvs : v ∉ s.vars) (_hiv : ∀ w ∈ i.vars, w ∉ s.vars) (_hnp : NoPin Γ v) :
    StmtT P Γ F (Stmt.withElemD v i x f s) (exitScope x Δ) := by
  have hr : RhsT Γ F (.remove v i) (popE v E (.dtor f t)) (kill .drop (Ty.dtor f t).holdsView v Γ) :=
    RhsT.remove hx hl hty hcd hvF (by simpa [Ty.holdsView, hv] using hds) hi
  have hhv : (Ty.dtor f t).holdsView = false := by simpa [Ty.holdsView] using hv
  rw [hhv] at hr
  have hτ : LetdTy f t (popE v E (.dtor f t)).ty (.dtor f t) := Or.inl ⟨rfl, Or.inr ⟨f, rfl⟩⟩
  exact StmtT.letd (P := P) (x := x) (f := f) (r := .remove v i) (s := .seq s (.insert v i x))
    (t := t) (H := H) (τ := .dtor f t) (by simp [Stmt.src, hss]) hxn hxF hr rfl hτ hst hfn
    (letd_fn hok) hH (StmtT.seq rfl hs (StmtT.insert hi1 hvF hpush)) he
    (by simp [Stmt.assigns, hna])

end A2.Dtor

namespace A2.DtorWitness
open A2.Dtor
open A2.DynCell (NoRootb noRootb_empty)

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
      (.seq (.push 3 2) (.seq (Stmt.vecTruncD 4 0 3 (.lit 0))
        (.seq (Stmt.vecClearD 6 0 3) (Stmt.vecFreeD 5 0 3)))))))

theorem main6_typed : ∃ Δ, StmtT P (fun _ => none) [] main6 Δ := by
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
  have htr := vecTruncD_typed (P := P) (F := []) (y := 4) (f := 0) (t := T) (n := .lit 0)
    hw6 h63 (by rw [hEV6]) (Or.inl (by rw [hEV6])) (by rw [hEV6]; rfl) (by simp)
    (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _) hfix ExprT.lit
    rfl rfl rfl drop_ok (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) (hK6.endOK _)
  have hcl := vecClearD_typed (P := P) (F := []) (y := 6) (f := 0) (t := T)
    hw6 h63 (by rw [hEV6]) (Or.inl (by rw [hEV6])) (by rw [hEV6]; rfl) (by simp)
    (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _) hfix
    rfl rfl rfl drop_ok (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) (hK6.endOK _)
  have hfr := vecFreeD_typed (P := P) (F := []) (y := 5) (f := 0) (t := T)
    hw6 h63 (by rw [hEV6]) (by rw [hEV6]) (by rw [hEV6]; rfl) (by simp) (hK6.noPin _)
    (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _)
    rfl rfl rfl drop_ok (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) (hK6.endOK _)
  have hK7 : NoRootb (A2.setE (kill .replace false 3 K6) 3 { EV6 with live := false, dtor := false }) :=
    (hK6.kill _ _ _).setE (by rw [hEV6]; simp)
  have hbody := StmtT.seq (P := P) rfl hpush (StmtT.seq rfl htr (StmtT.seq rfl hcl hfr))
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hbody (hK7.endOK _)
    (by simp [Stmt.assigns, Stmt.vecTruncD, Stmt.vecClearD, Stmt.vecFreeD])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv
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

/-! ### The witness: an element of a `Vec` of destructor values set

`main5`'s program, and then a second destructor value `w` and
`vec_set v 0 w`, as code: the premises of `vecSetD_typed` hold of a program.
The old element moves out to a destructor binding that ends at once, its
destructor running, and `w` goes in at index 0. -/

def mainSet : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letd 4 0 (.pair 0 1) (Stmt.vecSetD 5 0 3 (.lit 0) 4))))))

theorem mainSet_typed : ∃ Δ, StmtT P (fun _ => none) [] mainSet Δ := by
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
  have hEV6 : EV6 = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV6, hEVe, ownHeld, DT, T, Ty.holdsView]
  -- the second destructor value, `w` (binding 4)
  have h60 : K6 0 = some intE := by
    simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  have h61 : K6 1 = some intE := by
    simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  have hpair6 : RhsT K6 [] (.pair 0 1) EP K6 :=
    RhsT.pair (Ey := intE) (Ez := intE) h60 rfl PushArg.int h61 rfl PushArg.int
      (by simp [intE, Mode.ownSlot])
  have h64 : K6 4 = none := by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]
  let K7 : Ctx := A2.setE K6 4 ED
  have hK7 : NoRootb K7 := hK6.setE (by rw [hEDe]; simp)
  have hw7 : CtxWF K7 := wfAdd hw6 h64 (by rw [hEDe]; rfl) (by rw [hEDe]) (by rw [hEDe])
  have h73 : K7 3 = some EV6 := by simp [K7, K6, A2.setE, upd]
  have hnd0 : NoDeps (fun _ => none) := fun _ _ h => by cases h
  have hnd : NoDeps K7 :=
    ((((((((hnd0.setE (by simp [intE, Entry.vdeps, Mode.ownSlot])).setE
      (by simp [intE, Entry.vdeps, Mode.ownSlot])).setE (by rw [hEDe]; rfl)).setE
      (by rw [hEVe]; rfl)).kill _ _ _).setE (by rw [hEDe]; rfl)).kill _ _ _).setE
      (by rw [hEV6]; rfl)).setE (by rw [hEDe]; rfl)
  have hfix : kill .drop false 3 K7 = K7 := hnd.kill_eq _ _ _
  -- `vec_push v w`, which `vec_set`'s give-back is typed as
  let K8 : Ctx := A2.setE (kill .replace false 4 K7) 4 { ED with live := false, dtor := false }
  have hK8 : NoRootb K8 := (hK7.kill _ _ _).setE (by rw [hEDe]; simp)
  have hmove8 : PushArg K7 [] 4 ED DT ED.held K8 :=
    PushArg.move (Γ := K7) (F := []) (y := 4) (E := ED) (t := DT) rfl (by rw [hEDe])
      (by simp) (hK7.noPin _) (DtorSafe.of_none (fun v E h => (hK7 v E h).2.1) _ _ _)
  have hK83 : K8 3 = some EV6 := by
    simp [K8, K7, K6, A2.setE, upd, A2.kill, killE, hits, hEV6, Entry.vdeps, Mode.ownSlot]
  have hpush8 := StmtT.push (P := P) (Γ := K7) (Γ1 := K8) (F := []) (x := 3) (y := 4) (Ex := EV6)
    (Ey := ED) (Ex1 := EV6) (t := DT) (D := ED.held) h73 (by rw [hEV6]) (by rw [hEV6])
    (Or.inl (by rw [hEV6])) (by simp) (by simp [K7, A2.setE]) (by rw [hEDe]) (by rw [hEDe])
    (by decide) hmove8 (by rw [hEDe]; simp [roots]) hK83 (by rw [hEV6])
    (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _) (by rw [hEV6]; simp)
  have hset := vecSetD_typed (P := P) (F := []) (y := 5) (f := 0) (t := T) (i := .lit 0)
    hw7 h73 (by rw [hEV6]) (Or.inl (by rw [hEV6])) (by rw [hEV6]; rfl) (by simp)
    (DtorSafe.of_none (fun v E h => (hK7 v E h).2.1) _ _ _) hfix ExprT.lit
    rfl rfl rfl drop_ok (by simp [K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp)
    (hK7.endOK _) hpush8
  let EV9 : Entry := { EV6 with held := EV6.held ++ ownHeld true DT ED.held }
  have hK9 : NoRootb (A2.setE (kill .realloc DT.holdsView 3 K8) 3 EV9) :=
    (hK8.kill _ _ _).setE (by simp [EV9, hEV6])
  have hw := StmtT.letd (P := P) (Γ := K6) (Γ1 := K6) (F := []) (x := 4) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl h64
    (by simp) hpair6 rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hset
    (hK9.endOK _) (by simp [Stmt.assigns, Stmt.vecSetD])
  have hK10 := hK9.exitScope 4
  have hbody := StmtT.seq (P := P) rfl hpush hw
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hbody
    (hK10.endOK _) (by simp [Stmt.assigns, Stmt.vecSetD])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv
    ((hK10.exitScope 3).endOK _) (by simp [Stmt.assigns, Stmt.vecSetD])
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK10.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((hK10.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program that sets an element of a `Vec` of destructor values, as
    code, is memory safe. -/
theorem mainSet_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) mainSet (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := mainSet_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [mainSet, Stmt.vecSetD, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### The witness: an element of a `Vec` of destructor values handed over

`main5`'s program, and then `withElem v 0 x skip` as code: the premises of
`withElemD_typed` hold of a program.  The element moves out to `x`, a
destructor binding, and back in; `x`'s frame ends with nothing to drop. -/

def mainElem : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (Stmt.withElemD 3 (.lit 0) 4 0 .skip)))))

theorem mainElem_typed : ∃ Δ, StmtT P (fun _ => none) [] mainElem Δ := by
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
  have hEV6 : EV6 = ⟨.vec DT, .own, true, [], [], false, false⟩ := by
    simp [EV6, hEVe, ownHeld, DT, T, Ty.holdsView]
  have h64 : K6 4 = none := by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]
  have hnd0 : NoDeps (fun _ => none) := fun _ _ h => by cases h
  have hnd : NoDeps K6 :=
    (((((((hnd0.setE (by simp [intE, Entry.vdeps, Mode.ownSlot])).setE
      (by simp [intE, Entry.vdeps, Mode.ownSlot])).setE (by rw [hEDe]; rfl)).setE
      (by rw [hEVe]; rfl)).kill _ _ _).setE (by rw [hEDe]; rfl)).kill _ _ _).setE
      (by rw [hEV6]; rfl)
  have hfix : kill .drop false 3 K6 = K6 := hnd.kill_eq _ _ _
  have h63 : K6 3 = some EV6 := by simp [K6, A2.setE]
  -- the element checked out to `x` (binding 4)
  let EA : Entry := Entry.arm { popE 3 EV6 DT with ty := DT, held := (popE 3 EV6 DT).held }
  have hEAe : EA = ⟨DT, .own, true, [], [], false, false⟩ := by
    simp [EA, hEV6, popE, DT, T, Entry.arm, Ty.dtorViews, Ty.holdsView]
  let K7 : Ctx := A2.setE K6 4 EA
  have hK7 : NoRootb K7 := hK6.setE (by rw [hEAe]; simp)
  have hs : StmtT P (A2.setE (kill .drop false 3 K6) 4 EA) [] .skip K7 := by
    rw [hfix]; exact StmtT.skip
  have h73 : K7 3 = some EV6 := by simp [K7, K6, A2.setE, upd]
  -- the give-back, typed as `vec_push v x`
  let K8 : Ctx := A2.setE (kill .replace false 4 K7) 4 { EA with live := false, dtor := false }
  have hK8 : NoRootb K8 := (hK7.kill _ _ _).setE (by rw [hEAe]; simp)
  have hmove8 : PushArg K7 [] 4 EA DT EA.held K8 :=
    PushArg.move (Γ := K7) (F := []) (y := 4) (E := EA) (t := DT) rfl (by rw [hEAe])
      (by simp) (hK7.noPin _) (DtorSafe.of_none (fun v E h => (hK7 v E h).2.1) _ _ _)
  have hK83 : K8 3 = some EV6 := by
    simp [K8, K7, K6, A2.setE, upd, A2.kill, killE, hits, hEV6, Entry.vdeps, Mode.ownSlot]
  have hpush8 := StmtT.push (P := P) (Γ := K7) (Γ1 := K8) (F := []) (x := 3) (y := 4) (Ex := EV6)
    (Ey := EA) (Ex1 := EV6) (t := DT) (D := EA.held) h73 (by rw [hEV6]) (by rw [hEV6])
    (Or.inl (by rw [hEV6])) (by simp) (by simp [K7, A2.setE]) (by rw [hEAe]) (by rw [hEAe])
    (by decide) hmove8 (by rw [hEAe]; simp [roots]) hK83 (by rw [hEV6])
    (DtorSafe.of_none (fun v E h => (hK8 v E h).2.1) _ _ _) (by rw [hEV6]; simp)
  let EV9 : Entry := { EV6 with held := EV6.held ++ ownHeld true DT EA.held }
  have hK9 : NoRootb (A2.setE (kill .realloc DT.holdsView 3 K8) 3 EV9) :=
    (hK8.kill _ _ _).setE (by simp [EV9, hEV6])
  have hel := withElemD_typed (P := P) (F := []) (v := 3) (x := 4) (f := 0) (t := T) (i := .lit 0)
    (s := .skip) (H := (popE 3 EV6 DT).held)
    h63 (by rw [hEV6]) (Or.inl (by rw [hEV6])) (by rw [hEV6]; rfl) (by simp)
    (DtorSafe.of_none (fun v E h => (hK6 v E h).2.1) _ _ _) ExprT.lit rfl rfl rfl drop_ok h64 (by simp)
    rfl (HeldUp.refl _ _) hs ExprT.lit hpush8 (hK9.endOK _) (by simp [Stmt.assigns])
    (by simp [Stmt.vars]) (by simp [Expr.vars]) (hK6.noPin _)
  have hK10 := hK9.exitScope 4
  have hbody := StmtT.seq (P := P) rfl hpush hel
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hbody
    (hK10.endOK _) (by simp [Stmt.assigns, Stmt.withElemD])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv
    ((hK10.exitScope 3).endOK _) (by simp [Stmt.assigns, Stmt.withElemD])
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK10.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((hK10.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program that hands an element of a `Vec` of destructor values over,
    as code, is memory safe. -/
theorem mainElem_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 5) mainElem (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := mainElem_typed
  exact memory_safe prog_ok prog_codes ht rfl
    (by simp [mainElem, Stmt.withElemD, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

/-! ### A struct with a `Vec` of destructor values for a field (Agora #607)

`main5`'s program, and then `: c 3  :drop g ( pair v c )`: the `Vec` moves
into a struct, which is bound by `letd` at `GVD`, the destructor type whose
destructor is its glue (`glueV`): the glue takes the struct apart and hands
the `Vec` to a `letd` at its own type, whose frame drains it. -/

def main9 : Stmt :=
  .letv 0 (.expr (.lit 1)) (.letv 1 (.expr (.lit 2))
    (.letd 2 0 (.pair 0 1) (.letd 3 0 (.new DT)
      (.seq (.push 3 2) (.letv 4 (.expr (.lit 3)) (.letd 5 7 (.pair 3 4) .skip))))))

theorem main9_typed : ∃ Δ, StmtT P (fun _ => none) [] main9 Δ := by
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
  -- a struct literal takes the `Vec` for a field
  let K7 : Ctx := A2.setE K6 4 intE
  have hK7' : NoRootb K7 := hK6.setE (by simp [intE])
  let K8 : Ctx := A2.setE (kill .replace false 3 K7) 3 { EV6 with live := false, dtor := false }
  have hK8 : NoRootb K8 := (hK7'.kill _ _ _).setE (by rw [hEV6]; simp)
  have h73 : K7 3 = some EV6 := by simp [K7, K6, A2.setE, upd]
  have hmv3 : PushArg K7 [] 3 EV6 EV6.ty EV6.held K8 :=
    PushArg.move (Γ := K7) (F := []) (y := 3) (E := EV6) (t := EV6.ty) rfl (by rw [hEV6]) (by simp)
      (hK7'.noPin _) (DtorSafe.of_none (fun v E h => (hK7' v E h).2.1) _ _ _)
  have h84 : K8 4 = some intE := by
    simp [K8, K7, A2.setE, upd, A2.kill, killE, hits, intE, Entry.vdeps, Mode.ownSlot]
  let EG0 : Entry := ⟨.prod EV6.ty intE.ty, .own, true, [], EV6.held ++ [], false, false⟩
  have hgp : RhsT K7 [] (.pair 3 4) EG0 K8 :=
    RhsT.pair (Ey := EV6) (Ez := intE) h73 (by rw [hEV6]) hmv3 h84 rfl PushArg.int
      (by simp [intE, Mode.ownSlot])
  let EGa : Entry := Entry.arm { EG0 with ty := GVD, held := EG0.held }
  have hEGa : EGa.mode ≠ .rootb ∧ EGa.dtor = false ∧ EGa.dbind = false := by
    simp [EGa, EG0, Entry.arm, GVD, GV, DT, T, Ty.dtorViews, Ty.holdsView]
  have hK9 : NoRootb (A2.setE K8 5 EGa) := hK8.setE hEGa
  have hg := StmtT.letd (P := P) (Γ := K7) (Γ1 := K8) (F := []) (x := 5) (f := 7) (r := .pair 3 4)
    (s := .skip) (E := EG0) (t := GV) (H := EG0.held) (τ := GVD) rfl
    (by simp [K7, K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) hgp rfl
    (Or.inl ⟨rfl, Or.inl (by simp [EG0, hEV6, intE, GV])⟩) rfl rfl (letd_fn gvdrop_ok) (HeldUp.refl _ _)
    StmtT.skip (hK9.endOK _)
  have h4 := StmtT.letv (P := P) (x := 4) (r := .expr (.lit 3)) (E := intE) (F := []) (Γ := K6) (Γ1 := K6)
    rfl (by simp [K6, K5, K4, K3, K2, K1, A2.setE, upd, A2.kill]) (by simp) (RhsT.expr ExprT.lit) hg
    ((hK9.exitScope 5).endOK _)
  have hK7 := (hK9.exitScope 5).exitScope 4
  have hbody := StmtT.seq (P := P) rfl hpush h4
  have hdv := StmtT.letd (P := P) (Γ := K3) (Γ1 := K3) (F := []) (x := 3) (f := 0) (r := .new DT)
    (E := EN) (t := T) (H := []) (τ := .vec DT) rfl (by simp [K3, K2, K1, A2.setE, upd])
    (by simp) hnew rfl (Or.inr ⟨0, rfl, rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hbody (hK7.endOK _)
    (by simp [Stmt.assigns, Stmt.vecTruncD, Stmt.vecClearD, Stmt.vecFreeD])
  have hd := StmtT.letd (P := P) (Γ := K2) (Γ1 := K2) (F := []) (x := 2) (f := 0) (r := .pair 0 1)
    (E := EP) (t := T) (H := []) rfl (by simp [K2, K1, A2.setE, upd])
    (by simp) hpair rfl (Or.inl ⟨rfl, Or.inl rfl⟩) rfl rfl (letd_fn drop_ok) (HeldUp.refl _ _) hdv
    ((hK7.exitScope 3).endOK _) (by simp [Stmt.assigns, Stmt.vecTruncD, Stmt.vecClearD, Stmt.vecFreeD])
  have h1 := StmtT.letv (P := P) (x := 1) (r := .expr (.lit 2)) (E := intE) (F := []) (Γ := K1) (Γ1 := K1)
    rfl (by simp [K1, A2.setE]) (by simp) (RhsT.expr ExprT.lit) hd
    (((hK7.exitScope 3).exitScope 2).endOK _)
  exact ⟨_, StmtT.letv (P := P) (x := 0) (r := .expr (.lit 1)) (E := intE) (F := []) (Γ := fun _ => none)
    (Γ1 := fun _ => none) rfl rfl (by simp) (RhsT.expr ExprT.lit) h1
    ((((hK7.exitScope 3).exitScope 2).exitScope 1).endOK _)⟩

/-- The program with a `Vec` of destructor values inside a struct is memory safe. -/
theorem main9_safe {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem 6) main9 (.ok m' s')) :
    ¬ Stuck P m' s' := by
  obtain ⟨Δ, ht⟩ := main9_typed
  exact memory_safe prog_ok prog_codes ht rfl (by simp [main9, Stmt.codesOK, Rhs.codeOK]) (by decide) hr

end A2.DtorWitness
