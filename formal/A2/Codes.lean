import A2.Closure
import A2.Repl

/-! A2 — every package names code of its signature, at every step.

A package is made by `pack`, whose code the program checks (`Stmt.codesOK`);
everything else a step stores is, or is made from, what memory already held:
a value moved or copied, a part of one, one lent.  So the packages in memory
are the ones the program made. -/

namespace A2

/-- Every package inside `v` names code of its signature. -/
def PkgOK (P : Prog) (v : Val) : Prop :=
  ∀ fs te ms e cs, Sub (.pkg fs te ms e cs) v → CodeOK P fs te ms cs

theorem memCodes_iff {P : Prog} {m : Mem} :
    MemCodes P m ↔ ∀ x o V, m.st x = some ⟨o, some V⟩ → PkgOK P V :=
  ⟨fun h x o V hx fs te ms e cs hs => h x o V fs te ms e cs hx hs,
   fun h x o V fs te ms e cs hx hs => h x o V hx fs te ms e cs hs⟩

theorem PkgOK.sub {P : Prog} {u v : Val} (h : PkgOK P v) (hs : Sub u v) : PkgOK P u :=
  fun fs te ms e cs hp => h fs te ms e cs (hp.trans hs)

theorem pkgOK_leaf {P : Prog} {v : Val} (hv : ∀ fs te ms e cs, v ≠ .pkg fs te ms e cs)
    (hc : ∀ e, ¬ Child e v) : PkgOK P v := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', _⟩
  · exact absurd h.symm (hv fs te ms e cs)
  · exact absurd hc' (hc e')

theorem pkgOK_int (P : Prog) (n : Nat) : PkgOK P (.int n) :=
  pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
theorem pkgOK_href (P : Prog) (c : Nat) : PkgOK P (.href c) :=
  pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)
theorem pkgOK_view (P : Prog) (d o l : Nat) : PkgOK P (.view d o l) :=
  pkgOK_leaf (fun _ _ _ _ _ h => by cases h) (fun _ h => by cases h)

/-- A value built from parts: its packages are theirs, and its own. -/
theorem pkgOK_of_children {P : Prog} {v : Val}
    (hself : ∀ fs te ms e cs, v = .pkg fs te ms e cs → CodeOK P fs te ms cs)
    (hc : ∀ e, Child e v → PkgOK P e) : PkgOK P v := by
  intro fs te ms e cs hs
  rcases hs.cases' with h | ⟨e', hc', hs'⟩
  · exact hself fs te ms e cs h.symm
  · exact hc e' hc' fs te ms e cs hs'

theorem PkgOK.child {P : Prog} {e v : Val} (h : PkgOK P v) (hc : Child e v) : PkgOK P e :=
  h.sub (hc.sub (Sub.refl _))

/-- Lending a value keeps its packages' code. -/
theorem pkgOK_lend {P : Prog} : ∀ {v : Val}, PkgOK P v → PkgOK P (lendOf v)
  | .int _, h => h
  | .href _, h => h
  | .view _ _ _, h => h
  | .node _ c _ _, _ => pkgOK_href P c
  | .pair v w, h => by
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | fst => exact pkgOK_lend (h.child Child.fst)
    | snd => exact pkgOK_lend (h.child Child.snd)
  | .inl v, h => by
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | inl => exact pkgOK_lend (h.child Child.inl)
  | .inr v, h => by
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | inr => exact pkgOK_lend (h.child Child.inr)
  | .pkg fs te ms v cs, h => by
    refine pkgOK_of_children (fun fs' te' ms' e cs' he => ?_) (fun e hc => ?_)
    · cases he; exact h fs te ms v cs (Sub.refl _)
    · cases hc with
      | pkg => exact pkgOK_lend (h.child Child.pkg)

theorem MemCodes.slot {P : Prog} {m : Mem} (h : MemCodes P m) {x : Var} {o : Bool} {V : Val}
    (hx : m.st x = some ⟨o, some V⟩) : PkgOK P V := memCodes_iff.mp h x o V hx

theorem MemCodes.set {P : Prog} {m : Mem} (h : MemCodes P m) {x : Var} {o : Bool} {v : Option Val}
    (hv : ∀ V, v = some V → PkgOK P V) : MemCodes P (m.set x ⟨o, v⟩) := by
  refine memCodes_iff.mpr fun y o' V hy => ?_
  by_cases hyx : y = x
  · subst hyx; simp at hy; obtain ⟨_, rfl⟩ := hy; exact hv V rfl
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

theorem MemCodes.remove {P : Prog} {m : Mem} (h : MemCodes P m) (x : Var) : MemCodes P (m.remove x) := by
  refine memCodes_iff.mpr fun y o' V hy => ?_
  by_cases hyx : y = x
  · subst hyx; simp at hy
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

theorem MemCodes.of_st {P : Prog} {m m' : Mem} (h : MemCodes P m) (hst : m'.st = m.st) : MemCodes P m' :=
  memCodes_iff.mpr fun y o V hy => h.slot (by rw [← hst]; exact hy)

/-- A node found in memory: its packages name code of their signature. -/
theorem MemCodes.nodeAt {P : Prog} {m : Mem} (h : MemCodes P m) {c : Nat} {n : Val} (hn : NodeAt m c n) :
    PkgOK P n := by
  obtain ⟨x, t, hx, hs, _⟩ := hn
  exact (h.slot hx).sub hs

theorem MemCodes.dataAt {P : Prog} {m : Mem} (h : MemCodes P m) {d : Nat} {n : Val} (hn : DataAt m d n) :
    PkgOK P n := by
  obtain ⟨x, t, hx, hs, _⟩ := hn
  exact (h.slot hx).sub hs

theorem MemCodes.vecOf {P : Prog} {m : Mem} (h : MemCodes P m) {y : Var} {t : Ty} {c d : Nat}
    {es : List Val} (hv : VecOf m y t c d es) : PkgOK P (.node t c d es) := by
  obtain ⟨_, _, hv | ⟨_, hn⟩⟩ := hv
  · exact h.slot hv
  · exact h.nodeAt hn

theorem pkgOK_elem {P : Prog} {t : Ty} {c d : Nat} {es : List Val} (h : PkgOK P (.node t c d es))
    {e : Val} (he : e ∈ es) : PkgOK P e := h.child (Child.elem he)

/-- Rewriting a tree at one node keeps its packages' code, when the new
    node's packages are fine (#295). -/
theorem Repl.pkgOK_new {P : Prog} {n n' T T' : Val} (hr : Repl n n' T T') (hT : PkgOK P T)
    (hn' : PkgOK P n') : PkgOK P T' := by
  induction hr with
  | here => exact hn'
  | @elem t c d pre post e e' _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | elem hx =>
      rcases List.mem_append.mp hx with hx | hx
      · exact hT.child (Child.elem (List.mem_append_left _ hx))
      · rcases List.mem_cons.mp hx with rfl | hx
        · exact ih (hT.child (Child.elem (List.mem_append_right _ (List.mem_cons_self ..))))
        · exact hT.child (Child.elem (List.mem_append_right _ (List.mem_cons_of_mem _ hx)))
  | fst _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | fst => exact ih (hT.child Child.fst)
    | snd => exact hT.child Child.snd
  | snd _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | fst => exact hT.child Child.fst
    | snd => exact ih (hT.child Child.snd)
  | inl _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | inl => exact ih (hT.child Child.inl)
  | inr _ ih =>
    refine pkgOK_of_children (fun _ _ _ _ _ h => by cases h) (fun x hc => ?_)
    cases hc with
    | inr => exact ih (hT.child Child.inr)
  | pkg _ ih =>
    refine pkgOK_of_children (fun fs te ms e cs h => ?_) (fun x hc => ?_)
    · cases h; exact hT _ _ _ _ _ (Sub.refl _)
    · cases hc with
      | pkg => exact ih (hT.child Child.pkg)

theorem TakeVal.codes {P : Prog} {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1)
    (h : MemCodes P m) : PkgOK P v ∧ MemCodes P m1 := by
  cases ht with
  | own hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | bor hv => exact ⟨h.slot hv, h⟩

theorem EvalR.codes {P : Prog} {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (he : EvalR m r (.ok v o m1))
    (h : MemCodes P m) (hr : r.codeOK P) : PkgOK P v ∧ MemCodes P m1 := by
  cases he with
  | expr _ => exact ⟨pkgOK_int P _, h⟩
  | new =>
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), h.of_st rfl⟩
    cases hc with | elem he => simp at he
  | moveOwn hv => exact ⟨h.slot hv, h.set (fun _ e => by cases e)⟩
  | copy hv => exact ⟨h.slot hv, h⟩
  | borrowOwn _ => exact ⟨pkgOK_href P _, h⟩
  | borrowBor hv => exact ⟨h.slot hv, h⟩
  | «at» hn hv _ => exact ⟨pkgOK_lend (pkgOK_elem (h.vecOf hv) (List.getElem_mem hn)), h⟩
  | view _ => exact ⟨pkgOK_view P _ _ _, h⟩
  | sat hn _ _ _ _ hda => exact ⟨pkgOK_lend (pkgOK_elem (h.dataAt hda) (List.getElem_mem hn)), h⟩
  | pop hv _ _ =>
    have hT := h.slot hv
    refine ⟨pkgOK_elem hT (by simp), h.set (fun V e => ?_)⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with | elem he => exact pkgOK_elem hT (by simp [he])
  | pair h1 h2 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    obtain ⟨hw, hm2⟩ := h2.codes hm1
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm2⟩
    cases hc with
    | fst => exact hv
    | snd => exact hw
  | fst hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.fst), h⟩
  | snd hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.snd), h⟩
  | inl h1 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inl => exact hv
  | inr h1 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    refine ⟨pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_), hm1⟩
    cases hc with | inr => exact hv
  | getl hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.inl), h⟩
  | getr hv => exact ⟨pkgOK_lend ((h.slot hv).child Child.inr), h⟩
  | takel hv => exact ⟨(h.slot hv).child Child.inl, h.set (fun _ e => by cases e)⟩
  | taker hv => exact ⟨(h.slot hv).child Child.inr, h.set (fun _ e => by cases e)⟩
  | pack h1 =>
    obtain ⟨hv, hm1⟩ := h1.codes h
    refine ⟨pkgOK_of_children (fun fs te ms e cs he => ?_) (fun e hc => ?_), hm1⟩
    · cases he; exact hr
    · cases hc with | pkg => exact hv

theorem BindParams.codes {P : Prog} {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (hb : BindParams m ps as base i m') (h : MemCodes P m) : MemCodes P m' := by
  induction hb with
  | nil => exact h
  | @inp m _ _ _ a _ _ _ sl v ha hl _ ih =>
    refine ih (h.set (fun V e => ?_))
    cases e
    obtain ⟨o, val⟩ := sl
    cases o <;> cases val <;> simp [lendSlot] at hl
    · subst hl; exact h.slot ha
    · subst hl; exact pkgOK_lend (h.slot ha)
  | sink ha _ ih => exact ih ((h.set (fun _ e => by cases e)).set (fun V e => by cases e; exact h.slot ha))
  | inout _ ih => exact ih h

/-! ### The program's packages -/

/-- A package's code is checked against the modes and types of its captures,
    not their names. -/
theorem codeOK_caps_rename {P : Prog} {fs : List Nat} {te : Ty} {ms : List Nat} (ρ : Var → Var)
    (cs : List (Var × PMode × Ty)) :
    CodeOK P fs te ms (cs.map (fun c => (ρ c.1, c.2))) ↔ CodeOK P fs te ms cs := by
  have h : (cs.map (fun c => (ρ c.1, c.2))).map (·.2) = cs.map (·.2) := by
    simp [List.map_map, Function.comp_def]
  unfold CodeOK Implements
  simp only [h]

theorem Rhs.codeOK_rename {P : Prog} (ρ : Var → Var) (r : Rhs) : (r.rename ρ).codeOK P ↔ r.codeOK P := by
  cases r with
  | pack fs te ms y cs => exact codeOK_caps_rename ρ cs
  | _ => exact Iff.rfl

theorem Stmt.codesOK_rename {P : Prog} (ρ : Var → Var) (s : Stmt) : (s.rename ρ).codesOK P ↔ s.codesOK P := by
  induction s with
  | seq a b iha ihb => simp only [Stmt.rename, Stmt.codesOK, iha, ihb]
  | letv x r s ih => simp only [Stmt.rename, Stmt.codesOK, ih, Rhs.codeOK_rename]
  | letd x f r s ih => simp only [Stmt.rename, Stmt.codesOK, ih, Rhs.codeOK_rename]
  | assign x r => simp only [Stmt.rename, Stmt.codesOK, Rhs.codeOK_rename]
  | ite c a b iha ihb => simp only [Stmt.rename, Stmt.codesOK, iha, ihb]
  | letcall _ _ _ _ ih | «while» _ _ ih | scope _ _ ih | rbind _ _ ih | frozen _ _ ih | letrec _ _ _ ih
  | catchR _ _ _ ih | unpair _ _ _ _ ih | callc _ _ _ _ _ ih | scopeD _ _ _ ih =>
    simp only [Stmt.rename, Stmt.codesOK, ih]
  | _ => exact Iff.rfl

theorem wrapParams_codes {P : Prog} {s : Stmt} (hs : s.codesOK P) :
    ∀ (ps : List (PMode × Ty)) (base i : Nat), (wrapParams ps base i s).codesOK P := by
  intro ps
  induction ps with
  | nil => intro _ _; exact hs
  | cons p ps ih =>
    intro base i
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp only [wrapParams, Stmt.codesOK] <;> exact ih base (i + 1)

theorem callIn_codes {P : Prog} (hPc : ProgCodes P) {f : Nat} {fn : Fn} (hf : P[f]? = some fn)
    (args : List Var) (base : Nat) (x : Var) : (callIn fn args base x).codesOK P := by
  have hb : (fn.body.rename (callRen fn.params args base)).codesOK P :=
    (Stmt.codesOK_rename _ _).mpr (hPc fn (List.mem_of_getElem? hf))
  exact ⟨wrapParams_codes hb _ _ _, trivial⟩

/-- Every step keeps every package naming code of its signature. -/
theorem codes_step {P : Prog} (hPc : ProgCodes P) {m : Mem} {s : Stmt} {r : Res} (hst : Step P m s r) :
    MemCodes P m → s.codesOK P →
      (∀ m' s', r = .ok m' s' → MemCodes P m' ∧ s'.codesOK P) ∧ (∀ m', r = .panic m' → MemCodes P m') := by
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
    obtain ⟨hv, hm1⟩ := he.codes hm hs.1
    exact ⟨hm1.set (fun V e => by cases e; exact hv), hs.2⟩
  | letvP _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | letcall hf _ hb =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(((hb.codes hm).set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      callIn_codes hPc hf _ _ _, hs⟩
  | scopeSkip _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(hm.of_st rfl).remove _, trivial⟩
  | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | catchIn _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hs).1 _ _ rfl; exact ⟨h1, h2⟩
  | scopeP _ _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (((ih hm hs).2 _ rfl).of_st rfl).remove _
  | rbindSkip _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.remove _, trivial⟩
  | rbindP _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ((ih hm hs).2 _ rfl).remove _
  | frozenSkip | catchSkip =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm, trivial⟩
  | frozenP _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact (ih hm hs).2 _ rfl
  | catchP _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((ih hm hs).2 _ rfl).set (fun V e => by cases e; exact pkgOK_int P 1), trivial⟩
  | assign _ he _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.codes hm hs
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
    obtain ⟨hv, hm1⟩ := ht.codes hm
    have hT := hm1.slot hx
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he =>
      rcases List.mem_append.mp he with he | he
      · exact pkgOK_elem hT he
      · simp at he; subst he; exact hv
  | free _ _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨(hm.of_st rfl).set (fun _ e => by cases e), trivial⟩
  | editPush ht hn hr | editPushRealloc ht hn hr =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := ht.codes hm
    have hT := hm1.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm1.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine hr.pkgOK_new hT ?_
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he =>
      rcases List.mem_append.mp he with he | he
      · exact pkgOK_elem hn0 he
      · simp at he; subst he; exact hv
  | editTrunc _ hn _ hr =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hn.2.2.1
    have hn0 := hT.sub hr.sub
    refine ⟨(hm.of_st rfl).set (fun V e => ?_), trivial⟩
    cases e
    refine hr.pkgOK_new hT ?_
    refine pkgOK_of_children (fun _ _ _ _ _ he => by cases he) (fun e hc => ?_)
    cases hc with
    | elem he => exact pkgOK_elem hn0 (List.mem_of_mem_take he)
  | panic =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | letrec hf _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((hm.set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      ⟨callIn_codes hPc hf _ _ _, hs⟩⟩
  | unpair hy _ _ _ =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hy
    exact ⟨((hm.set (fun _ e => by cases e)).set (fun V e => by cases e; exact hT.child Child.fst)).set
      (fun V e => by cases e; exact hT.child Child.snd), hs⟩
  | letd _ he =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨hv, hm1⟩ := he.codes hm hs.1
    exact ⟨hm1.set (fun V e => by cases e; exact hv), hs.2⟩
  | letdP _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact hm
  | scopeDIn _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    obtain ⟨h1, h2⟩ := (ih hm hs).1 _ _ rfl; exact ⟨h1, h2⟩
  | scopeDEnd _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.of_st rfl, trivial⟩
  | scopeDMoved _ =>
    intro hm _; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨hm.remove _, trivial⟩
  | scopeDP _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ⟨((ih hm hs).2 _ rfl).of_st rfl, trivial, trivial⟩
  | scopeDPMoved _ _ ih =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    exact ((ih hm hs).2 _ rfl).remove _
  | callc hslot _ hf _ hb =>
    intro hm hs; refine ⟨fun _ _ h => ?_, fun _ h => ?_⟩ <;> cases h
    have hT := hm.slot hslot
    have hme : MemCodes P (envMem _ _) :=
      (hm.set (fun V e => by cases e; exact pkgOK_lend (hT.child Child.pkg))).of_st rfl
    exact ⟨(((hb.codes hme).set (fun _ e => by cases e)).set (fun _ e => by cases e)).of_st rfl,
      ⟨callIn_codes hPc hf _ _ _, hs⟩⟩

end A2
