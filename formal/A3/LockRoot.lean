import A3.LockExcl

/-! A3.2 — Agora #808: **a check-out's root share outlives its body.**

`StmtT.withLock` asks the binding `a` the check-out is through to be a root
(`Ea.mode.isRoot`) that its body does not name (`a ∉ s.vars`).  The marking
sweep's roots are every thread's slots (`Cfg.roots`), so while `a`'s slot
holds the lock share `.lk k` (or the cell share `.cell k`), block `k` is
reached and kept.  This file proves that no step changes that slot while the
check-out's frame `scopeL k t x s` is out:

* a step leaves the slot of a binding its statement does not name
  (`Stmt.nm`: the names, but a `frozen` list's, which only says what a call
  lends out) and that holds a share, and names it no more after
  (`Step.keepSlot`): what a step changes is a binding it names, a fresh one, or
  (a change through a borrow, `NodeOf`) the owner of a `Vec`, which holds no
  share; a call's inside is named apart from `base` on, but its `inout`
  arguments, which the call names; a `sink` argument is named too; a call
  through a package passes the bindings it captures by name, unnamed, but
  only `inp` ones and `Vec`s changed in place (`CapsOK`, kept in memory by
  `PkgsOK`), so none of them holding a share is moved or changed
  (`CapShr`, from the typing: `TypedAt.capShr`);
* so each frame on a thread's spine has such a slot on its thread
  (`LkRoots`, kept by every thread's step, `Step.lkRoots`, and by a spawn,
  `Redex.lkRoots`), and its block is there (`RootInv`, kept by every `TStep`:
  the marking sweep keeps what that slot reaches, `reach_rootInv`).

So in every configuration a run reaches, a frame's block is still there
(`reach_frame_live`), and the give-back lemmas need no hypothesis on it
(`reach_scopeL_end_gives_back`, `reach_scopeL_panic`). -/

namespace A3
open A2

/-! ### The names a statement uses -/

/-- The variables a statement names: `Stmt.vars` but for a `frozen` list,
    which a call puts around its inside to say what it lends out (every
    caller binding but its `inout` arguments), and which nothing reads. -/
def _root_.A2.Stmt.nm : Stmt → List Var
  | .skip => []
  | .seq a b => a.nm ++ b.nm
  | .letv x r s => x :: r.vars ++ s.nm
  | .letcall x _ args s => x :: args ++ s.nm
  | .assign x r => x :: r.vars
  | .ite c a b => c.vars ++ a.nm ++ b.nm
  | .while c s => c.vars ++ s.nm
  | .push x y => [x, y]
  | .free x => [x]
  | .scope x s => x :: s.nm
  | .rbind p s => p :: s.nm
  | .frozen _ s => s.nm
  | .panic => []
  | .letrec x _ s => x :: s.nm
  | .catchR x _ s => x :: s.nm
  | .unpair y x z s => y :: x :: z :: s.nm
  | .callc x c _ zs s => x :: c :: zs ++ s.nm
  | .letd x _ r s => x :: r.vars ++ s.nm
  | .scopeD x _ s => x :: s.nm
  | .edit _ x op => x :: op.vars
  | .withLock a x s => x :: a :: s.nm
  | .scopeL _ _ x s => x :: s.nm
  | .insert x i y => x :: y :: i.vars
  | .withElem v i x s => x :: v :: i.vars ++ s.nm
  | .callcE x c _ zs s => x :: c :: zs ++ s.nm

theorem nm_vars (s : Stmt) : ∀ v, v ∉ s.vars → v ∉ s.nm := by
  induction s <;> intro v hv <;> simp_all [Stmt.nm, Stmt.vars]

theorem nm_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).nm = s.nm.map ρ := by
  induction s <;> simp_all [Stmt.rename, Stmt.nm, Rhs.vars_rename, Expr.vars_rename, Edit.vars_rename]

/-! ### A slot that holds a share -/

/-- A lock share or a cell share: what a check-out is through. -/
def Shr (w : Val) : Prop := ∃ k, w = .lk k ∨ w = .cell k

/-- A share holds nothing else. -/
theorem Sub.of_shr {n w : Val} (h : Sub n w) (hw : Shr w) : n = w := by
  obtain ⟨k, rfl | rfl⟩ := hw <;> cases h <;> rfl

theorem ne_of_none {st : Var → Option Slot} {y x : Var} {sl : Slot} (hy : st y = some sl)
    (hx : st x = none) : y ≠ x := by
  rintro rfl; rw [hx] at hy; cases hy

theorem getD_mem {l : List Var} {i : Nat} (h : i < l.length) (d : Var) : l.getD i d ∈ l := by
  rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem h, Option.getD_some]
  exact List.getElem_mem h

theorem ne_add_of_lt {y b : Nat} (h : y < b) (c : Nat) : y ≠ b + c :=
  Nat.ne_of_lt (Nat.lt_of_lt_of_le h (Nat.le_add_right _ _))

theorem _root_.A2.TakeVal.st_ne {m m1 : Mem} {y' : Var} {v : Val} (h : TakeVal m y' v m1) {y : Var}
    (hne : y ≠ y') : m1.st y = m.st y := by
  cases h with
  | own _ => simp [upd_ne _ _ hne]
  | bor _ _ => rfl

/-- A right-hand side changes only the slots it names. -/
theorem EvalR.st_ne {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1)) {y : Var}
    (hy : y ∉ r.vars) : m1.st y = m.st y := by
  cases h with
  | moveOwn _ | pop _ _ _ | remove _ _ _ _ _ | takel _ | taker _ =>
    simp only [Rhs.vars, List.mem_cons, not_or] at hy
    simp [upd_ne _ _ hy.1]
  | pair h1 h2 =>
    simp only [Rhs.vars, List.mem_cons, List.not_mem_nil, or_false, not_or] at hy
    rw [TakeVal.st_ne h2 hy.2, TakeVal.st_ne h1 hy.1]
  | inl h1 | inr h1 | arcNew h1 _ | lockNew h1 _ _ | cellNew h1 _ _ =>
    simp only [Rhs.vars, List.mem_cons, List.not_mem_nil, or_false] at hy
    exact TakeVal.st_ne h1 hy
  | pack h1 =>
    simp only [Rhs.vars, List.mem_cons, not_or] at hy
    exact TakeVal.st_ne h1 hy.1
  | chanSend _ h1 _ _ _ _ _ | chanSendClosed _ h1 _ _ _ _ | lockRestore _ h1 _ _ =>
    simp only [Rhs.vars, List.mem_cons, List.not_mem_nil, or_false, not_or] at hy
    exact TakeVal.st_ne h1 hy.2
  | _ => rfl

/-- A lock scope's end drops its binding only. -/
theorem Release.st_eq {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') :
    m'.st = upd m.st x none := by
  cases h <;> rfl

/-! ### Binding a call's parameters -/

theorem BindParams.len {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : ps.length = as.length := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih | sink _ _ ih | inout _ ih => simp [ih]

/-- Binding the parameters leaves a caller binding below `base` that is no
    argument but of an `in` parameter's. -/
theorem BindParams.keep {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') {y : Var} (hlt : y < base)
    (hinp : ∀ p ∈ ps.zip as, p.2 = y → p.1.1 = .inp) : m'.st y = m.st y := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih =>
    rw [ih hlt (fun p hp => hinp p (List.mem_cons_of_mem _ hp))]
    simp only [Mem.set_st]; exact upd_ne _ _ (ne_add_of_lt hlt _)
  | @sink m0 _ t _ a _ _ _ v _ _ ih =>
    rw [ih hlt (fun p hp => hinp p (List.mem_cons_of_mem _ hp))]
    have hay : y ≠ a := fun e => by
      have := hinp ((.sink, t), a) List.mem_cons_self e.symm; cases this
    simp only [Mem.set_st]; rw [upd_ne _ _ (ne_add_of_lt hlt _), upd_ne _ _ hay]
  | inout _ ih => exact ih hlt (fun p hp => hinp p (List.mem_cons_of_mem _ hp))

theorem mem_zip_of_getElem? {ps : List (PMode × Ty)} {as : List Var} (hl : ps.length = as.length)
    {i : Nat} {p : PMode × Ty} (h : ps[i]? = some p) : (p, as.getD i 0) ∈ ps.zip as := by
  have hi : i < ps.length := (List.getElem?_eq_some_iff.mp h).1
  have hia : i < as.length := hl ▸ hi
  rw [List.mem_iff_getElem?]
  refine ⟨i, ?_⟩
  rw [List.getElem?_zip_eq_some]
  refine ⟨h, ?_⟩
  rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hia, Option.getD_some]

/-! ### The names of a call's inside -/

theorem nm_wrap (s : Stmt) : ∀ (ps : List (PMode × Ty)) (base i : Nat) (v : Var),
    v ∈ (wrapParams ps base i s).nm → base + i ≤ v ∨ v ∈ s.nm := by
  intro ps
  induction ps with
  | nil => intro _ _ v h; exact .inr h
  | cons p ps ih =>
    intro base i v h
    obtain ⟨pm, t⟩ := p
    cases pm with
    | inp | sink =>
      simp only [wrapParams, Stmt.nm, List.mem_cons] at h
      rcases h with h | h
      · exact .inl (Nat.le_of_eq h.symm)
      · rcases ih base (i + 1) v h with h | h
        · exact .inl (by omega)
        · exact .inr h
    | inout b =>
      rcases ih base (i + 1) v h with h | h
      · exact .inl (by omega)
      · exact .inr h

theorem callRen_cases (ps : List (PMode × Ty)) (args : List Var) (base v : Var) :
    base ≤ callRen ps args base v ∨
      ∃ b t, ps[v]? = some (.inout b, t) ∧ args.getD v 0 = callRen ps args base v := by
  unfold callRen
  split
  · next b t h => exact .inr ⟨b, t, h, rfl⟩
  · exact .inl (Nat.le_add_right _ _)

/-- A call's inside names its result's binding, fresh bindings from `base`
    on, and its `inout` arguments. -/
theorem nm_callIn {fn : Fn} {args : List Var} {base : Nat} {x v : Var}
    (h : v ∈ (callIn fn args base x).nm) :
    base ≤ v ∨ v = x ∨ ∃ i b t, fn.params[i]? = some (.inout b, t) ∧ args.getD i 0 = v := by
  have key : v ∈ (Stmt.seq (.frozen ((List.range base).filter
      (fun v => !(inoutArgs fn.params args).contains v))
      (wrapParams fn.params base 0 (fn.body.rename (callRen fn.params args base))))
      (.assign x (.var (base + fn.params.length)))).nm → base ≤ v ∨ v = x ∨
      ∃ i b t, fn.params[i]? = some (.inout b, t) ∧ args.getD i 0 = v := by
    intro h
    simp only [Stmt.nm, List.mem_append, List.mem_cons, Rhs.vars, List.not_mem_nil, or_false] at h
    rcases h with h | h | h
    · rcases nm_wrap _ _ _ _ _ h with h | h
      · exact .inl (by omega)
      · rw [nm_rename] at h
        obtain ⟨u, _, rfl⟩ := List.mem_map.mp h
        rcases callRen_cases fn.params args base u with h | ⟨b, t, h1, h2⟩
        · exact .inl h
        · exact .inr (.inr ⟨u, b, t, h1, h2⟩)
    · exact .inr (.inl h)
    · exact .inl (h ▸ Nat.le_add_right _ _)
  unfold callIn resFrame at h
  split at h
  · simp only [Stmt.nm, List.mem_cons] at h
    rcases h with h | h
    · exact .inl (h ▸ Nat.le_add_right _ _)
    · exact key h
  · simp only [Stmt.nm, List.mem_cons] at h
    rcases h with h | h
    · exact .inl (h ▸ Nat.le_add_right _ _)
    · exact key h

/-! ### What a call through a package moves -/

/-- At a call through a package (`callc`), every argument its code takes
    moved or changed is the environment's binding or one the call names, or
    holds no share: a binding the package captures by name is read (`inp`)
    or is a `Vec` changed in place (`CapsOK`, kept in memory by `PkgsOK`),
    never a lock or cell share.  Asked of the redexes of a statement's
    spine. -/
def CapShr (P : Prog) (st : Var → Option Slot) (nv : Nat) : Stmt → Prop
  | .seq a _ => CapShr P st nv a
  | .scope _ s => CapShr P st nv s
  | .scopeD _ _ s => CapShr P st nv s
  | .rbind _ s => CapShr P st nv s
  | .frozen _ s => CapShr P st nv s
  | .catchR _ _ s => CapShr P st nv s
  | .scopeL _ _ _ s => CapShr P st nv s
  | .callc _ c j zs _ => ∀ o fs te ms env cs f fn, st c = some ⟨o, some (.pkg fs te ms env cs)⟩ →
      fs[j]? = some f → P[f]? = some fn → ∀ p ∈ fn.params.zip (nv :: zs ++ cs.map (·.1)),
      p.1.1 ≠ .inp → p.2 ∈ nv :: zs ∨ ∀ o' w, st p.2 = some ⟨o', some w⟩ → ¬ Shr w
  | _ => True

/-- A change through a borrow rewrites an owner's tree that holds a `Vec`,
    so no slot that holds a share. -/
theorem nodeOf_ne {m : Mem} {x ow : Var} {T : Val} {t : Ty} {c d : Nat} {es : List Val}
    (h : NodeOf m x ow T t c d es) {y : Var} {o : Bool} {w : Val} (hy : m.st y = some ⟨o, some w⟩)
    (hw : Shr w) (hx : y ≠ x) : y ≠ ow := by
  rintro rfl
  obtain ⟨_, _, hT, hc⟩ := h
  rw [hy] at hT; cases hT
  rcases hc with ⟨rfl, _⟩ | ⟨_, hs⟩
  · exact hx rfl
  · have := Sub.of_shr hs hw
    obtain ⟨k, h1 | h1⟩ := hw <;> rw [h1] at this <;> cases this

local macro "nm_close" : tactic => `(tactic| simp_all only [Stmt.nm, Rhs.vars, Expr.vars, Edit.vars,
  List.mem_cons, List.mem_append, List.not_mem_nil, List.mem_singleton, or_false, false_or, not_or,
  not_false_eq_true, and_true, true_and, and_self, ne_eq, List.cons_append, List.nil_append,
  List.mem_map, List.map_nil])

/-- **A step leaves the slot of a binding its statement does not name, and
    that holds a share**, and names it no more after: what a step changes is
    a binding it names, a fresh one, or (a change through a borrow) the owner
    of a `Vec`; a call's inside is named apart from `base` but for its
    `inout` arguments, which the call names, and a call through a package
    passes no share it captures by name `inout` or `sink` (`CapShr`). -/
theorem Step.keepSlot {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) :
    CapShr P m.st m.nv s → ∀ {y : Var} {o : Bool} {w : Val}, m.st y = some ⟨o, some w⟩ → Shr w →
      y ∉ s.nm → y < m.nv → r.mem.st y = m.st y ∧ ∀ m' s', r = .ok m' s' → y ∉ s'.nm := by
  induction h with
  | seqSkip =>
    intro _ y o w _ _ hyn _
    exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | seqL _ ih =>
    intro hck y o w hy hw hyn hlt
    have hyn' : y ∉ _ := fun h => hyn (List.mem_append_left _ h)
    obtain ⟨h1, h2⟩ := ih hck hy hw hyn' hlt
    exact ⟨h1, fun _ _ he => by cases he; have := h2 _ _ rfl; nm_close⟩
  | seqP _ ih =>
    intro hck y o w hy hw hyn hlt
    exact ⟨(ih hck hy hw (fun h => hyn (List.mem_append_left _ h)) hlt).1, fun _ _ he => by cases he⟩
  | @letv m' x r s v o0 hx he =>
    intro _ y o w hy _ hyn _
    simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hyn
    refine ⟨?_, fun _ _ he' => by cases he'; nm_close⟩
    show (m'.set x _).st y = _
    rw [Mem.set_st, upd_ne _ _ hyn.1, EvalR.st_ne he hyn.2.1]
  | letvP _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he⟩
  | @letcall m' x f args s fn hf hx hb =>
    intro _ y o w hy _ hyn hlt
    simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hyn
    obtain ⟨hyx, hya, hys⟩ := hyn
    refine ⟨?_, fun _ _ he => ?_⟩
    · show (({ (m'.set x _).set (m.nv + fn.params.length) _ with nv := _ } : Mem)).st y = _
      simp only [Mem.set_st]
      rw [upd_ne _ _ (ne_add_of_lt hlt _), upd_ne _ _ hyx]
      exact BindParams.keep hb (Nat.lt_of_lt_of_le hlt (Nat.le_add_right _ 0))
        (fun p hp e => absurd (e ▸ (List.of_mem_zip hp).2) hya)
    · cases he
      simp only [callStmt, Stmt.nm, List.mem_cons, List.mem_append, not_or]
      refine ⟨hyx, fun hm => ?_, hys⟩
      rcases nm_callIn hm with h | h | ⟨i, b, t, hi, he⟩
      · exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le hlt h)
      · exact hyx h
      · have hil : i < args.length := by
          rw [← BindParams.len hb]; exact (List.getElem?_eq_some_iff.mp hi).1
        exact hya (he ▸ getD_mem hil 0)
  | @scopeSkip x sl a' hx hd =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    exact ⟨by show (({ m with alloc := a' } : Mem).remove x).st y = _; simp [upd_ne _ _ hyn.1],
      fun _ _ he => by cases he; nm_close⟩
  | scopeIn _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    obtain ⟨h1, h2⟩ := ih hck hy hw hyn.2 hlt
    exact ⟨h1, fun _ _ he => by cases he; have := h2 _ _ rfl; nm_close⟩
  | @scopeP m1 x s sl a' _ hx hd ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he⟩
    show (({ m1 with alloc := a' } : Mem).remove x).st y = _
    simp only [Mem.remove_st]; rw [upd_ne _ _ hyn.1]; exact (ih hck hy hw hyn.2 hlt).1
  | @rbindSkip p w0 hp =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    exact ⟨by show (m.remove p).st y = _; simp [upd_ne _ _ hyn.1], fun _ _ he => by cases he; nm_close⟩
  | rbindIn _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    obtain ⟨h1, h2⟩ := ih hck hy hw hyn.2 hlt
    exact ⟨h1, fun _ _ he => by cases he; have := h2 _ _ rfl; nm_close⟩
  | @rbindP m1 p s w0 _ hp ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he⟩
    show (m1.remove p).st y = _
    simp only [Mem.remove_st]; rw [upd_ne _ _ hyn.1]; exact (ih hck hy hw hyn.2 hlt).1
  | frozenSkip => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | frozenIn _ ih =>
    intro hck y o w hy hw hyn hlt
    obtain ⟨h1, h2⟩ := ih hck hy hw hyn hlt
    exact ⟨h1, fun _ _ he => by cases he; have := h2 _ _ rfl; exact this⟩
  | frozenP _ ih =>
    intro hck y o w hy hw hyn hlt
    exact ⟨(ih hck hy hw hyn hlt).1, fun _ _ he => by cases he⟩
  | @assign m1 x r v o0 sl a' _ he hx hd =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he' => by cases he'; nm_close⟩
    show (({ m1 with alloc := a' } : Mem).set x _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1]; exact EvalR.st_ne he hyn.2
  | assignP _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he⟩
  | iteT _ _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | iteF _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | «while» => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | @push m1 x y' v t c d es ht _ _ _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, List.not_mem_nil, or_false, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show (m1.set x _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1]; exact TakeVal.st_ne ht hyn.2
  | @pushRealloc m1 x y' v t c d es ht _ _ _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, List.not_mem_nil, or_false, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show (({ m1 with alloc := _, nid := _ } : Mem).set x _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1]; exact TakeVal.st_ne ht hyn.2
  | @editPush m1 b x y' ow v T T' t c d es ht hn _ =>
    intro _ y o w hy hw hyn _
    simp only [Stmt.nm, Edit.vars, List.mem_cons, List.not_mem_nil, or_false, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    have h1 := TakeVal.st_ne ht hyn.2
    show (m1.set ow _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ (nodeOf_ne hn (h1.trans hy) hw hyn.1)]; exact h1
  | @editPushRealloc m1 b x y' ow v T T' t c d es ht hn _ =>
    intro _ y o w hy hw hyn _
    simp only [Stmt.nm, Edit.vars, List.mem_cons, List.not_mem_nil, or_false, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    have h1 := TakeVal.st_ne ht hyn.2
    show (({ m1 with alloc := _, nid := _ } : Mem).set ow _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ (nodeOf_ne hn (h1.trans hy) hw hyn.1)]; exact h1
  | @editTrunc b x ow i n T T' t c d es a' _ hn _ _ =>
    intro _ y o w hy hw hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show (({ m with alloc := a' } : Mem).set ow _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ (nodeOf_ne hn hy hw hyn.1)]
  | @editSet m1 b x y' ow i n v T T' t c d es a' _ _ ht hn _ _ =>
    intro _ y o w hy hw hyn _
    simp only [Stmt.nm, Edit.vars, List.mem_cons, List.mem_append, List.not_mem_nil, or_false,
      not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    have h1 := TakeVal.st_ne ht hyn.2.2
    show (({ m1 with alloc := a' } : Mem).set ow _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ (nodeOf_ne hn (h1.trans hy) hw hyn.1)]; exact h1
  | @editSetOOB m1 b x y' ow i n v T t c d es a' _ ht _ _ _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, Edit.vars, List.mem_cons, List.mem_append, List.not_mem_nil, or_false,
      not_or] at hyn
    exact ⟨TakeVal.st_ne ht hyn.2.2, fun _ _ he => by cases he; nm_close⟩
  | @insert m1 x y' i n v t c d es _ ht _ _ _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show (m1.set x _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1]; exact TakeVal.st_ne ht hyn.2.1
  | @withElem v x i s t c d n es _ _ _ _ _ hx =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show ((m.set v _).set x _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1, upd_ne _ _ hyn.2.1]
  | withElemOOB _ _ _ _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he⟩
  | @free x t a' _ _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, List.not_mem_nil, or_false] at hyn
    exact ⟨by show (({ m with alloc := a' } : Mem).set x _).st y = _; simp [upd_ne _ _ hyn],
      fun _ _ he => by cases he; nm_close⟩
  | panic => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he⟩
  | waitPanic _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he⟩
  | @letrec x f s fn hf hps hx =>
    intro _ y o w hy _ hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => ?_⟩
    · show (({ (m.set x _).set (m.nv + fn.params.length) _ with nv := _ } : Mem)).st y = _
      simp only [Mem.set_st]
      rw [upd_ne _ _ (ne_add_of_lt hlt _), upd_ne _ _ hyn.1]
    · cases he
      have hci : y ∉ (callIn fn [] m.nv x).nm := fun hm => by
        rcases nm_callIn hm with h | h | ⟨i, b, t, hi, _⟩
        · exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le hlt h)
        · exact hyn.1 h
        · rw [hps] at hi; cases hi
      simp only [recStmt]; nm_close
  | catchIn _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    obtain ⟨h1, h2⟩ := ih hck hy hw hyn.2 hlt
    exact ⟨h1, fun _ _ he => by cases he; have := h2 _ _ rfl; nm_close⟩
  | catchSkip => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | @unpair y0 x z s v w0 _ _ _ _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show (((m.set y0 _).set x _).set z _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.2.2.1, upd_ne _ _ hyn.2.1, upd_ne _ _ hyn.1]
  | @callc m1 x c j zs k o0 fs te ms env cs f fn hc hfs hf hx hb =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hyn
    obtain ⟨hyx, hyc, hyz, hyk⟩ := hyn
    have hyv : y ≠ m.nv := Nat.ne_of_lt hlt
    -- every argument equal to `y` is an `in` one
    have hinp : ∀ p ∈ fn.params.zip (m.nv :: zs ++ cs.map (·.1)), p.2 = y → p.1.1 = .inp := by
      intro p hp e
      refine Classical.byContradiction fun hne => ?_
      rcases hck o0 fs te ms env cs f fn hc hfs hf p hp hne with h | h
      · rw [e] at h
        rcases List.mem_cons.mp h with h | h
        · exact hyv h
        · exact hyz h
      · exact h o w (e ▸ hy) hw
    refine ⟨?_, fun _ _ he => ?_⟩
    · show (({ (m1.set x _).set (m.nv + 1 + fn.params.length) _ with nv := _ } : Mem)).st y = _
      simp only [Mem.set_st]
      rw [upd_ne _ _ (ne_add_of_lt (Nat.lt_succ_of_lt hlt) _), upd_ne _ _ hyx,
        BindParams.keep hb (Nat.lt_succ_of_lt hlt) hinp]
      show upd m.st m.nv _ y = _
      rw [upd_ne _ _ hyv]
    · cases he
      have hci : y ∉ (callIn fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x).nm := fun hm => by
        rcases nm_callIn hm with h | h | ⟨i, b, t, hi, he⟩
        · exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le (Nat.lt_succ_of_lt hlt) h)
        · exact hyx h
        · have hz := mem_zip_of_getElem? (BindParams.len hb) hi
          rw [he] at hz
          have := hinp _ hz rfl
          cases this
      nm_close
  | @callcE x c j zs k fs te ms env f fn _ _ _ hx _ =>
    intro _ y o w _ _ hyn hlt
    simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hyn
    have hyv : y ≠ m.nv := Nat.ne_of_lt hlt
    have hyv1 : y ≠ m.nv + 1 := ne_add_of_lt hlt 1
    refine ⟨?_, fun _ _ he => by cases he; simp only [handStmt]; nm_close⟩
    show (({ ((m.set c _).set m.nv _).set x _ with nv := _ } : Mem)).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1, upd_ne _ _ hyv, upd_ne _ _ hyn.2.1]
  | @callcD x c j zs k fs te ms env f fn pt _ _ _ hx _ =>
    intro _ y o w _ _ hyn hlt
    simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hyn
    have hyv : y ≠ m.nv := Nat.ne_of_lt hlt
    have hyv1 : y ≠ m.nv + 1 := ne_add_of_lt hlt 1
    refine ⟨?_, fun _ _ he => by cases he; simp only [handStmtD]; nm_close⟩
    show (({ ((m.set c _).set m.nv _).set x _ with nv := _ } : Mem)).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1, upd_ne _ _ hyv, upd_ne _ _ hyn.2.1]
  | @catchP m1 x m0 s _ _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show (m1.set x _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1]; exact (ih hck hy hw hyn.2 hlt).1
  | @letd m' x f r s v o0 hx he =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hyn
    refine ⟨?_, fun _ _ he' => by cases he'; nm_close⟩
    show (m'.set x _).st y = _
    rw [Mem.set_st, upd_ne _ _ hyn.1, EvalR.st_ne he hyn.2.1]
  | letdP _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he⟩
  | scopeDIn _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    obtain ⟨h1, h2⟩ := ih hck hy hw hyn.2 hlt
    exact ⟨h1, fun _ _ he => by cases he; have := h2 _ _ rfl; nm_close⟩
  | scopeDEnd _ _ =>
    intro _ y o w _ _ hyn hlt
    have hyv : y ≠ _ := Nat.ne_of_lt hlt
    exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | @scopeDMoved x f _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    exact ⟨by show (m.remove x).st y = _; simp [upd_ne _ _ hyn.1], fun _ _ he => by cases he; nm_close⟩
  | scopeDDrain _ =>
    intro _ y o w _ _ hyn hlt
    have hyv : y ≠ _ := Nat.ne_of_lt hlt
    exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | scopeDEmpty _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | scopeDP _ _ _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    exact ⟨(ih hck hy hw hyn.2 hlt).1, fun _ _ he => by cases he; nm_close⟩
  | scopeDPDrain _ _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    exact ⟨(ih hck hy hw hyn.2 hlt).1, fun _ _ he => by cases he; nm_close⟩
  | @scopeDPMoved m1 x f s _ _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he⟩
    show (m1.remove x).st y = _
    simp only [Mem.remove_st]; rw [upd_ne _ _ hyn.1]; exact (ih hck hy hw hyn.2 hlt).1
  | @withLock a x s k t v _ _ hx _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show (({ m with blk := _ } : Mem).set x _).st y = _
    simp only [Mem.set_st]; rw [upd_ne _ _ hyn.1]
  | scopeLIn _ ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    obtain ⟨h1, h2⟩ := ih hck hy hw hyn.2 hlt
    exact ⟨h1, fun _ _ he => by cases he; have := h2 _ _ rfl; nm_close⟩
  | scopeLSkip hr _ =>
    intro _ y o w _ _ hyn _
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    exact ⟨by show _ = _; rw [Res.mem, Release.st_eq hr, upd_ne _ _ hyn.1],
      fun _ _ he => by cases he; nm_close⟩
  | scopeLFail _ _ => intro _ _ _ _ _ _ _ _; exact ⟨rfl, fun _ _ he => by cases he; nm_close⟩
  | scopeLP _ hr ih =>
    intro hck y o w hy hw hyn hlt
    simp only [Stmt.nm, List.mem_cons, not_or] at hyn
    refine ⟨?_, fun _ _ he => by cases he⟩
    rw [Res.mem, Release.st_eq hr, upd_ne _ _ hyn.1]; exact (ih hck hy hw hyn.2 hlt).1
  | reap _ _ _ =>
    intro _ y o w _ _ hyn hlt
    have hyv : y ≠ _ := Nat.ne_of_lt hlt
    refine ⟨?_, fun _ _ he => by cases he; nm_close⟩
    show upd _ _ _ y = _
    rw [upd_ne _ _ hyv]

/-! ### `CapShr` from the typing -/

theorem mem_zip_map {α β γ : Type} {l : List α} {f : α → β} {g : α → γ} {p : β × γ}
    (h : p ∈ (l.map f).zip (l.map g)) : ∃ a ∈ l, p = (f a, g a) := by
  induction l with
  | nil => cases h
  | cons a l ih =>
    simp only [List.map_cons, List.zip_cons_cons, List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨a, List.mem_cons_self, rfl⟩
    · obtain ⟨b, hb, rfl⟩ := ih h
      exact ⟨b, List.mem_cons_of_mem _ hb, rfl⟩

/-- A typed call through a package: what its code takes moved or changed is
    the environment's binding, an argument the call names, or a `Vec` the
    package captures by name (`PkgsOK`), whose slot holds no share. -/
theorem capShr_callc {P : Prog} {m : Mem} {Γ Γ1 : Ctx} {F : List Var} (hi : MInv m Γ)
    (hcd : MemCodes P m) {c : Var} {j : Nat} {zs : List Var} {Ec E : Entry} {ms : List Nat} {q : Cross}
    {σ : Nat} {sig : Fn} (hc : Γ c = some Ec) (htc : Ec.ty.undtor = .fn ms q) (hj : ms[j]? = some σ)
    (hσ : P[σ]? = some sig) (hhd : sig.params.head? = some (.inp, Ec.ty))
    (hcT : CallT P Γ F σ (c :: zs) E Γ1) (x : Var) (k : Stmt) :
    CapShr P m.st m.nv (.callc x c j zs k) := by
  intro o fs te ms' env cs f fn hslot hfs hf p hp hne
  have hlc := callT_recv_live hcT hc
  obtain ⟨o0, fs0, te0, env0, cs0, hslot0⟩ := pkg_slot hi hc hlc htc
  rw [hslot] at hslot0; cases hslot0
  obtain ⟨f', fn', hfs', hf', hps, _⟩ := pkg_code hcd hslot hj hσ hhd
  rw [hfs] at hfs'; cases hfs'; rw [hf] at hf'; cases hf'
  obtain ⟨sig', hσ', hlen, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  have hzl : ((PMode.inp, te) :: sig.params.tail).length = (m.nv :: zs).length := by
    cases h : sig.params with
    | nil => rw [h] at hhd; cases hhd
    | cons p0 rest => rw [h] at hlen; simp only [List.length_cons] at hlen; simp [hlen]
  rw [hps, List.zip_append hzl] at hp
  rcases List.mem_append.mp hp with hp | hp
  · exact .inl (List.of_mem_zip hp).2
  · obtain ⟨ci, hci, rfl⟩ := mem_zip_map hp
    right
    intro o' w hw hsw
    rcases (hi.pkgs c _ _ hslot rfl fs te ms env cs (Sub.refl _)).2.1 ci hci with h | ⟨b, _, _, s, hs⟩
    · exact hne h
    · obtain ⟨Ev, hEv, hlv, _, htv, hmo, _⟩ := pkg_cap hi hc hlc htc hslot hci
      obtain ⟨T, hT, hwT, _⟩ := hi.own_val hEv hlv (by rw [hmo]; rfl)
      simp only at hw
      rw [hT] at hw; cases hw
      rw [htv, hs] at hwT
      obtain ⟨k, rfl | rfl⟩ := hsw <;> cases hwT

/-- **A typed statement's spine passes no share a package captures by name
    to be moved or changed.** -/
theorem TypedAt.capShr {P : Prog} {m : Mem} (hcd : MemCodes P m) :
    ∀ {s : Stmt}, TypedAt P m s → CapShr P m.st m.nv s := by
  intro s
  induction s with
  | seq _ _ ih _ => exact fun h => ih h.seq
  | scope _ _ ih => exact fun h => ih h.scope
  | scopeD _ _ _ ih => exact fun h => ih h.scopeD
  | rbind _ _ ih => exact fun h => ih h.rbind
  | frozen _ _ ih => exact fun h => ih h.frozen
  | catchR _ _ _ ih => exact fun h => ih h.catchR
  | scopeL _ _ _ _ ih => exact fun h => ih h.scopeL
  | callc x c j zs k _ =>
    intro h
    obtain ⟨Γ, F, Δ, ht, hi⟩ := h
    generalize hs : Stmt.callc x c j zs k = s0 at ht
    induction ht with
    | callc _ _ _ h4 h5 h6 h7 h8 _ h10 => cases hs; exact capShr_callc hi hcd h4 h5 h6 h7 h8 h10 _ _
    | sub hw _ _ ih => exact ih (hi.weaker hw) hs
    | _ => cases hs
  | _ => exact fun _ => trivial

theorem _root_.A2.StmtT.withLock_a {P : Prog} {Γ Δ : Ctx} {F : List Var} {a x : Var} {s : Stmt}
    (ht : StmtT P Γ F (.withLock a x s) Δ) : a ∉ s.vars := by
  generalize hs : Stmt.withLock a x s = s0 at ht
  induction ht with
  | withLock _ _ _ _ _ _ _ _ _ h10 => cases hs; exact h10
  | sub _ _ _ ih => exact ih hs
  | _ => cases hs

/-! ### The frames' roots on a thread -/

/-- Each `scopeL k` frame on a statement's spine has a slot of its thread that
    holds a share of block `k`, a lock's or a cell's, and that the frame's
    body does not name (the check-out's root `a`); one that is a borrow (a
    borrowed parameter's, the slot owning nothing) is bound by an `rbind`
    around the frame (`R`: the `rbind`s the spine has gone through). -/
def LkRoots (st : Var → Option Slot) : List Var → Stmt → Prop
  | R, .seq a _ => LkRoots st R a
  | R, .scope _ s => LkRoots st R s
  | R, .scopeD _ _ s => LkRoots st R s
  | R, .rbind p s => LkRoots st (p :: R) s
  | R, .frozen _ s => LkRoots st R s
  | R, .catchR _ _ s => LkRoots st R s
  | R, .scopeL k _ _ s =>
    (∃ y o w, st y = some ⟨o, some w⟩ ∧ (w = .lk k ∨ w = .cell k) ∧ y ∉ s.nm ∧ (o = false → y ∈ R)) ∧
      LkRoots st R s
  | _, _ => True

/-- A check-out through a borrow is through a borrowed parameter, bound by an
    `rbind` around it (`R`).  Asked of the redexes of a statement's spine. -/
def RbOK (st : Var → Option Slot) : List Var → Stmt → Prop
  | R, .seq a _ => RbOK st R a
  | R, .scope _ s => RbOK st R s
  | R, .scopeD _ _ s => RbOK st R s
  | R, .rbind p s => RbOK st (p :: R) s
  | R, .frozen _ s => RbOK st R s
  | R, .catchR _ _ s => RbOK st R s
  | R, .scopeL _ _ _ s => RbOK st R s
  | R, .withLock a _ _ => ∀ v, st a = some ⟨false, v⟩ → a ∈ R
  | _, _ => True

/-- A statement inside no frame has nothing to keep. -/
theorem lkRoots_nil (st : Var → Option Slot) : ∀ {s : Stmt} (R : List Var), s.lfr = [] → LkRoots st R s := by
  intro s
  induction s with
  | seq _ _ ih _ => exact ih
  | scope _ _ ih => exact ih
  | scopeD _ _ _ ih => exact ih
  | rbind _ _ ih => exact fun R => ih _
  | frozen _ _ ih => exact ih
  | catchR _ _ _ ih => exact ih
  | scopeL _ _ _ _ _ => intro _ h; cases h
  | _ => exact fun _ _ => trivial

/-- A frame's root, from the spine's. -/
theorem LkRoots.root {st : Var → Option Slot} : ∀ {s : Stmt} {R : List Var}, LkRoots st R s →
    ∀ {k : Nat} {u : Ty}, (k, u) ∈ s.lfr → ∃ y o w, st y = some ⟨o, some w⟩ ∧ (w = .lk k ∨ w = .cell k) := by
  intro s
  induction s with
  | seq _ _ ih _ => exact ih
  | scope _ _ ih => exact ih
  | scopeD _ _ _ ih => exact ih
  | rbind _ _ ih => exact ih
  | frozen _ _ ih => exact ih
  | catchR _ _ _ ih => exact ih
  | scopeL k0 t0 x0 b ih =>
    intro R hl k u hm
    simp only [Stmt.lfr, List.mem_cons] at hm
    rcases hm with hm | hm
    · cases hm
      obtain ⟨⟨y, o, w, hy, hw, _⟩, _⟩ := hl
      exact ⟨y, o, w, hy, hw⟩
    · exact ih hl.2 hm
  | _ => intro _ _ _ _ hm; simp [Stmt.lfr] at hm

/-! ### `RbOK` from the typing -/

/-- A borrowed parameter of a context `Weaker` than another is one of it. -/
theorem Weaker.rootb {Γ Γ' : Ctx} (hw : Weaker Γ Γ') {p : Var} {E' : Entry} (hp : Γ' p = some E')
    (hm : E'.mode = .rootb) : ∃ E, Γ p = some E ∧ E.mode = .rootb := by
  cases h : Γ p with
  | none => rw [(hw.1 p).1.1 h] at hp; cases hp
  | some E => exact ⟨E, rfl, ((hw.1 p).2 E E' h hp).mode ▸ hm⟩

/-- **A typed statement's check-outs through a borrow are through borrowed
    parameters bound around them**: every borrowed parameter of the context
    is bound on the spine or by an `rbind` gone through (`R`); a `scope`'s,
    a destructor frame's and a check-out's bindings are no borrowed
    parameters, so one on the spine is an `rbind`'s. -/
theorem rbOK_of {P : Prog} {m : Mem} : ∀ (s : Stmt) {Γ : Ctx} {F : List Var} {Δ : Ctx} (R : List Var),
    StmtT P Γ F s Δ → MInv m Γ →
    (∀ p E, Γ p = some E → E.mode = .rootb → p ∈ s.spine ∨ p ∈ R) → RbOK m.st R s := by
  intro s
  induction s with
  | seq a b iha _ =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.seq a b = s0 at ht hR
    induction ht with
    | seq _ ha _ _ _ => cases hs; exact iha R ha hi hR
    | sub hw _ _ ih =>
      exact ih (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | scope x b ih =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.scope x b = s0 at ht hR
    induction ht with
    | scope hx _ hb _ =>
      cases hs
      refine ih R hb hi fun p E hp hm => ?_
      obtain ⟨Ex, hEx, hmx⟩ := hx
      rcases hR p E hp hm with h | h
      · rcases List.mem_cons.mp h with h | h
        · subst h; rw [hp] at hEx; cases hEx; exact absurd hm hmx
        · exact .inl h
      · exact .inr h
    | sub hw _ _ ih0 =>
      exact ih0 (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | scopeD x f b ih =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.scopeD x f b = s0 at ht hR
    induction ht with
    | scopeD hx _ hb _ _ _ _ _ _ =>
      cases hs
      refine ih R hb hi fun p E hp hm => ?_
      obtain ⟨Ex, _, hEx, hmx, _⟩ := hx
      rcases hR p E hp hm with h | h
      · rcases List.mem_cons.mp h with h | h
        · subst h; rw [hp] at hEx; cases hEx; rw [hmx] at hm; cases hm
        · exact .inl h
      · exact .inr h
    | sub hw _ _ ih0 =>
      exact ih0 (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | rbind q b ih =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.rbind q b = s0 at ht hR
    induction ht with
    | rbind _ _ _ _ _ hb _ =>
      cases hs
      refine ih (q :: R) hb hi fun p E hp hm => ?_
      rcases hR p E hp hm with h | h
      · rcases List.mem_cons.mp h with h | h
        · exact .inr (h ▸ List.mem_cons_self)
        · exact .inl h
      · exact .inr (List.mem_cons_of_mem _ h)
    | sub hw _ _ ih0 =>
      exact ih0 (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | frozen z b ih =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.frozen z b = s0 at ht hR
    induction ht with
    | frozen hb _ => cases hs; exact ih R hb hi hR
    | sub hw _ _ ih0 =>
      exact ih0 (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | catchR x m0 b ih =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.catchR x m0 b = s0 at ht hR
    induction ht with
    | catchR _ hb _ _ _ _ => cases hs; exact ih R hb hi hR
    | sub hw _ _ ih0 =>
      exact ih0 (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | scopeL k t x b ih =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.scopeL k t x b = s0 at ht hR
    induction ht with
    | scopeL hx _ hb _ =>
      cases hs
      refine ih R hb hi fun p E hp hm => ?_
      obtain ⟨Ex, hEx, hmx, _⟩ := hx
      rcases hR p E hp hm with h | h
      · rcases List.mem_cons.mp h with h | h
        · subst h; rw [hp] at hEx; cases hEx; exact absurd hm hmx
        · exact .inl h
      · exact .inr h
    | sub hw _ _ ih0 =>
      exact ih0 (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | withLock a x b _ =>
    intro Γ F Δ R ht hi hR
    generalize hs : Stmt.withLock a x b = s0 at ht hR
    induction ht with
    | withLock _ _ _ h4 _ _ _ _ h9 _ =>
      cases hs
      intro v hv
      obtain ⟨sl, hsl, _, hown, _⟩ := hi.slot _ _ h4
      rw [hv] at hsl; cases hsl
      rcases hi.mode_cases h4 with hm | hm | hm
      · rw [hm] at hown; cases hown
      · rcases hR _ _ h4 hm with h | h
        · simp [Stmt.spine] at h
        · exact h
      · rw [hm] at h9; cases h9
    | sub hw _ _ ih0 =>
      exact ih0 (hi.weaker hw) hs (fun p E hp hm => by
        obtain ⟨E0, h0, hm0⟩ := Weaker.rootb hw hp hm; exact hR p E0 h0 hm0)
    | _ => cases hs
  | _ => intros; trivial

/-- **A thread's step keeps each frame's root**: the step of a frame's body
    leaves the root's slot, which the body does not name (`Step.keepSlot`),
    and a check-out's new frame has its own `a`, which `withLock`'s typing
    says its body does not name (a borrowed one an `rbind`'s, `RbOK`). -/
theorem Step.lkRoots {P : Prog} (hP : ProgOK P) {m m' : Mem} {s s' : Stmt} (h : Step P m s (.ok m' s'))
    (ht : Typed P s) (hck : CapShr P m.st m.nv s) (hnv : ∀ v, (m.st v).isSome = true → v < m.nv)
    {R : List Var} (hrb : RbOK m.st R s) (hl : LkRoots m.st R s) : LkRoots m'.st R s' := by
  revert ht hck hnv hrb hl
  generalize hr : Res.ok m' s' = r at h
  induction h generalizing m' s' R with
  | seqL _ ih => cases hr; intro ht hck hnv hrb hl; have h1 := ih rfl ht.seq hck hnv hrb hl; exact h1
  | scopeIn _ ih => cases hr; intro ht hck hnv hrb hl; have h1 := ih rfl ht.scope hck hnv hrb hl; exact h1
  | rbindIn _ ih => cases hr; intro ht hck hnv hrb hl; have h1 := ih rfl ht.rbind hck hnv hrb hl; exact h1
  | frozenIn _ ih => cases hr; intro ht hck hnv hrb hl; have h1 := ih rfl ht.frozen hck hnv hrb hl; exact h1
  | catchIn _ ih => cases hr; intro ht hck hnv hrb hl; have h1 := ih rfl ht.catchR hck hnv hrb hl; exact h1
  | scopeDIn _ ih => cases hr; intro ht hck hnv hrb hl; have h1 := ih rfl ht.scopeD hck hnv hrb hl; exact h1
  | @scopeLIn m1 k t x b b' hb ih =>
    cases hr; intro ht hck hnv hrb hl
    obtain ⟨⟨y, o, w, hy, hw, hyn, hyR⟩, hlb⟩ := hl
    refine ⟨?_, by have h1 := ih rfl ht.scopeL hck hnv hrb hlb; exact h1⟩
    have hlt : y < m.nv := hnv y (by rw [hy]; rfl)
    obtain ⟨h1, h2⟩ := Step.keepSlot hb hck hy ⟨k, hw⟩ hyn hlt
    exact ⟨y, o, w, h1.trans hy, hw, h2 _ _ rfl, hyR⟩
  | seqSkip =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ _ _; exact lkRoots_nil _ _ (lfr_src ht.seq_src)
  | letv _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ _ _; exact lkRoots_nil _ _ (by simp [Stmt.lfr, lfr_src ht.letv_src])
  | iteT _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ _ _; exact lkRoots_nil _ _ (lfr_src ht.ite_src.1)
  | iteF _ =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ _ _; exact lkRoots_nil _ _ (lfr_src ht.ite_src.2)
  | withElem _ _ _ _ _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ _ _
    exact lkRoots_nil _ _ (by simp [Stmt.lfr, lfr_src ht.withElem_src])
  | unpair _ _ _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ _ _
    exact lkRoots_nil _ _ (by simp [Stmt.lfr, lfr_src ht.unpair_src])
  | letd _ _ =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ _ _; exact lkRoots_nil _ _ (by simp [Stmt.lfr, lfr_src ht.letd_src])
  | letcall hf _ _ =>
    cases hr; intro _ _ _ _ _
    exact lkRoots_nil _ _ (by simp [Stmt.lfr, callStmt, lfr_callIn (body_src hP hf)])
  | letrec hf _ _ =>
    cases hr; intro _ _ _ _ _
    exact lkRoots_nil _ _ (by simp [Stmt.lfr, recStmt, lfr_callIn (body_src hP hf)])
  | callc _ _ hf _ _ =>
    cases hr; intro _ _ _ _ _; exact lkRoots_nil _ _ (by simp [Stmt.lfr, lfr_callIn (body_src hP hf)])
  | @withLock a x s0 k t v hla _ hx _ =>
    cases hr; rintro ⟨_, _, _, ht⟩ _ _ hrb _
    obtain ⟨o, ha⟩ := hla
    have hax : a ≠ x := fun e => by
      subst e; rcases ha with ha | ha <;> rw [hx] at ha <;> cases ha
    have hst : (({ m with blk := upd m.blk k (some ⟨t, .lock, none⟩) } : Mem).set x ⟨v.owns, some v⟩).st a =
        m.st a := by simp [upd_ne _ _ hax]
    have hn : a ∉ s0.nm := nm_vars _ _ ht.withLock_a
    refine ⟨?_, lkRoots_nil _ _ (lfr_src ht.withLock_src)⟩
    rcases ha with ha | ha
    · exact ⟨a, o, .lk k, hst.trans ha, .inl rfl, hn, fun ho => hrb _ (ho ▸ ha)⟩
    · exact ⟨a, o, .cell k, hst.trans ha, .inr rfl, hn, fun ho => hrb _ (ho ▸ ha)⟩
  | scopeLFail _ _ =>
    cases hr; intro _ _ _ _ hl
    obtain ⟨⟨y, o, w, hy, hw, _, hyR⟩, _⟩ := hl
    exact ⟨⟨y, o, w, hy, hw, by simp [Stmt.nm], hyR⟩, trivial⟩
  | _ => first
    | (cases hr; done)
    | (cases hr; intro _ _ _ _ _; exact lkRoots_nil _ _ (by simp [Stmt.lfr, handStmt, handStmtD]))

/-! ### Through a redex's context -/

theorem Redex.nm_sub {s r : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {y : Var} (hy : y ∉ s.nm) :
    y ∉ r.nm := by
  induction h with
  | here => exact hy
  | seq _ ih => exact ih (fun h => hy (List.mem_append_left _ h))
  | scope _ ih => exact ih (fun h => hy (List.mem_cons_of_mem _ h))
  | rbind _ ih => exact ih (fun h => hy (List.mem_cons_of_mem _ h))
  | frozen _ ih => exact ih hy
  | catchR _ ih => exact ih (fun h => hy (List.mem_cons_of_mem _ h))
  | scopeD _ ih => exact ih (fun h => hy (List.mem_cons_of_mem _ h))
  | scopeL _ ih => exact ih (fun h => hy (List.mem_cons_of_mem _ h))

theorem Redex.nm_mono {s r r' : Stmt} {K : Stmt → Stmt} (h : Redex s K r)
    (hr : ∀ y, y ∉ r.nm → y ∉ r'.nm) : ∀ y, y ∉ s.nm → y ∉ (K r').nm := by
  induction h with
  | here => exact hr
  | seq _ ih =>
    intro y hy
    simp only [Stmt.nm, List.mem_append, not_or] at hy ⊢
    exact ⟨ih hr y hy.1, hy.2⟩
  | scope _ ih | rbind _ ih | catchR _ ih | scopeD _ ih | scopeL _ ih =>
    intro y hy
    simp only [Stmt.nm, List.mem_cons, not_or] at hy ⊢
    exact ⟨hy.1, ih hr y hy.2⟩
  | frozen _ ih => exact ih hr

/-- A redex replaced by one inside no frame, that names no more and changes
    only slots the old one names, keeps every frame's root around it. -/
theorem Redex.lkRoots {s r r' : Stmt} {K : Stmt → Stmt} (h : Redex s K r) {st st' : Var → Option Slot}
    {R : List Var} (hl : LkRoots st R s) (hr' : r'.lfr = []) (hnm : ∀ y, y ∉ r.nm → y ∉ r'.nm)
    (hst : ∀ y, y ∉ r.nm → st' y = st y) : LkRoots st' R (K r') := by
  induction h generalizing R with
  | here => exact lkRoots_nil _ _ hr'
  | seq _ ih => exact ih hl hnm hst
  | scope _ ih => exact ih hl hnm hst
  | rbind _ ih => exact ih hl hnm hst
  | frozen _ ih => exact ih hl hnm hst
  | catchR _ ih => exact ih hl hnm hst
  | scopeD _ ih => exact ih hl hnm hst
  | scopeL hb ih =>
    obtain ⟨⟨y, o, w, hy, hw, hyn, hyR⟩, hlb⟩ := hl
    exact ⟨⟨y, o, w, (hst y (hb.nm_sub hyn)).trans hy, hw, hb.nm_mono hnm y hyn, hyR⟩, ih hlb hnm hst⟩

/-- The root of a frame on a statement's spine: a borrowed one is bound by
    an `rbind` around the frame. -/
theorem Redex.lkRoot {s : Stmt} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (h : Redex s K (.scopeL k u x b)) {st : Var → Option Slot} {R : List Var} (hl : LkRoots st R s) :
    ∃ y o w, st y = some ⟨o, some w⟩ ∧ (w = .lk k ∨ w = .cell k) ∧ y ∉ b.nm ∧
      (o = false → y ∈ R ∨ ∃ K' s', Redex s K' (.rbind y s')) := by
  generalize hr : Stmt.scopeL k u x b = r at h
  induction h generalizing R with
  | here =>
    subst hr
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := hl.1
    exact ⟨y, o, w, hy, hw, hyn, fun ho => .inl (hyR ho)⟩
  | seq _ ih =>
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := ih hl hr
    refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
    rcases hyR ho with h | ⟨K', s', h⟩
    · exact .inl h
    · exact .inr ⟨_, _, .seq h⟩
  | scope _ ih =>
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := ih hl hr
    refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
    rcases hyR ho with h | ⟨K', s', h⟩
    · exact .inl h
    · exact .inr ⟨_, _, .scope h⟩
  | @rbind p s0 r0 K0 _ ih =>
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := ih hl hr
    refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
    rcases hyR ho with h | ⟨K', s', h⟩
    · rcases List.mem_cons.mp h with h | h
      · subst h; exact .inr ⟨_, _, .here⟩
      · exact .inl h
    · exact .inr ⟨_, _, .rbind h⟩
  | frozen _ ih =>
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := ih hl hr
    refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
    rcases hyR ho with h | ⟨K', s', h⟩
    · exact .inl h
    · exact .inr ⟨_, _, .frozen h⟩
  | catchR _ ih =>
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := ih hl hr
    refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
    rcases hyR ho with h | ⟨K', s', h⟩
    · exact .inl h
    · exact .inr ⟨_, _, .catchR h⟩
  | scopeD _ ih =>
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := ih hl hr
    refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
    rcases hyR ho with h | ⟨K', s', h⟩
    · exact .inl h
    · exact .inr ⟨_, _, .scopeD h⟩
  | scopeL _ ih =>
    obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := ih hl.2 hr
    refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
    rcases hyR ho with h | ⟨K', s', h⟩
    · exact .inl h
    · exact .inr ⟨_, _, .scopeL h⟩

theorem MoveArgs.st_ne {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (h : MoveArgs st as vs st') {y : Var} (hy : y ∉ as) : st' y = st y := by
  induction h with
  | nil => rfl
  | cons _ _ ih =>
    simp only [List.mem_cons, not_or] at hy
    rw [ih hy.2, upd_ne _ _ hy.1]

/-! ### The invariant over the configuration -/

/-- **Agora #808: the check-outs' roots.**  Every frame on a thread has a
    slot of its thread holding a share of its block that its body does not
    name (`LkRoots`), and its block is there. -/
structure RootInv (C : Cfg) : Prop where
  roots : ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → LkRoots t.st [] t.s
  live  : ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → ∀ (k : Nat) (u : Ty), (k, u) ∈ t.s.lfr →
    C.blk k ≠ none

theorem BlkLe.ne_none {B B' : Nat → Option Blk} (h : BlkLe B B') {k : Nat} (hk : B k ≠ none) :
    B' k ≠ none := by
  cases hb : B k with
  | none => exact absurd hb hk
  | some bl =>
    obtain ⟨bl', h', _⟩ := h k bl hb
    rw [h']; exact fun h => nomatch h

/-- **A thread's step keeps the invariant** (before the sweep): the stepping
    thread's frames keep their roots (`Step.lkRoots`) and the other threads'
    slots are theirs; no block is removed, and a new frame's block is the
    one the step checked out. -/
theorem RootInv.put {P : Prog} (hP : ProgOK P) {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps)
    (h : RootInv C) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} (hi : C.ths[i]? = some t)
    (hst : Step P (C.view t) t.s (.ok m' s')) : RootInv (C.put i m' s') := by
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto, _⟩ := hc.ok i t a hi ha
  have hta : TypedAt P (ownView C t a) t.s := TypedAt.of_threadOK hto
  have htyp : Typed P t.s := by obtain ⟨Γ, F, Δ, ht, _⟩ := hta; exact ⟨Γ, F, Δ, ht⟩
  obtain ⟨Γ, F, Δ, ht0, hinv, hcd, _, hcl⟩ := hto
  have hck : CapShr P (C.view t).st (C.view t).nv t.s := TypedAt.capShr hcd hta
  have hrb : RbOK (C.view t).st [] t.s :=
    rbOK_of (m := ownView C t a) t.s [] ht0 hinv.toMInv fun p E hp _ => .inl (hcl p (by rw [hp]; rfl))
  have hnv : ∀ v, ((C.view t).st v).isSome = true → v < (C.view t).nv := hinv.nvSt
  have hE := Step.lfr hP hst htyp
  have hg : Grows (C.view t) m' := Step.grows hst
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hths : ∀ (j : Nat) (tj : Thread), (C.put i m' s').ths[j]? = some tj →
      (j = i ∧ tj = ⟨m'.st, m'.nv, s'⟩) ∨ (j ≠ i ∧ C.ths[j]? = some tj) := by
    intro j tj hj
    simp only [Cfg.put] at hj
    rw [list_set_get hilen] at hj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; exact .inl ⟨hij.symm, rfl⟩
    · rw [ite_eq_right hij] at hj; exact .inr ⟨Ne.symm hij, hj⟩
  refine ⟨fun j tj hj => ?_, fun j tj hj k u hm => ?_⟩
  · rcases hths j tj hj with ⟨-, rfl⟩ | ⟨_, hj⟩
    · exact Step.lkRoots hP hst htyp hck hnv hrb (h.roots i t hi)
    · exact h.roots j tj hj
  · show m'.blk k ≠ none
    rcases hths j tj hj with ⟨-, rfl⟩ | ⟨_, hj⟩
    · rcases hE with hpre | ⟨k0, u0, v0, he, _, h2⟩
      · exact BlkLe.ne_none hg.blk (h.live i t hi k u (hpre.subset hm))
      · rw [he, List.mem_append, List.mem_singleton] at hm
        rcases hm with hm | hm
        · exact BlkLe.ne_none hg.blk (h.live i t hi k u hm)
        · cases hm; rw [h2]; exact fun h => nomatch h
    · exact BlkLe.ne_none hg.blk (h.live j tj hj k u hm)

/-- **The marking sweep keeps every frame's block**: the frame's root is a
    slot's value, a root of the sweep, which refers to the block. -/
theorem RootInv.sweepD {C : Cfg} (h : RootInv C) : RootInv C.sweepD := by
  refine ⟨h.roots, fun j tj hj k u hm => ?_⟩
  obtain ⟨y, o, w, hy, hw⟩ := (h.roots j tj hj).root hm
  have hR : C.roots w := .inl ⟨j, tj, hj, y, o, hy⟩
  have hrf : Refers C.blk w k := by
    rcases hw with rfl | rfl
    · exact .inl (.inl ⟨none, Sub.refl _⟩)
    · exact .inl (.inr (Sub.refl _))
  have hreach : Reached (RootsD C.roots C.blk) C.blk k :=
    Reached.roots (fun v hv => .inl (.inl hv)) (.root hR hrf)
  show sweepBlkD C.roots C.blk k ≠ none
  unfold sweepBlkD
  rw [ite_eq_left hreach]
  exact h.live j tj hj k u hm

/-- ... and so do the reaps after it. -/
theorem RootInv.settle {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {i : Nat} {C C' : Cfg}
    (h : CSettle P i C C') (hc : ∃ ps, CParts P C ps) (hl : RootInv C) : RootInv C' := by
  induction h with
  | done _ => exact hl
  | reap hi hs _ _ ih =>
    obtain ⟨ps, hc⟩ := hc
    exact ih (hc.putD hP hPc (restrictLemma _) hi hs) (hl.put hP hc hi hs).sweepD

/-- **A spawn keeps the invariant**: the spawner's call becomes its result's
    scope (its arguments, which the call names, moved out), inside the same
    frames; the new thread is inside none. -/
theorem RootInv.spawn {P : Prog} (hP : ProgOK P) {C : Cfg} {ps : List (Nat → Bool)} (hc : CParts P C ps)
    (h : RootInv C) {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var} {k : Stmt}
    {fn : Fn} {vs : List Val} {st' : Var → Option Slot} (hi : C.ths[i]? = some t)
    (hK : Redex t.s K (.letcall x f args k)) (hf : P[f]? = some fn) (hmv : MoveArgs t.st args vs st')
    (stn : Var → Option Slot) :
    RootInv { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                    [⟨stn, fn.nvars, wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] } := by
  obtain ⟨a, ha⟩ := part_of hc.len hi
  obtain ⟨hto, _⟩ := hc.ok i t a hi ha
  obtain ⟨Γ, F, Δ, ht, hinv, _⟩ := hto
  obtain ⟨Γ', F', Δ', ht', _⟩ := hK.typed Γ F Δ ht hinv
  have hks : k.src = true := by simpa [Stmt.src] using letcall_src ht'
  have hlfr : (K (.scope x k)).lfr = t.s.lfr := by
    rw [hK.eq]; exact hK.lfr_eq (by simp [Stmt.lfr, lfr_src hks])
  have hroot : LkRoots (upd st' x (some ⟨false, some (.int 0)⟩)) [] (K (.scope x k)) := by
    refine hK.lkRoots (h.roots i t hi) (by simp [Stmt.lfr, lfr_src hks]) ?_ ?_
    · intro y hy
      simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hy ⊢
      exact ⟨hy.1, hy.2.2⟩
    · intro y hy
      simp only [Stmt.nm, List.cons_append, List.mem_cons, List.mem_append, not_or] at hy
      rw [upd_ne _ _ hy.1, hmv.st_ne hy.2.1]
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hnew : (wrapParams fn.params 0 0 (.scope fn.params.length fn.body)).lfr = [] := by
    simp [lfr_wrap, Stmt.lfr, lfr_src (body_src hP hf)]
  refine ⟨fun j tj hj => ?_, fun j tj hj k' u hm => ?_⟩ <;> simp only at hj <;>
    rw [get_set_append hilen] at hj
  · by_cases hjl : j < C.ths.length
    · rw [ite_eq_left hjl] at hj
      by_cases hij : i = j
      · rw [ite_eq_left hij] at hj; cases hj; exact hroot
      · rw [ite_eq_right hij] at hj; exact h.roots j tj hj
    · rw [ite_eq_right hjl] at hj
      by_cases hje : j = C.ths.length
      · rw [ite_eq_left hje] at hj; cases hj; exact lkRoots_nil _ _ hnew
      · rw [ite_eq_right hje] at hj; cases hj
  · by_cases hjl : j < C.ths.length
    · rw [ite_eq_left hjl] at hj
      by_cases hij : i = j
      · rw [ite_eq_left hij] at hj; cases hj; rw [hlfr] at hm; exact h.live i t hi k' u hm
      · rw [ite_eq_right hij] at hj; exact h.live j tj hj k' u hm
    · rw [ite_eq_right hjl] at hj
      by_cases hje : j = C.ths.length
      · rw [ite_eq_left hje] at hj; cases hj; rw [hnew] at hm; cases hm
      · rw [ite_eq_right hje] at hj; cases hj

/-- ... and so does a spawn whose crossing check fails: a panic before the
    call, nothing moved. -/
theorem RootInv.spawnFail {C : Cfg} (h : RootInv C) {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat}
    {args : List Var} {k : Stmt} (hi : C.ths[i]? = some t) (hK : Redex t.s K (.letcall x f args k)) :
    RootInv { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ } := by
  have hlfr : (K (.seq .panic (.letcall x f args k))).lfr = t.s.lfr := by
    rw [hK.eq]; exact hK.lfr_eq rfl
  have hroot : LkRoots t.st [] (K (.seq .panic (.letcall x f args k))) :=
    hK.lkRoots (h.roots i t hi) rfl (fun y hy => by simpa [Stmt.nm] using hy) (fun _ _ => rfl)
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  refine ⟨fun j tj hj => ?_, fun j tj hj k' u hm => ?_⟩ <;> simp only at hj <;>
    rw [list_set_get hilen] at hj
  · by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; exact hroot
    · rw [ite_eq_right hij] at hj; exact h.roots j tj hj
  · by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; rw [hlfr] at hm; exact h.live i t hi k' u hm
    · rw [ite_eq_right hij] at hj; exact h.live j tj hj k' u hm

/-- **Every step of the configuration keeps the invariant.** -/
theorem RootInv.tstep {P : Prog} {spawn : Nat → Bool} (hP : ProgOK P) (hPc : ProgCodes P) {C C' : Cfg}
    (hc : CInv P C) (h : RootInv C) (hs : TStep P spawn C C') : RootInv C' := by
  obtain ⟨ps, hcp, _⟩ := hc
  cases hs with
  | thread hi _ hst hse =>
    exact RootInv.settle hP hPc hse (hcp.putD hP hPc (restrictLemma _) hi hst) (h.put hP hcp hi hst).sweepD
  | spawn hi hK _ hf _ hmv _ => exact h.spawn hP hcp hi hK hf hmv _
  | spawnFail hi hK _ _ _ _ _ => exact h.spawnFail hi hK

/-- The start: one thread, of source code, inside no frame. -/
theorem RootInv.start {G : Globs} {s : Stmt} (hs : s.src = true) (nv : Nat) : RootInv (Cfg.start G s nv) := by
  have hnil : ∀ (j : Nat) (t : Thread), (Cfg.start G s nv).ths[j]? = some t → t.s.lfr = [] := by
    intro j t hj
    cases j with
    | zero => simp [Cfg.start] at hj; subst hj; exact lfr_src hs
    | succ j => simp [Cfg.start] at hj
  exact ⟨fun j t hj => lkRoots_nil _ _ (hnil j t hj), fun j t hj k u hm => by rw [hnil j t hj] at hm; cases hm⟩

/-- **Agora #808: every configuration a typed start reaches keeps the
    check-outs' roots.** -/
theorem reach_rootInv {P : Prog} {spawn : Nat → Bool} {G : Globs} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C) : RootInv C := by
  have key : ∀ C1 C2, Reach P spawn C1 C2 → Reach P spawn (Cfg.start G s nv) C1 → RootInv C1 → RootInv C2 := by
    intro C1 C2 h
    induction h with
    | refl => exact fun _ hl => hl
    | step hst _ ih =>
      exact fun h0 hl => ih (h0.snoc hst) (hl.tstep hP hPc (reach_inv hP hPc hSp hG ht hs hsc hv h0).1 hst)
  exact key _ _ hr .refl (RootInv.start hs nv)

/-! ### What a reached configuration's frames say -/

section reach
variable {P : Prog} {spawn : Nat → Bool} {G : Globs} {s0 : Stmt} {Δ0 : Ctx} {nv : Nat}

/-- **The check-out's root share outlives its body** (Agora #808): in a
    reached configuration, a thread inside a check-out of block `k` holds a
    share of block `k` (a lock's or a cell's) in a slot the frame's body does
    not name; a borrowed one (the slot owns nothing) is a borrowed
    parameter's, bound by an `rbind` on the thread's spine. -/
theorem reach_frame_root (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b)) :
    ∃ y o w, th.st y = some ⟨o, some w⟩ ∧ (w = .lk k ∨ w = .cell k) ∧ y ∉ b.nm ∧
      (o = false → ∃ K' s', Redex th.s K' (.rbind y s')) := by
  obtain ⟨y, o, w, hy, hw, hyn, hyR⟩ := hK.lkRoot ((reach_rootInv hP hPc hSp hG ht hs hsc hv hr).roots i th hi)
  refine ⟨y, o, w, hy, hw, hyn, fun ho => ?_⟩
  rcases hyR ho with h | h
  · cases h
  · exact h

/-- **A frame's block is never removed while the frame is out** (Agora
    #808): the sweep keeps what the root's share refers to. -/
theorem reach_frame_live (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn) (hG : GlobsOK P G)
    (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b)) : C.blk k ≠ none :=
  (reach_rootInv hP hPc hSp hG ht hs hsc hv hr).live i th hi k u (hK.lfr_mem rfl)

/-- **A frame's block, in a reached configuration**: for a payload that
    holds a destructor value, checked out, `⟨u, .lock, none⟩`
    (`reach_frame_out` with the block there, `reach_frame_live`). -/
theorem reach_frame_checked_out (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (hG : GlobsOK P G) (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b)) (hu : u.dtorFree = false) :
    C.blk k = some ⟨u, .lock, none⟩ := by
  rcases (reach_frame_out hP hPc hSp hG ht hs hsc hv hr hi hK hu).2 with h0 | h0
  · exact absurd h0 (reach_frame_live hP hPc hSp hG ht hs hsc hv hr hi hK)
  · exact h0

/-- **The check-out's end gives the value back, in a reached configuration**
    (Agora #808): `scopeL_typed_end_gives_back` with the block's state
    discharged: the frame's typing names `x` an owner of a `u`, and the block
    is there (`reach_frame_live`) and checked out (`reach_frame_out`), so
    every step of the frame's end is the give-back.  (`Step.scopeLFail` and
    the code-less `Release.drop` are not taken.) -/
theorem reach_scopeL_end_gives_back (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (hG : GlobsOK P G) (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x .skip))
    (hd : u.holdsDtor = true) (hna : u.hasArc = false) (hvf : u.holdsView = false)
    {r : Res} (h : Step P (C.view th) (.scopeL k u x .skip) r) :
    ∃ v, th.st x = some ⟨true, some v⟩ ∧
      r = .ok ({ C.view th with blk := upd C.blk k (some ⟨u, .lock, some v⟩) }.remove x) .skip := by
  obtain ⟨ps, hcp, _⟩ := (reach_inv hP hPc hSp hG ht hs hsc hv hr).1
  obtain ⟨a, ha⟩ := part_of hcp.len hi
  obtain ⟨hto, _⟩ := hcp.ok i th a hi ha
  obtain ⟨Γ, F, Δ, hth, hinv, _⟩ := hto
  obtain ⟨Γ', F', Δ', ht', hinv'⟩ := hK.typed Γ F Δ hth hinv
  obtain ⟨w, hx, hw⟩ := LockDtorWitness.scopeL_end_owns ht' hinv'.toMInv hd
  have hk : (C.view th).blk k = some ⟨u, .lock, none⟩ :=
    reach_frame_checked_out hP hPc hSp hG ht hs hsc hv hr hi hK (dtorFree_of_holdsDtor hd)
  have hno : ¬ Orphan (C.view th) := fun ho => Reach.noOrphan hr hG.noOrphan ho
  exact ⟨w, hx, LockDtorWitness.scopeL_end_gives_back (m := C.view th) hx hw hna hvf hk hno h⟩

/-- **A panic through the check-out gives the value back, in a reached
    configuration** (Agora #808): `scopeL_typed_panic` with the block's state
    discharged: the block is there (`reach_frame_live`) and checked out, and
    the body's unwinding leaves it so (its frame is the block's only one,
    `Step.stay`): at the panic point `x` owns a `u`, given back into the
    block, or nothing, the release freeing nothing. -/
theorem reach_scopeL_panic (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (hG : GlobsOK P G) (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b))
    (hd : u.holdsDtor = true) (hna : u.hasArc = false) (hvf : u.holdsView = false)
    {m2 : Mem} (h : Step P (C.view th) (.scopeL k u x b) (.panic m2)) :
    ∃ m1, Step P (C.view th) b (.panic m1) ∧
      ((∃ v, m1.st x = some ⟨true, some v⟩ ∧ WFv u v ∧
          m2 = ({ m1 with blk := upd m1.blk k (some ⟨u, .lock, some v⟩) }.remove x)) ∨
        (m1.st x = some ⟨true, none⟩ ∧ m2 = m1.remove x)) := by
  have hl := reach_lockInv hP hPc hSp hG ht hs hsc hv hr
  obtain ⟨ps, hcp, _⟩ := (reach_inv hP hPc hSp hG ht hs hsc hv hr).1
  obtain ⟨a, ha⟩ := part_of hcp.len hi
  obtain ⟨hto, _⟩ := hcp.ok i th a hi ha
  have hrf : RF (C.view th) th.s := RF.congr (m := ownView C th a) (m' := C.view th) rfl rfl
    (TypedAt.of_threadOK hto).rf
  obtain ⟨Γ, F, Δ, hth, hinv, _⟩ := hto
  obtain ⟨Γ', F', Δ', ht', hinv'⟩ := hK.typed Γ F Δ hth hinv
  have hk : (C.view th).blk k = some ⟨u, .lock, none⟩ :=
    reach_frame_checked_out hP hPc hSp hG ht hs hsc hv hr hi hK (dtorFree_of_holdsDtor hd)
  obtain ⟨m1, hb, hres⟩ := scopeL_typed_panic_of (m := C.view th) ht' hinv' rfl hd hna hvf h
  -- the body's unwinding leaves the block checked out: the frame is its only one
  have hk1 : m1.blk k = some ⟨u, .lock, none⟩ := by
    have hout : Out (C.view th) k := .inr ⟨u, hk, dtorFree_of_holdsDtor hd⟩
    rcases Step.stay hb (hK.rf hrf) hout with h1 | ⟨hkb, _, _⟩
    · exact h1.trans hk
    · have h2 := hK.count_two rfl hkb
      rw [hl.nd i th hi k u (hK.lfr_mem rfl) (dtorFree_of_holdsDtor hd)] at h2
      omega
  refine ⟨m1, hb, ?_⟩
  rcases hres with ⟨v, hx, hw, hput⟩ | hnone
  · exact .inl ⟨v, hx, hw, hput hk1⟩
  · exact .inr hnone

theorem _root_.A2.StmtT.rbind_live {P : Prog} {m : Mem} {Γ Δ : Ctx} {F : List Var} {y : Var} {s : Stmt}
    (ht : StmtT P Γ F (.rbind y s) Δ) (hi : MInv m Γ) :
    ∃ Γ' E, MInv m Γ' ∧ Γ' y = some E ∧ E.live = true := by
  generalize hs : Stmt.rbind y s = s0 at ht
  induction ht with
  | rbind h1 _ h3 => cases hs; exact ⟨_, _, hi, h1, h3⟩
  | sub hw _ _ ih => exact ih (hi.weaker hw) hs
  | _ => cases hs

/-- **A3.5: a thread inside a check-out holds a share of its block**: the
    check-out is through a lock share the thread holds, or the thread holds
    an owner's share of cell `k` (`CellOp`'s second case: the root share of a
    cell's check-out, through an owner, or, through a borrowed parameter, its
    caller's owner, `MInv.cell_owned`). -/
theorem reach_frame_cell_owner (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (hG : GlobsOK P G) (ht : StmtT P (fun _ => none) [] s0 Δ0) (hs : s0.src = true) (hsc : s0.codesOK P)
    (hv : ∀ v ∈ s0.vars, v < nv) {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C)
    {i : Nat} {th : Thread} {K : Stmt → Stmt} {k : Nat} {u : Ty} {x : Var} {b : Stmt}
    (hi : C.ths[i]? = some th) (hK : Redex th.s K (.scopeL k u x b)) :
    (∃ y o, th.st y = some ⟨o, some (.lk k)⟩) ∨
      ∃ y v, th.st y = some ⟨true, some v⟩ ∧ Sub (.cell k) v := by
  obtain ⟨y, o, w, hy, hw, _, hyR⟩ := reach_frame_root hP hPc hSp hG ht hs hsc hv hr hi hK
  rcases hw with rfl | rfl
  · exact .inl ⟨y, o, hy⟩
  · right
    cases o with
    | true => exact ⟨y, _, hy, Sub.refl _⟩
    | false =>
      obtain ⟨K', s', hK'⟩ := hyR rfl
      obtain ⟨ps, hcp, _⟩ := (reach_inv hP hPc hSp hG ht hs hsc hv hr).1
      obtain ⟨a, ha⟩ := part_of hcp.len hi
      obtain ⟨hto, _⟩ := hcp.ok i th a hi ha
      obtain ⟨Γ, F, Δ, hth, hinv, _⟩ := hto
      obtain ⟨Γ', F', Δ', ht', hinv'⟩ := hK'.typed Γ F Δ hth hinv
      obtain ⟨Γ'', E, hi'', hE, hl⟩ := ht'.rbind_live hinv'.toMInv
      exact hi''.cell_owned (m := ownView C th a) hE hl hy (Sub.refl _)

end reach

end A3
