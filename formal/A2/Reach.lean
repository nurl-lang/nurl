module

public import A2.Codes
public import A2.SweepD

@[expose] public section

/-! A2 — the functions a run can name (AGORA-1013).

A function of the program runs only where something names it: a call
(`letcall f`), a `recover f` (`letrec f`), a destructor frame (`letd x f`,
`scopeD x f`, and the destructor of a block's type that a reap hands to
one, `Ty.Reaps`), a call's result frame (`Fn.resTy`'s destructor,
`resFrame`), or a package's code (`Rhs.pack fs`, `Val.pkg fs`), which a
call through the package (`callc`, `callcE`) runs.  This file gives a set
`A` of function indices those names stay inside, through every step: a
configuration all of whose names are in `A` (`Stmt.fnsIn`, `MemFns`) steps
to one again when every function of `A` names only functions of `A`
(`ProgFns`).  So a run from such a configuration consults the program only
at indices in `A`: a program that agrees with it there (`Agree`) has the
same runs (`steps_agree`).  A function outside `A` is never entered, and
replacing its code, by any code, changes nothing a run does.

This is what a certificate's `N.cap` rests on: `A` is the closure of the
entry's names (`C.reachB`), decided by the kernel for the program, and
what a function outside it would do (a foreign call, a write, a
connection) cannot happen.

The file is a layer over A2: it reads the semantics and no rule or
theorem of A1–A3 or C changes.  It follows `Codes.lean`, whose invariant
(every package names checked code) is the same shape: there the codes must
implement their interfaces, here they must be in `A`. -/

namespace A2

/-! ### Values, blocks and the store -/

/-- Every package inside `v` names code in `A`. -/
def PkgFns (A : Nat → Prop) (v : Val) : Prop :=
  ∀ fs te ms e cs, Sub (.pkg fs te ms e cs) v → ∀ f ∈ fs, A f

/-- The destructor a block of each type would hand to a reap (`Ty.Reaps`)
    is in `A`. -/
def DeadFns (A : Nat → Prop) (B : Nat → Option Blk) : Prop :=
  ∀ k bl, B k = some bl → ∀ f u, bl.ty.Reaps f u → A f

/-- The blocks: the packages in what each owns and in what its holders read,
    and the destructors of their types. -/
def BlkFns (A : Nat → Prop) (B : Nat → Option Blk) : Prop :=
  (∀ k bl, B k = some bl → PkgFns A bl.tree ∧ PkgFns A bl.rd) ∧ DeadFns A B

/-- The store names only functions in `A`: its slots' packages, and its
    blocks'. -/
def MemFns (A : Nat → Prop) (m : Mem) : Prop :=
  (∀ x o V, m.st x = some ⟨o, some V⟩ → PkgFns A V) ∧ BlkFns A m.blk

variable {A : Nat → Prop}

theorem PkgFns.sub {u v : Val} (h : PkgFns A v) (hs : Sub u v) : PkgFns A u :=
  fun fs te ms e cs hp => h fs te ms e cs (hp.trans hs)

theorem pkgFns_leaf {v : Val} (hv : ∀ fs te ms e cs, v ≠ .pkg fs te ms e cs)
    (hc : ∀ e, ¬ Child e v) : PkgFns A v := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', _⟩
  · exact absurd h.symm (hv fs te ms e cs)
  · exact absurd hc' (hc e')

theorem pkgFns_int (A : Nat → Prop) (n : Nat) : PkgFns A (.int n) :=
  pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
theorem pkgFns_href (A : Nat → Prop) (c : Nat) : PkgFns A (.href c) :=
  pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
theorem pkgFns_view (A : Nat → Prop) (d o l : Nat) : PkgFns A (.view d o l) :=
  pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
/-- A share carries no package a step reads (its payload is ghost). -/
theorem pkgFns_share {v : Val} (hv : ∀ fs te ms e cs, v ≠ .pkg fs te ms e cs)
    (hc : ∀ e, ¬ Child e v) : PkgFns A v := pkgFns_leaf hv hc

/-- A value built from parts: its packages are theirs, and its own. -/
theorem pkgFns_of_children {v : Val}
    (hself : ∀ fs te ms e cs, v = .pkg fs te ms e cs → ∀ f ∈ fs, A f)
    (hc : ∀ e, Child e v → PkgFns A e) : PkgFns A v := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', hs'⟩
  · exact hself fs te ms e cs h.symm
  · exact hc e' hc' fs te ms e cs hs'

theorem PkgFns.child {e v : Val} (h : PkgFns A v) (hc : Child e v) : PkgFns A e :=
  h.sub (hc.sub (Sub.refl _))

/-- A package's own code. -/
theorem PkgFns.code {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val} {cs : List (Var × PMode × Ty)}
    (h : PkgFns A (.pkg fs te ms e cs)) : ∀ f ∈ fs, A f := h fs te ms e cs (Sub.refl _)

/-- Lending a value keeps its packages' code. -/
theorem pkgFns_lend : ∀ {v : Val}, PkgFns A v → PkgFns A (lendOf v)
  | .int _, h => h
  | .href _, h => h
  | .view _ _ _, h => h
  | .arc _ _, h => h
  | .lk _, h => h
  | .cell _, h => h
  | .node _ c _ _, _ => pkgFns_href A c
  | .pair v w, h => by
    refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact pkgFns_lend (h.child Child.fst)
    | snd => exact pkgFns_lend (h.child Child.snd)
  | .inl v, h => by
    refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | inl => exact pkgFns_lend (h.child Child.inl)
  | .inr v, h => by
    refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | inr => exact pkgFns_lend (h.child Child.inr)
  | .pkg fs te ms v cs, h => by
    refine pkgFns_of_children (fun fs' te' ms' e cs' he => ?_) (fun e hc => ?_)
    · cases he; exact h.code
    · cases hc with
      | pkg => exact pkgFns_lend (h.child Child.pkg)

theorem MemFns.slot {m : Mem} (h : MemFns A m) {x : Var} {o : Bool} {V : Val}
    (hx : m.st x = some ⟨o, some V⟩) : PkgFns A V := h.1 x o V hx

theorem MemFns.blk {m : Mem} (h : MemFns A m) : BlkFns A m.blk := h.2

theorem MemFns.dead {m : Mem} (h : MemFns A m) : DeadFns A m.blk := h.2.2

theorem MemFns.set {m : Mem} (h : MemFns A m) {x : Var} {o : Bool} {v : Option Val}
    (hv : ∀ V, v = some V → PkgFns A V) : MemFns A (m.set x ⟨o, v⟩) := by
  refine ⟨fun y o' V hy => ?_, h.2⟩
  by_cases hyx : y = x
  · subst hyx; simp [Mem.set] at hy; obtain ⟨_, rfl⟩ := hy; exact hv V rfl
  · simp [Mem.set, upd_ne _ _ hyx] at hy; exact h.slot hy

theorem MemFns.remove {m : Mem} (h : MemFns A m) (x : Var) : MemFns A (m.remove x) := by
  refine ⟨fun y o' V hy => ?_, h.2⟩
  by_cases hyx : y = x
  · subst hyx; simp [Mem.remove] at hy
  · simp [Mem.remove, upd_ne _ _ hyx] at hy; exact h.slot hy

/-- The slots of one store, the blocks of another. -/
theorem MemFns.withBlk {m m' : Mem} (h : MemFns A m) (hst : m'.st = m.st)
    (hb : BlkFns A m'.blk) : MemFns A m' :=
  ⟨fun y o V hy => h.slot (by rw [← hst]; exact hy), hb⟩

theorem MemFns.of_st {m m' : Mem} (h : MemFns A m) (hst : m'.st = m.st)
    (hb : m'.blk = m.blk := by rfl) : MemFns A m' :=
  h.withBlk hst (by rw [hb]; exact h.blk)

/-- A block whose payload's packages name code in `A`, and the destructor of
    whose type is in `A`. -/
theorem BlkFns.upd {B : Nat → Option Blk} (h : BlkFns A B) {k : Nat} {bl : Blk}
    (hbl : PkgFns A bl.tree ∧ PkgFns A bl.rd)
    (hd : ∀ f u, bl.ty.Reaps f u → A f := by reaps_none) :
    BlkFns A (upd B k (some bl)) := by
  refine ⟨fun k' bl' hk' => ?_, fun k' bl' hk' => ?_⟩
  · by_cases hkk : k' = k
    · subst hkk; rw [upd_same] at hk'; cases hk'; exact hbl
    · rw [upd_ne _ _ hkk] at hk'; exact h.1 k' bl' hk'
  · by_cases hkk : k' = k
    · subst hkk; rw [upd_same] at hk'; cases hk'; exact hd
    · rw [upd_ne _ _ hkk] at hk'; exact h.2 k' bl' hk'

/-- A block put where one of the same type was keeps its destructor. -/
theorem BlkFns.updSame {B : Nat → Option Blk} (h : BlkFns A B) {k : Nat} {bl0 bl : Blk}
    (hbl : PkgFns A bl.tree ∧ PkgFns A bl.rd) (hk : B k = some bl0) (hty : bl.ty = bl0.ty := by rfl) :
    BlkFns A (A2.upd B k (some bl)) :=
  BlkFns.upd h hbl (fun f u hr => h.2 k bl0 hk f u (hty ▸ hr))

theorem blkFns_dead {t : Ty} {p : Option Val} (hp : ∀ v, p = some v → PkgFns A v) :
    PkgFns A (Blk.tree ⟨t, .dead, p⟩) ∧ PkgFns A (Blk.rd ⟨t, .dead, p⟩) := by
  refine ⟨?_, pkgFns_int A 0⟩
  cases p with
  | none => exact pkgFns_int A 0
  | some v => exact hp v rfl

theorem blkFns_lock {t : Ty} {p : Option Val} (hp : ∀ v, p = some v → PkgFns A v) :
    PkgFns A (Blk.tree ⟨t, .lock, p⟩) ∧ PkgFns A (Blk.rd ⟨t, .lock, p⟩) := by
  refine ⟨?_, pkgFns_int A 0⟩
  cases p with
  | none => exact pkgFns_int A 0
  | some v => exact hp v rfl

theorem blkFns_arc {t : Ty} {v : Val} (hv : PkgFns A v) :
    PkgFns A (Blk.tree ⟨t, .arc, some v⟩) ∧ PkgFns A (Blk.rd ⟨t, .arc, some v⟩) := ⟨hv, hv⟩

theorem blkFns_view {t : Ty} {v : Val} (hv : PkgFns A v) :
    PkgFns A (Blk.tree ⟨t, .view, some v⟩) ∧ PkgFns A (Blk.rd ⟨t, .view, some v⟩) := ⟨pkgFns_int A 0, hv⟩

theorem MemFns.nodeAt {m : Mem} (h : MemFns A m) {c : Nat} {n : Val} (hn : NodeAt m c n) :
    PkgFns A n := by
  rcases hn with ⟨x, t, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.slot hx).sub hs
  · exact (h.blk.1 k bl hk).2.sub hs

theorem MemFns.dataAt {m : Mem} (h : MemFns A m) {d : Nat} {n : Val} (hn : DataAt m d n) :
    PkgFns A n := by
  rcases hn with ⟨x, t, hx, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.slot hx).sub hs
  · exact (h.blk.1 k bl hk).2.sub hs

theorem MemFns.vecOf {m : Mem} (h : MemFns A m) {y : Var} {t : Ty} {c d : Nat}
    {es : List Val} (hv : VecOf m y t c d es) : PkgFns A (.node t c d es) := by
  obtain ⟨_, _, hv | ⟨_, hn⟩⟩ := hv
  · exact h.slot hv
  · exact h.nodeAt hn

theorem pkgFns_elem {t : Ty} {c d : Nat} {es : List Val} (h : PkgFns A (.node t c d es))
    {e : Val} (he : e ∈ es) : PkgFns A e := h.child (Child.elem he)

/-- A node built of values whose packages are in `A`. -/
theorem pkgFns_node {t : Ty} {c d : Nat} {es : List Val} (h : ∀ e ∈ es, PkgFns A e) :
    PkgFns A (.node t c d es) := by
  refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
  cases hc with | elem he => exact h e he

/-- Rewriting a tree at one node keeps its packages in `A`, when the new
    node's are. -/
theorem Repl.pkgFns_new {n n' T T' : Val} (hr : Repl n n' T T') (hT : PkgFns A T)
    (hn' : PkgFns A n') : PkgFns A T' := by
  induction hr with
  | here => exact hn'
  | @elem t c d pre post e e' _ ih =>
    refine pkgFns_node (fun x hx => ?_)
    rcases List.mem_append.mp hx with hx | hx
    · exact hT.child (Child.elem (List.mem_append_left _ hx))
    · rcases List.mem_cons.mp hx with rfl | hx
      · exact ih (hT.child (Child.elem (List.mem_append_right _ (List.mem_cons_self ..))))
      · exact hT.child (Child.elem (List.mem_append_right _ (List.mem_cons_of_mem _ hx)))
  | fst _ ih =>
    refine pkgFns_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | fst => exact ih (hT.child Child.fst)
    | snd => exact hT.child Child.snd
  | snd _ ih =>
    refine pkgFns_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | fst => exact hT.child Child.fst
    | snd => exact ih (hT.child Child.snd)
  | inl _ ih =>
    refine pkgFns_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | inl => exact ih (hT.child Child.inl)
  | inr _ ih =>
    refine pkgFns_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | inr => exact ih (hT.child Child.inr)
  | pkg _ ih =>
    refine pkgFns_of_children (fun fs te ms e cs h => ?_) (fun x hc => ?_)
    · cases h; exact hT.code
    · cases hc with
      | pkg => exact ih (hT.child Child.pkg)

theorem TakeVal.fns {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1)
    (h : MemFns A m) : PkgFns A v ∧ MemFns A m1 := by
  cases ht with
  | own hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | bor hv => exact ⟨h.slot hv, h⟩

/-! ### Statements -/

/-- The functions a right-hand side names: a package's code, and the
    destructor of the type of a block it makes. -/
def Rhs.fnsIn (A : Nat → Prop) : Rhs → Prop
  | .pack fs _ _ _ _ => ∀ f ∈ fs, A f
  | .arcNew t _ => ∀ f u, t.Reaps f u → A f
  | .lockNew t _ => ∀ f u, t.Reaps f u → A f
  | .cellNew t _ => ∀ f u, t.Reaps f u → A f
  | _ => True

/-- The functions a statement names: its calls, its `recover`s, its
    destructor frames, a lock scope's payload type's destructor, and what its
    right-hand sides name. -/
def Stmt.fnsIn (A : Nat → Prop) : Stmt → Prop
  | .seq a b => a.fnsIn A ∧ b.fnsIn A
  | .letv _ r s => r.fnsIn A ∧ s.fnsIn A
  | .letcall _ f _ s => A f ∧ s.fnsIn A
  | .assign _ r => r.fnsIn A
  | .ite _ a b => a.fnsIn A ∧ b.fnsIn A
  | .while _ s => s.fnsIn A
  | .scope _ s => s.fnsIn A
  | .rbind _ s => s.fnsIn A
  | .frozen _ s => s.fnsIn A
  | .letrec _ f s => A f ∧ s.fnsIn A
  | .catchR _ _ s => s.fnsIn A
  | .unpair _ _ _ s => s.fnsIn A
  | .callc _ _ _ _ _ s => s.fnsIn A
  | .letd _ f r s => A f ∧ r.fnsIn A ∧ s.fnsIn A
  | .scopeD _ f s => A f ∧ s.fnsIn A
  | .withLock _ _ s => s.fnsIn A
  | .scopeL _ t _ s => (∀ f u, t.Reaps f u → A f) ∧ s.fnsIn A
  | .withElem _ _ _ s => s.fnsIn A
  | .callcE _ _ _ _ s => s.fnsIn A
  | .block s => s.fnsIn A
  | .loop s => s.fnsIn A
  | .takeB _ _ _ s => s.fnsIn A
  -- (each constructor written out: a wildcard's equation lemma negates all
  -- the others, and every certificate that imports this module loads it)
  | .skip | .push _ _ | .free _ | .panic | .edit _ _ _ | .insert _ _ _ | .exit _ => True

/-- A function names only functions in `A`: its body, and the destructor of
    its result type (its call's result frame, `resFrame`). -/
def Fn.fnsIn (A : Nat → Prop) (fn : Fn) : Prop :=
  fn.body.fnsIn A ∧ ∀ g, fn.resTy.dhead = some g → A g

/-- **`A` is closed under the program's names**: every function of `A` the
    program has names only functions of `A`. -/
def ProgFns (A : Nat → Prop) (P : Prog) : Prop :=
  ∀ f fn, P[f]? = some fn → A f → fn.fnsIn A

/-- Two programs agree on `A`: the same function at every index of `A`. -/
def Agree (A : Nat → Prop) (P P' : Prog) : Prop := ∀ f, A f → P'[f]? = P[f]?

theorem Rhs.fnsIn_rename (ρ : Var → Var) (r : Rhs) : (r.rename ρ).fnsIn A ↔ r.fnsIn A := by
  cases r <;> exact Iff.rfl

theorem Stmt.fnsIn_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).fnsIn A ↔ s.fnsIn A := by
  induction s with
  | seq a b iha ihb => simp only [Stmt.rename, Stmt.fnsIn, iha, ihb]
  | letv x r s ih => simp only [Stmt.rename, Stmt.fnsIn, ih, Rhs.fnsIn_rename]
  | letd x f r s ih => simp only [Stmt.rename, Stmt.fnsIn, ih, Rhs.fnsIn_rename]
  | assign x r => simp only [Stmt.rename, Stmt.fnsIn, Rhs.fnsIn_rename]
  | ite c a b iha ihb => simp only [Stmt.rename, Stmt.fnsIn, iha, ihb]
  | letcall _ _ _ _ ih | «while» _ _ ih | scope _ _ ih | rbind _ _ ih | frozen _ _ ih | letrec _ _ _ ih
  | catchR _ _ _ ih | unpair _ _ _ _ ih | callc _ _ _ _ _ _ ih | scopeD _ _ _ ih | withLock _ _ _ ih
  | scopeL _ _ _ _ ih | withElem _ _ _ _ ih | callcE _ _ _ _ _ ih | block _ ih | loop _ ih
  | takeB _ _ _ _ ih =>
    simp only [Stmt.rename, Stmt.fnsIn, ih]
  | _ => exact Iff.rfl

/-- The frames an exit leaves are the statement's own. -/
theorem ExitAt.fnsIn {s e : Stmt} {n : Nat} (h : ExitAt s n e) (hs : s.fnsIn A) : e.fnsIn A := by
  induction h with
  | exit => trivial
  | seq _ ih => exact ih hs.1
  | scope _ ih => exact ih hs
  | scopeD _ ih => exact ⟨hs.1, ih hs.2⟩
  | block _ ih => exact ih hs

theorem wrapParams_fns {s : Stmt} (hs : s.fnsIn A) :
    ∀ (ps : List (PMode × Ty)) (base i : Nat), (wrapParams ps base i s).fnsIn A := by
  intro ps
  induction ps with
  | nil => intro _ _; exact hs
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp only [wrapParams, Stmt.fnsIn] <;> exact ih base (i + 1)

/-- The inside of a call of a function that names only `A`. -/
theorem callIn_fns {fn : Fn} (hfn : fn.fnsIn A) (args : List Var) (base : Nat) (x : Var) :
    (callIn fn args base x).fnsIn A := by
  have hb : (fn.body.rename (callRen fn.params args base)).fnsIn A :=
    (Stmt.fnsIn_rename _ _).mpr hfn.1
  have hin : (Stmt.seq (.frozen ((List.range base).filter
      (fun v => !(inoutArgs fn.params args).contains v))
        (wrapParams fn.params base 0 (fn.body.rename (callRen fn.params args base))))
      (.assign x (.var (base + fn.params.length)))).fnsIn A :=
    ⟨wrapParams_fns hb _ _ _, trivial⟩
  unfold callIn resFrame
  split
  · next g _ hg => exact ⟨hfn.2 g hg, hin⟩
  · exact hin

/-- A lock scope's end gives `x`'s value, with its packages, back to the
    block, or drops it. -/
theorem Release.fns {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (hrl : Release m k t x m')
    (hm : MemFns A m) : MemFns A m' := by
  cases hrl with
  | put hx _ hk =>
    refine MemFns.remove ?_ _
    exact hm.withBlk rfl (hm.blk.updSame (blkFns_lock fun _ e => by cases e; exact hm.slot hx) hk.1)
  | drop _ _ _ => exact (hm.of_st rfl).remove _

/-! ### Right-hand sides and calls -/

theorem EvalR.fns {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (he : EvalR m r (.ok v o m1))
    (h : MemFns A m) (hr : r.fnsIn A) : PkgFns A v ∧ MemFns A m1 := by
  have hB := h.blk.1
  cases he with
  | expr _ => exact ⟨pkgFns_int A _, h⟩
  | new => exact ⟨pkgFns_node (fun e he => by simp at he), h.of_st rfl⟩
  | moveOwn hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | take hv =>
    refine ⟨h.slot hv, (h.of_st rfl).set (fun V e => ?_)⟩
    cases e; exact pkgFns_node (fun e he => by simp at he)
  | copy hv => exact ⟨h.slot hv, h⟩
  | borrowOwn _ => exact ⟨pkgFns_href A _, h⟩
  | borrowBor hv => exact ⟨h.slot hv, h⟩
  | «at» hn hv _ => exact ⟨pkgFns_lend (pkgFns_elem (h.vecOf hv) (List.getElem_mem hn)), h⟩
  | view _ => exact ⟨pkgFns_view A _ _ _, h⟩
  | @slit n _ =>
    have hn : PkgFns A (.node .int m.nid (m.nid + 1) (List.replicate n (.int 0))) :=
      pkgFns_node (fun e he => by rw [List.eq_of_mem_replicate he]; exact pkgFns_int A 0)
    exact ⟨pkgFns_view A _ _ _, h.withBlk rfl (h.blk.upd ⟨hn, hn⟩)⟩
  | sat hn _ _ _ _ hda => exact ⟨pkgFns_lend (pkgFns_elem (h.dataAt hda) (List.getElem_mem hn)), h⟩
  | pop hv _ _ =>
    have hT := h.slot hv
    refine ⟨pkgFns_elem hT (by simp), h.set (fun V e => ?_)⟩
    cases e; exact pkgFns_node (fun e he => pkgFns_elem hT (by simp [he]))
  | remove hn hv _ _ _ =>
    have hT := h.slot hv
    refine ⟨pkgFns_elem hT (List.getElem_mem hn), h.set (fun V e => ?_)⟩
    cases e; exact pkgFns_node (fun e he => pkgFns_elem hT (List.mem_of_mem_eraseIdx he))
  | pair h1 h2 =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    obtain ⟨hw, hm2⟩ := h2.fns hm1
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm2⟩
    cases hc with
    | fst => exact hv
    | snd => exact hw
  | fst hv => exact ⟨pkgFns_lend ((h.slot hv).child Child.fst), h⟩
  | snd hv => exact ⟨pkgFns_lend ((h.slot hv).child Child.snd), h⟩
  | inl h1 =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inl => exact hv
  | inr h1 =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inr => exact hv
  | getl hv => exact ⟨pkgFns_lend ((h.slot hv).child Child.inl), h⟩
  | getr hv => exact ⟨pkgFns_lend ((h.slot hv).child Child.inr), h⟩
  | takel hv => exact ⟨(h.slot hv).child Child.inl, h.set (fun _ e => by cases e)⟩
  | taker hv => exact ⟨(h.slot hv).child Child.inr, h.set (fun _ e => by cases e)⟩
  | pack h1 =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    refine ⟨pkgFns_of_children (fun fs te ms e cs he => ?_) (fun e hc => ?_), hm1⟩
    · cases he; exact hr
    · cases hc with | pkg => exact hv
  | arcNew h1 _ =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    exact ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      hm1.withBlk rfl (hm1.blk.upd (blkFns_arc hv) hr)⟩
  | lockNew h1 _ =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    exact ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      hm1.withBlk rfl (hm1.blk.upd (blkFns_lock fun _ e => by cases e; exact hv) hr)⟩
  | arcClone _ => exact ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | lockClone _ => exact ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | cellNew h1 _ =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    exact ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      hm1.withBlk rfl (hm1.blk.upd (blkFns_lock fun _ e => by cases e; exact hv) hr)⟩
  | cellClone _ => exact ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | glob _ hf =>
    rcases hf with ⟨_, _, _, _, rfl, _⟩ | ⟨_, _, _, _, rfl, _⟩ <;>
      exact ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h), h⟩
  | rwRead _ hk _ =>
    have hp := (hB _ _ hk).1
    refine ⟨pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h),
      h.withBlk rfl (h.blk.upd (blkFns_view ?_))⟩
    refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    | snd => exact hp
  | rwTryRead _ hk _ =>
    have hp := (hB _ _ hk).1
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_),
      h.withBlk rfl (h.blk.upd (blkFns_view ?_))⟩
    · cases hc with
      | inr => exact pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact pkgFns_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
    | snd => exact hp
  | rwTryReadNone _ _ | rwTryWriteNone _ _ =>
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inl => exact pkgFns_int A _
  | rwTryWrite _ _ _ =>
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inr => exact pkgFns_int A _
  | atomic _ _ _ _ =>
    exact ⟨pkgFns_int A _, h.withBlk rfl (h.blk.upd (blkFns_lock fun _ e => by cases e; exact pkgFns_int A _))⟩
  | @chanSend _ _ _ k _ u c d es _ _ _ h1 hk _ _ _ =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    have hp : PkgFns A (.pair (.node u c d es) (.int 0)) := (hm1.blk.1 _ _ hk).1
    refine ⟨pkgFns_int A _, hm1.withBlk rfl (hm1.blk.updSame (blkFns_lock fun _ e => ?_) hk)⟩
    cases e
    refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst =>
      refine pkgFns_node (fun e he => ?_)
      rcases List.mem_append.mp he with he | he
      · exact pkgFns_elem (hp.child Child.fst) he
      · simp at he; subst he; exact hv
    | snd => exact pkgFns_int A _
  | @chanSendClosed _ _ _ k t s q f v m1 _ h1 hk ht _ _ =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    refine ⟨pkgFns_int A _, hm1.withBlk rfl (hm1.blk.upd (blkFns_lock fun _ e => by cases e; exact hv)
      (fun f' u' hr => ?_))⟩
    exact hm1.blk.2 k _ hk f' u' (.chan ht hr)
  | @chanRecv _ _ _ _ _ u c d f v es _ hk _ _ =>
    have hp : PkgFns A (.pair (.node u c d (v :: es)) (.int f)) := (hB _ _ hk).1
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_),
      h.withBlk rfl (h.blk.updSame (blkFns_lock fun _ e => ?_) hk)⟩
    · cases hc with
      | inr => exact pkgFns_elem (hp.child Child.fst) (List.mem_cons_self ..)
    · cases e
      refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
      cases hc with
      | fst => exact pkgFns_node (fun e he => pkgFns_elem (hp.child Child.fst) (List.mem_cons_of_mem _ he))
      | snd => exact pkgFns_int A _
  | chanRecvNone _ _ _ _ =>
    refine ⟨pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h⟩
    cases hc with
    | inl => exact pkgFns_int A _
  | lockTake _ hk _ =>
    exact ⟨(hB _ _ hk).1, h.withBlk rfl (h.blk.updSame (blkFns_lock fun _ e => by cases e) hk)⟩
  | lockRestore _ h1 hk =>
    obtain ⟨hv, hm1⟩ := h1.fns h
    exact ⟨pkgFns_int A _, hm1.withBlk rfl (hm1.blk.updSame (blkFns_lock fun _ e => by cases e; exact hv) hk)⟩
  | @chanClose _ _ k _ q _ _ hk _ =>
    have hp : PkgFns A (.pair q (.int _)) := (hB _ _ hk).1
    refine ⟨pkgFns_int A _, h.withBlk rfl (h.blk.updSame (blkFns_lock fun _ e => ?_) hk)⟩
    cases e
    refine pkgFns_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact hp.child Child.fst
    | snd => exact pkgFns_int A _
  | arcGet _ hk => exact ⟨pkgFns_lend (hB _ _ hk).2, h⟩

theorem BindParams.fns {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (hb : BindParams m ps as base i m') (h : MemFns A m) : MemFns A m' := by
  induction hb with
  | nil => exact h
  | @inp m _ _ _ a _ _ _ sl v ha hl _ ih =>
    refine ih (h.set (fun V e => ?_))
    cases e
    obtain ⟨o, val⟩ := sl
    cases o <;> cases val <;> simp [lendSlot] at hl
    · subst hl; exact h.slot ha
    · subst hl; exact pkgFns_lend (h.slot ha)
  | sink ha _ ih => exact ih ((h.set (fun _ e => by cases e)).set (fun V e => by cases e; exact h.slot ha))
  | inout _ ih => exact ih h

/-! ### Every step keeps the names in `A` -/

/-- **Every step names only functions of `A`**, when every function of `A`
    does: what it leaves to run is part of the statement, the body of a
    function the statement named, a package's code or a block type's
    destructor, and what it stores is, or is made from, what memory held or
    the statement named. -/
theorem fns_step {P : Prog} (hP : ProgFns A P) {m : Mem} {s : Stmt} {r : Res} (hst : Step P m s r) :
    MemFns A m → s.fnsIn A →
      (∀ m' s', r = .ok m' s' → MemFns A m' ∧ s'.fnsIn A) ∧ (∀ m', r = .panic m' → MemFns A m') := by
  induction hst with
  | seqSkip =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs.2⟩
  | seqL _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hs.1).1 _ _ rfl; exact ⟨h1, h2, hs.2⟩
  | seqP _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (ih hm hs.1).2 _ rfl
  | letv _ he =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.fns hm hs.1
    exact ⟨hm1.set (fun V e => by cases e; exact hv), hs.2⟩
  | letvP _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | letcall hf _ hb =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(((hb.fns hm).set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      callIn_fns (hP _ _ hf hs.1) _ _ _, hs.2⟩
  | scopeSkip _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(hm.of_st rfl).remove _, trivial⟩
  | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | blockIn _ ih | catchIn _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hs).1 _ _ rfl; exact ⟨h1, h2⟩
  | scopeLIn _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hs.2).1 _ _ rfl; exact ⟨h1, hs.1, h2⟩
  | scopeDIn _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hs.2).1 _ _ rfl; exact ⟨h1, hs.1, h2⟩
  | scopeP _ _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (((ih hm hs).2 _ rfl).of_st rfl).remove _
  | scopeLP _ hrl ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hrl.fns ((ih hm hs.2).2 _ rfl)
  | withLock _ hk _ =>
    -- the payload checked out goes to `x`; the lock scope keeps the block's type
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    refine ⟨MemFns.set ?_ (fun V e => by cases e; exact (hm.blk.1 _ _ hk).1),
      fun f u hr => hm.dead _ _ hk f u hr, hs⟩
    exact hm.withBlk rfl (hm.blk.updSame (blkFns_lock fun _ e => by cases e) hk)
  | @reap r0 k0 n f u p _ hk _ =>
    -- the payload goes to the fresh binding, and its frame runs the block
    -- type's destructor
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    refine ⟨MemFns.withBlk (m := m.set m.nv ⟨true, some p⟩)
      (MemFns.set hm (fun V e => by cases e; exact (hm.blk.1 _ _ hk).1)) rfl
      (hm.blk.upd (blkFns_dead fun _ e => by cases e)
        (fun f' u' hr => hm.dead k0 _ hk f' u' hr)), ⟨hm.dead k0 _ hk f u .nest, trivial⟩, hs⟩
  | scopeLSkip hrl _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hrl.fns hm, trivial⟩
  | scopeLFail _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs.1, trivial⟩
  | rbindSkip _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.remove _, trivial⟩
  | rbindP _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ((ih hm hs).2 _ rfl).remove _
  | frozenSkip | catchSkip =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, trivial⟩
  | frozenP _ ih | blockP _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (ih hm hs).2 _ rfl
  | blockSkip =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, trivial⟩
  | blockExit he =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, he.fnsIn hs⟩
  | loop =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs, hs⟩
  | catchP _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((ih hm hs).2 _ rfl).set (fun V e => by cases e; exact pkgFns_int A 1), trivial⟩
  | assign _ he _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.fns hm hs
    exact ⟨(hm1.of_st rfl).set (fun V e => by cases e; exact hv), trivial⟩
  | assignP _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | iteT _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs.1⟩
  | iteF _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, hs.2⟩
  | «while» =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, ⟨hs, hs⟩, trivial⟩
  | push ht hx _ _ | pushRealloc ht hx _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.fns hm
    have hT := hm1.slot hx
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine pkgFns_node (fun e he => ?_)
    rcases List.mem_append.mp he with he | he
    · exact pkgFns_elem hT he
    · simp at he; subst he; exact hv
  | withElem hn hv _ _ _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hv
    refine ⟨(hm.set (fun V e => ?_)).set (fun V e => ?_), hs, trivial⟩
    · cases e
      refine pkgFns_node (fun e he => ?_)
      rcases List.mem_append.mp he with he | he
      · exact pkgFns_elem hT (List.mem_of_mem_take he)
      · exact pkgFns_elem hT (List.mem_of_mem_drop he)
    · cases e; exact pkgFns_elem hT (List.getElem_mem hn)
  | withElemOOB _ _ _ _ | takeBOOB _ _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | insert _ ht hx _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.fns hm
    have hT := hm1.slot hx
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine pkgFns_node (fun e he => ?_)
    rcases List.mem_append.mp he with he | he
    · exact pkgFns_elem hT (List.mem_of_mem_take he)
    · rcases List.mem_cons.mp he with he | he
      · subst he; exact hv
      · exact pkgFns_elem hT (List.mem_of_mem_drop he)
  | free _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(hm.of_st rfl).set (fun _ e => by cases e), trivial⟩
  | editPush ht hn hr | editPushRealloc ht hn hr =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.fns hm
    have hT := hm1.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine hr.pkgFns_new hT (pkgFns_node (fun e he => ?_))
    rcases List.mem_append.mp he with he | he
    · exact pkgFns_elem hn0 he
    · simp at he; subst he; exact hv
  | editTrunc _ hn _ hr =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    exact hr.pkgFns_new hT (pkgFns_node (fun e he => pkgFns_elem hn0 (List.mem_of_mem_take he)))
  | takeB hlt _ hn _ hr =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨((hm.of_st rfl).set (fun V e => ?_)).set (fun V e => ?_), hs⟩
    · cases e
      exact hr.pkgFns_new hT (pkgFns_node (fun e he => pkgFns_elem hn0 (List.mem_of_mem_eraseIdx he)))
    · cases e; exact pkgFns_elem hn0 (List.getElem_mem hlt)
  | editSet _ _ ht hn _ hr =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.fns hm
    have hT := hm1.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine hr.pkgFns_new hT (pkgFns_node (fun e he => ?_))
    rcases List.mem_or_eq_of_mem_set he with he | he
    · exact pkgFns_elem hn0 he
    · subst he; exact hv
  | editSetOOB _ ht _ _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(ht.fns hm).2.of_st rfl, trivial⟩
  | panic =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | waitPanic _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | letrec hf _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((hm.set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      ⟨callIn_fns (hP _ _ hf hs.1) _ _ _, hs.2⟩⟩
  | unpair hy _ _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hy
    exact ⟨((hm.set (fun _ e => by cases e)).set (fun V e => by cases e; exact hT.child Child.fst)).set
      (fun V e => by cases e; exact hT.child Child.snd), hs⟩
  | letd _ he =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.fns hm hs.2.1
    exact ⟨hm1.set (fun V e => by cases e; exact hv), hs.1, hs.2.2⟩
  | letdP _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | scopeDEnd _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.of_st rfl, hs.1, trivial⟩
  | scopeDDrain _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.of_st rfl, hs.1, hs.1, trivial, trivial⟩
  | scopeDEmpty _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, trivial⟩
  | scopeDPDrain _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(ih hm hs.2).2 _ rfl, ⟨hs.1, trivial⟩, trivial⟩
  | scopeDMoved _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.remove _, trivial⟩
  | scopeDP _ _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((ih hm hs.2).2 _ rfl).of_st rfl, ⟨hs.1, trivial⟩, trivial⟩
  | scopeLPD _ _ ht _ _ ih =>
    -- the check-out's frame becomes `x`'s destructor frame: the destructor
    -- of the lock scope's payload type
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(ih hm hs.2).2 _ rfl, ⟨hs.1 _ _ (by rw [ht]; exact .nest), trivial⟩, trivial⟩
  | scopeDPMoved _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ((ih hm hs.2).2 _ rfl).remove _
  | callc hslot hj hf _ hb =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hslot
    have hme : MemFns A (envMem _ _) :=
      (hm.set (fun V e => by cases e; exact pkgFns_lend (hT.child Child.pkg))).of_st rfl
    exact ⟨(((hb.fns hme).set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      callIn_fns (hP _ _ hf (hT.code _ (List.mem_of_getElem? hj))) _ _ _, hs⟩
  | callcE hc hj _ _ =>
    -- the environment moves to its binding; the code is the package's, and
    -- the package it goes back into names the code it came from
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hc
    exact ⟨(((hm.set (fun _ e => by cases e)).set (fun V e => by cases e; exact hT.child Child.pkg)).set
      (fun _ e => by cases e)).of_st rfl,
      ⟨⟨hT.code _ (List.mem_of_getElem? hj), trivial⟩, hT.code⟩, hs⟩
  | callcD hc hj _ _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hc
    exact ⟨(((hm.set (fun _ e => by cases e)).set (fun V e => by cases e; exact hT.child Child.pkg)).set
      (fun _ e => by cases e)).of_st rfl, ⟨hT.code _ (List.mem_of_getElem? hj), trivial⟩, hs⟩

/-! ### The sweeps -/

/-- The marking sweep keeps or marks blocks: their packages and their types'
    destructors stay.  A3's sweep of the shared blocks is this one too. -/
theorem BlkFns.sweepBlkD {R : Val → Prop} {B : Nat → Option Blk} (h : BlkFns A B) :
    BlkFns A (sweepBlkD R B) := by
  refine ⟨fun k bl hk => ?_, fun k bl hk => ?_⟩
  · rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, hp, rfl⟩
    · exact h.1 k bl hk0
    · refine ⟨?_, by rw [Blk.mark_rd]; exact pkgFns_int A 0⟩
      rw [hp.tree hk0]; exact (h.1 k bl0 hk0).1
  · rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, hp, rfl⟩
    · exact h.2 k bl hk0
    · exact h.2 k bl0 hk0

/-- The marking sweep changes no slot. -/
theorem MemFns.sweepDR {R : Val → Prop} {m : Mem} (h : MemFns A m) : MemFns A (m.sweepDR R) :=
  ⟨h.1, h.blk.sweepBlkD⟩

theorem MemFns.sweepD {m : Mem} (h : MemFns A m) : MemFns A m.sweepD := h.sweepDR

theorem MemFns.sweepR {R : Val → Prop} {m : Mem} (h : MemFns A m) : MemFns A (m.sweepR R) :=
  ⟨h.1, fun k bl hk => h.blk.1 k bl (Mem.sweepR_blk.mp hk).1,
    fun k bl hk => h.dead k bl (Mem.sweepR_blk.mp hk).1⟩

theorem MemFns.sweep {m : Mem} (h : MemFns A m) : MemFns A m.sweep := h.sweepR

/-- The thread whose step the marking sweep ended reaps: each reap is a
    step, so the names stay in `A`. -/
theorem Settle.fns {P : Prog} (hP : ProgFns A P) {m m2 : Mem} {s s2 : Stmt} (h : Settle P m s m2 s2)
    (hm : MemFns A m) (hs : s.fnsIn A) : MemFns A m2 ∧ s2.fnsIn A := by
  induction h with
  | done _ => exact ⟨hm, hs⟩
  | reap hst _ _ ih =>
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    exact ih hm1.sweepD hs1

/-- **A run from a configuration that names only `A` names only `A`**, at
    every configuration it reaches. -/
theorem Steps.fns {P : Prog} (hP : ProgFns A P) {m : Mem} {s : Stmt} {r : Res} (h : Steps P m s r)
    (hm : MemFns A m) (hs : s.fnsIn A) :
    (∀ m' s', r = .ok m' s' → MemFns A m' ∧ s'.fnsIn A) ∧ (∀ m', r = .panic m' → MemFns A m') := by
  induction h with
  | refl => exact ⟨fun _ _ e => (by cases e; exact ⟨hm, hs⟩), fun _ e => (by cases e)⟩
  | step hst hse _ ih =>
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    obtain ⟨hm2, hs2⟩ := hse.fns hP hm1.sweepD hs1
    exact ih hm2 hs2
  | panic hst =>
    exact ⟨fun _ _ e => (by cases e), fun _ e => (by cases e; exact ((fns_step hP hst hm hs).2 _ rfl).sweep)⟩

/-! ### The program outside `A` is never read -/

/-- **A step reads the program only at indices in `A`**: a program that agrees
    with it there takes the same step. -/
theorem step_agree {P P' : Prog} (hag : Agree A P P') {m : Mem} {s : Stmt} {r : Res}
    (hst : Step P m s r) : MemFns A m → s.fnsIn A → Step P' m s r := by
  induction hst with
  | seqSkip => intro _ _; exact .seqSkip
  | seqL _ ih => intro hm hs; exact .seqL (ih hm hs.1)
  | seqP _ ih => intro hm hs; exact .seqP (ih hm hs.1)
  | letv h1 h2 => intro _ _; exact .letv h1 h2
  | letvP h1 => intro _ _; exact .letvP h1
  | letcall hf h1 h2 => intro _ hs; exact .letcall ((hag _ hs.1).trans hf) h1 h2
  | scopeSkip h1 h2 => intro _ _; exact .scopeSkip h1 h2
  | scopeIn _ ih => intro hm hs; exact .scopeIn (ih hm hs)
  | scopeP _ h1 h2 ih => intro hm hs; exact .scopeP (ih hm hs) h1 h2
  | rbindSkip h1 => intro _ _; exact .rbindSkip h1
  | rbindIn _ ih => intro hm hs; exact .rbindIn (ih hm hs)
  | rbindP _ h1 ih => intro hm hs; exact .rbindP (ih hm hs) h1
  | frozenSkip => intro _ _; exact .frozenSkip
  | frozenIn _ ih => intro hm hs; exact .frozenIn (ih hm hs)
  | frozenP _ ih => intro hm hs; exact .frozenP (ih hm hs)
  | assign h1 h2 h3 h4 => intro _ _; exact .assign h1 h2 h3 h4
  | assignP h1 => intro _ _; exact .assignP h1
  | iteT h1 h2 => intro _ _; exact .iteT h1 h2
  | iteF h1 => intro _ _; exact .iteF h1
  | «while» => intro _ _; exact .while
  | push h1 h2 h3 h4 => intro _ _; exact .push h1 h2 h3 h4
  | pushRealloc h1 h2 h3 h4 => intro _ _; exact .pushRealloc h1 h2 h3 h4
  | editPush h1 h2 h3 => intro _ _; exact .editPush h1 h2 h3
  | editPushRealloc h1 h2 h3 => intro _ _; exact .editPushRealloc h1 h2 h3
  | editTrunc h1 h2 h3 h4 => intro _ _; exact .editTrunc h1 h2 h3 h4
  | editSet h h1 h2 h3 h4 h5 => intro _ _; exact .editSet h h1 h2 h3 h4 h5
  | editSetOOB h1 h2 h3 h4 h5 => intro _ _; exact .editSetOOB h1 h2 h3 h4 h5
  | insert h1 h2 h3 h4 h5 => intro _ _; exact .insert h1 h2 h3 h4 h5
  | withElem h h1 h2 h3 h4 h5 => intro _ _; exact .withElem h h1 h2 h3 h4 h5
  | withElemOOB h1 h2 h3 h4 => intro _ _; exact .withElemOOB h1 h2 h3 h4
  | takeB h h1 h2 h3 h4 => intro _ _; exact .takeB h h1 h2 h3 h4
  | takeBOOB h1 h2 h3 => intro _ _; exact .takeBOOB h1 h2 h3
  | free h1 h2 => intro _ _; exact .free h1 h2
  | panic => intro _ _; exact .panic
  | waitPanic h1 => intro _ _; exact .waitPanic h1
  | letrec hf h1 h2 => intro _ hs; exact .letrec ((hag _ hs.1).trans hf) h1 h2
  | catchIn _ ih => intro hm hs; exact .catchIn (ih hm hs)
  | catchSkip => intro _ _; exact .catchSkip
  | unpair h1 h2 h3 h4 => intro _ _; exact .unpair h1 h2 h3 h4
  | callc hc hj hf h1 h2 =>
    intro hm _
    exact .callc hc hj ((hag _ ((hm.slot hc).code _ (List.mem_of_getElem? hj))).trans hf) h1 h2
  | callcE hc hj hf h1 h2 =>
    intro hm _
    exact .callcE hc hj ((hag _ ((hm.slot hc).code _ (List.mem_of_getElem? hj))).trans hf) h1 h2
  | callcD hc hj hf h1 h2 =>
    intro hm _
    exact .callcD hc hj ((hag _ ((hm.slot hc).code _ (List.mem_of_getElem? hj))).trans hf) h1 h2
  | catchP _ h1 ih => intro hm hs; exact .catchP (ih hm hs) h1
  | letd h1 h2 => intro _ _; exact .letd h1 h2
  | letdP h1 => intro _ _; exact .letdP h1
  | scopeDIn _ ih => intro hm hs; exact .scopeDIn (ih hm hs.2)
  | scopeDEnd h1 h2 => intro _ _; exact .scopeDEnd h1 h2
  | scopeDMoved h1 => intro _ _; exact .scopeDMoved h1
  | scopeDDrain h1 => intro _ _; exact .scopeDDrain h1
  | scopeDEmpty h1 => intro _ _; exact .scopeDEmpty h1
  | scopeDP _ h1 h2 ih => intro hm hs; exact .scopeDP (ih hm hs.2) h1 h2
  | scopeDPDrain _ h1 ih => intro hm hs; exact .scopeDPDrain (ih hm hs.2) h1
  | scopeDPMoved _ h1 ih => intro hm hs; exact .scopeDPMoved (ih hm hs.2) h1
  | withLock h1 h2 h3 h4 => intro _ _; exact .withLock h1 h2 h3 h4
  | scopeLIn _ ih => intro hm hs; exact .scopeLIn (ih hm hs.2)
  | scopeLSkip h1 h2 => intro _ _; exact .scopeLSkip h1 h2
  | scopeLFail h1 h2 => intro _ _; exact .scopeLFail h1 h2
  | scopeLP _ h1 ih => intro hm hs; exact .scopeLP (ih hm hs.2) h1
  | scopeLPD _ h1 h2 h3 h4 ih => intro hm hs; exact .scopeLPD (ih hm hs.2) h1 h2 h3 h4
  | reap h1 h2 h3 => intro _ _; exact .reap h1 h2 h3
  | blockIn _ ih => intro hm hs; exact .blockIn (ih hm hs)
  | blockSkip => intro _ _; exact .blockSkip
  | blockExit h1 => intro _ _; exact .blockExit h1
  | blockP _ ih => intro hm hs; exact .blockP (ih hm hs)
  | loop => intro _ _; exact .loop

/-- Programs that agree on `A` both name only `A` there. -/
theorem ProgFns.of_agree {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') : ProgFns A P' :=
  fun f fn hf hA => hP f fn ((hag f hA).symm.trans hf) hA

theorem Agree.symm {P P' : Prog} (hag : Agree A P P') : Agree A P' P := fun f hA => (hag f hA).symm

theorem Settle.agree {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') {m m2 : Mem} {s s2 : Stmt}
    (h : Settle P m s m2 s2) (hm : MemFns A m) (hs : s.fnsIn A) : Settle P' m s m2 s2 := by
  induction h with
  | done ho => exact .done ho
  | reap hst hr _ ih =>
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    exact .reap (step_agree hag hst hm hs) hr (ih hm1.sweepD hs1)

/-- **A run reads the program only at indices in `A`**: from a configuration
    that names only `A`, a program that agrees with `P` on `A` has every run
    `P` has. -/
theorem Steps.agree {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') {m : Mem} {s : Stmt} {r : Res}
    (h : Steps P m s r) (hm : MemFns A m) (hs : s.fnsIn A) : Steps P' m s r := by
  induction h with
  | refl => exact .refl
  | step hst hse _ ih =>
    obtain ⟨hm1, hs1⟩ := (fns_step hP hst hm hs).1 _ _ rfl
    obtain ⟨hm2, hs2⟩ := hse.fns hP hm1.sweepD hs1
    exact .step (step_agree hag hst hm hs) (hse.agree hP hag hm1.sweepD hs1) (ih hm2 hs2)
  | panic hst => exact .panic (step_agree hag hst hm hs)

/-- **... and the same runs**: neither program reads the other's functions
    outside `A`, so what a run does never depends on them. -/
theorem steps_agree_iff {P P' : Prog} (hP : ProgFns A P) (hag : Agree A P P') {m : Mem} {s : Stmt}
    {r : Res} (hm : MemFns A m) (hs : s.fnsIn A) : Steps P m s r ↔ Steps P' m s r :=
  ⟨fun h => h.agree hP hag hm hs, fun h => h.agree (hP.of_agree hag) hag.symm hm hs⟩

end A2
