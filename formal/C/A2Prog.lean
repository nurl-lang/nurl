import C.A2Exit
import A2.Soundness

/-!
# C11: A2's whole programs, decided (AGORA-970)

`fnOK2B` decides A2's `FnOK` for a function: its signature's clauses, the
body checked by `checkX` (`checkA2`'s rules, and `exit`s carried as
obligations, none left at the body's top) from `sigCtx` over the domain of
its variables and its parameters' regions, and the end the summary promises.
`progOK2B` decides `ProgOK`, and `checked_program_safe2` closes phase C for
A2: a program the checker accepts never gets stuck from the empty store.
-/

namespace C

open A2

/-- `lendable` (A2), decided. -/
def lendable2B (fn : Fn) (j : Nat) : Bool :=
  match fn.params[j]? with
  | some (.inp, _) => true
  | some (.inout _, _) => true
  | _ => false

theorem lendable2B_sound {fn : Fn} {j : Nat} (h : lendable2B fn j = true) : lendable fn j := by
  unfold lendable2B at h
  split at h
  · rename_i t hj
    obtain ⟨hlt, he⟩ := List.getElem?_eq_some_iff.mp hj
    exact ⟨hlt, Or.inl (by rw [he])⟩
  · rename_i b t hj
    obtain ⟨hlt, he⟩ := List.getElem?_eq_some_iff.mp hj
    exact ⟨hlt, Or.inr ⟨b, by rw [he]⟩⟩
  · cases h

/-- `kindFits`, decided. -/
def kindFitsB (fn : Fn) (j : Nat) (k : Kind) : Bool :=
  match fn.params[j]? with
  | some (.inout _, t) => decide (rootKind t k = k)
  | _ => true

theorem kindFitsB_sound {fn : Fn} {j : Nat} {k : Kind} (h : kindFitsB fn j k = true) : kindFits fn j k := by
  intro b t hj
  simp only [kindFitsB, hj, decide_eq_true_eq] at h
  exact h

/-- The domain a function's body is checked over: its variables and its
    parameters' regions (`isRegionIdx`). -/
def fnDom (fn : Fn) : List Var := List.range (fn.nvars + fn.params.length)

theorem sigCtx_supported2 {fn : Fn} (h : fn.params.length < fn.nvars) :
    Supported2 (sigCtx fn) (fnDom fn) := by
  intro v hv
  have hv' : fn.nvars + fn.params.length ≤ v := by simpa [fnDom] using hv
  have hlen : fn.params.length < v :=
    Nat.lt_of_lt_of_le h (Nat.le_trans (Nat.le_add_right _ _) hv')
  have h1 : ¬ v < fn.params.length := fun hlt => Nat.lt_asymm hlt hlen
  have h2 : ¬ v = fn.params.length := fun he => Nat.lt_irrefl _ (he ▸ hlen)
  have h3 : isRegionIdx fn v = false := by
    cases hr : isRegionIdx fn v
    · rfl
    · obtain ⟨hge, hlt, _⟩ := isRegionIdx_iff.mp hr
      exact absurd hlt (Nat.not_lt.mpr (Nat.le_sub_of_add_le (Nat.add_comm _ _ ▸ hv')))
  simp [sigCtx, h1, h2, h3]

/-- No destructor binding is left at the body's end (over the domain). -/
def noDtorEndB (D : List Var) (Δ : Ctx) : Bool :=
  D.all fun v => match Δ v with | some E => !E.dtor && !E.dbind | none => true

theorem noDtorEndB_sound {D : List Var} {Δ : Ctx} (hs : Supported2 Δ D) (h : noDtorEndB D Δ = true) :
    ∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false := by
  intro v E hE
  have := List.all_eq_true.mp h v (mem_of_some2 hs hE)
  simp only [hE, Bool.and_eq_true, Bool.not_eq_true'] at this
  exact this

/-- The result's end: set, of the result type and mode, borrowing and
    holding only what the summary names (or a parameter's region), and an
    owned view-free result holding nothing. -/
def resEndB (fn : Fn) (Δ : Ctx) : Bool :=
  match Δ fn.params.length with
  | some Er => Er.live && decide (Er.ty = fn.resTy) && decide (Er.mode = resMode fn) &&
      Er.path.all (fun d => isRegionIdx fn d.root || decide ((d.root, d.kind) ∈ fn.lends)) &&
      Er.held.all (fun d => isRegionIdx fn d.root || decide ((d.root, d.kind) ∈ fn.rholds)) &&
      (!fn.resOwn || fn.resTy.holdsView || Er.held.isEmpty)
  | none => false

theorem resEndB_sound {fn : Fn} {Δ : Ctx} (h : resEndB fn Δ = true) :
    ∃ Er, Δ fn.params.length = some Er ∧ Er.live = true ∧ Er.ty = fn.resTy ∧ Er.mode = resMode fn ∧
      (∀ d ∈ Er.path, isRegionIdx fn d.root ∨ (d.root, d.kind) ∈ fn.lends) ∧
      (∀ d ∈ Er.held, isRegionIdx fn d.root ∨ (d.root, d.kind) ∈ fn.rholds) ∧
      (fn.resOwn = true → fn.resTy.holdsView = false → Er.held = []) := by
  unfold resEndB at h
  split at h
  · rename_i Er hEr
    simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true',
      List.all_eq_true, List.isEmpty_iff] at h
    obtain ⟨⟨⟨⟨⟨hl, ht⟩, hm⟩, hp⟩, hh⟩, he⟩ := h
    refine ⟨Er, hEr, hl, ht, hm, fun d hd => hp d hd, fun d hd => hh d hd, fun ho hv => ?_⟩
    rcases he with (he | he) | he
    · rw [ho] at he; cases he
    · rw [hv] at he; cases he
    · exact he
  · cases h

/-- Every `inout` parameter's end: set again, holding only what the summary
    names (or a parameter's region), nothing when its type holds no views. -/
def inoutEndB (fn : Fn) (Δ : Ctx) : Bool :=
  (List.range fn.params.length).all fun i =>
    match fn.params[i]? with
    | some (.inout _, t) => (match Δ i with
        | some Ei => Ei.live &&
            Ei.held.all (fun d => isRegionIdx fn d.root || decide ((i, d.root, d.kind) ∈ fn.outHolds)) &&
            (t.holdsView || Ei.held.isEmpty)
        | none => false)
    | _ => true

theorem inoutEndB_sound {fn : Fn} {Δ : Ctx} (h : inoutEndB fn Δ = true) :
    ∀ i (hi : i < fn.params.length) b, fn.params[i].1 = .inout b →
      ∃ Ei, Δ i = some Ei ∧ Ei.live = true ∧
        (∀ d ∈ Ei.held, isRegionIdx fn d.root ∨ (i, d.root, d.kind) ∈ fn.outHolds) ∧
        (fn.params[i].2.holdsView = false → Ei.held = []) := by
  intro i hi b hb
  have := List.all_eq_true.mp h i (List.mem_range.mpr hi)
  rw [List.getElem?_eq_getElem hi] at this
  have hpi : fn.params[i] = (.inout b, fn.params[i].2) := by rw [← hb]
  rw [hpi] at this
  simp only at this
  split at this
  · rename_i Ei hEi
    simp only [Bool.and_eq_true, Bool.or_eq_true, List.all_eq_true, List.isEmpty_iff] at this
    obtain ⟨⟨hl, hh⟩, he⟩ := this
    refine ⟨Ei, hEi, hl, fun d hd => by simpa using hh d hd, fun hv => ?_⟩
    rcases he with he | he
    · rw [hv] at he; cases he
    · exact he
  · cases this

/-- A destructor type, or a nest of `Vec`s around one: its destructor and
    struct. -/
def resDTyOf : Ty → Option (Nat × Ty)
  | .dtor g t => some (g, t)
  | .vec u => resDTyOf u
  | _ => none

theorem resDTyOf_nest : ∀ {u : Ty} {g : Nat} {t : Ty}, resDTyOf u = some (g, t) →
    ∃ n, u = Ty.nest n (.dtor g t) := by
  intro u
  induction u with
  | dtor g' t' _ =>
    intro g t h
    simp only [resDTyOf, Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    exact ⟨0, rfl⟩
  | vec u ih =>
    intro g t h
    simp only [resDTyOf] at h
    obtain ⟨n, hn⟩ := ih h
    exact ⟨n + 1, by rw [hn]; rfl⟩
  | _ => intro g t h; simp [resDTyOf] at h

theorem resDTyOf_sound {τ : Ty} {g : Nat} {t : Ty} (h : resDTyOf τ = some (g, t)) : ResDTy g t τ := by
  cases τ with
  | dtor g' t' =>
    simp only [resDTyOf, Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
    exact Or.inl rfl
  | vec u =>
    simp only [resDTyOf] at h
    obtain ⟨n, hn⟩ := resDTyOf_nest h
    exact Or.inr ⟨n, by rw [hn]⟩
  | _ => simp [resDTyOf] at h

/-- `DtorParamsOK`, decided: a `sink` parameter holding a destructor value
    is moved first and never assigned; an `inout` one holding one is never
    assigned; an owned result holding one is assigned at most once and is
    of a destructor type (or a `Vec` nest of one) whose struct holds no
    views and no closure, with its destructor or glue checked (`dropFnOKB`).
    A `sink` parameter that is not moved first may instead be the value an
    enum's or a closure's glue takes apart, `fn` being that glue: function
    `f` of the program (`glueSelfB`). -/
def glueSelfB (P : Prog) (f : Nat) (fn : Fn) : Bool :=
  match fn.params with
  | [(.sink, .dtor _ u)] => enumGlueOKB P f u || closureGlueOKB P f u
  | _ => false

theorem glueSelfB_sound {P : Prog} {f : Nat} {fn : Fn} (hf : P[f]? = some fn) (h : glueSelfB P f fn = true) :
    ∃ f u, P[f]? = some fn ∧ (EnumGlueOK P f u ∨ ClosureGlueOK P f u) := by
  unfold glueSelfB at h
  split at h
  · simp only [Bool.or_eq_true] at h
    rcases h with h | h
    · exact ⟨f, _, hf, Or.inl (enumGlueOKB_sound h)⟩
    · exact ⟨f, _, hf, Or.inr (closureGlueOKB_sound h)⟩
  · cases h

/-- An enum's glue (`glueEx`, C7) takes its `sink` parameter apart by its
    tag and never moves it: its clause holds only as the glue it is. -/
example : (glueEx (.ite (.isl 0) (.assign 1 (.expr (.lit 0))) .skip) (.sum .int .int)).all
    (fun fn => glueSelfB (glueEx (.ite (.isl 0) (.assign 1 (.expr (.lit 0))) .skip) (.sum .int .int)) 0 fn)
    = true := by decide

def dtorParamsB (P : Prog) (f : Nat) (fn : Fn) : Bool :=
  (List.range fn.params.length).all (fun i => match fn.params[i]? with
    | some (.sink, t) => !t.holdsDtor ||
        ((decide (i ∈ fn.body.movedFirst) || glueSelfB P f fn) && decide (i ∉ fn.body.assigns))
    | some (.inout _, t) => !t.holdsDtor || decide (i ∉ fn.body.assigns)
    | _ => true) &&
  (!fn.resOwn || !fn.resTy.holdsDtor ||
    (decide (fn.body.asgMax fn.params.length ≤ 1) &&
      match resDTyOf fn.resTy with
      | some (g, t) => !t.holdsView && !t.hasFn && dropFnOKB P g t
      | none => false))

theorem dtorParamsB_sound {P : Prog} {f : Nat} {fn : Fn} (hf : P[f]? = some fn) (h : dtorParamsB P f fn = true) :
    DtorParamsOK P fn := by
  simp only [dtorParamsB, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at h
  obtain ⟨hp, hr⟩ := h
  refine ⟨fun i hi hs hd => ?_, fun i hi b hb hd => ?_, fun ho hd => ?_⟩
  · have := List.all_eq_true.mp hp i (List.mem_range.mpr hi)
    rw [List.getElem?_eq_getElem hi] at this
    have hpi : fn.params[i] = (.sink, fn.params[i].2) := by rw [← hs]
    rw [hpi] at this
    simp only [hd, Bool.not_true, Bool.false_or, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at this
    obtain ⟨hm, ha⟩ := this
    rcases hm with hm | hm
    · exact ⟨Or.inl hm, ha⟩
    · exact ⟨Or.inr (glueSelfB_sound hf hm), ha⟩
  · have := List.all_eq_true.mp hp i (List.mem_range.mpr hi)
    rw [List.getElem?_eq_getElem hi] at this
    have hpi : fn.params[i] = (.inout b, fn.params[i].2) := by rw [← hb]
    rw [hpi] at this
    simp only [hd, Bool.not_true, Bool.false_or, decide_eq_true_eq] at this
    exact this
  · rcases hr with (hr | hr) | hr
    · rw [ho] at hr; cases hr
    · rw [hd] at hr; cases hr
    · simp only [Bool.and_eq_true, decide_eq_true_eq] at hr
      obtain ⟨ha, hm⟩ := hr
      split at hm
      · rename_i g t ht
        simp only [Bool.and_eq_true, Bool.not_eq_true'] at hm
        obtain ⟨⟨hv, hf⟩, hdf⟩ := hm
        exact ⟨ha, g, t, resDTyOf_sound ht, hv, hf, dropFnOKB_sound hdf⟩
      · cases hm

/-- One round of the through-changing set: every function whose body
    changes elements through a borrow, or calls one of `S`. -/
def thruStep (P : Prog) (S : List Nat) : List Nat :=
  (List.range P.length).filter fun f => match P[f]? with
    | some fn => fn.body.hasThru || fn.body.calls.any (· ∈ S)
    | none => false

/-- The through-changing set, grown round by round from nothing until a
    round adds nothing (at most one round per function). A search of every
    call chain (`n` calls deep from each function) was exponential in the
    depth. -/
def thruIter (P : Prog) : Nat → List Nat → List Nat
  | 0, S => S
  | n + 1, S => let S' := thruStep P S; if S' = S then S else thruIter P n S'

def thruSet (P : Prog) : List Nat := thruIter P P.length []

theorem thruStep_sound {P : Prog} {S : List Nat} (hS : ∀ g ∈ S, ThruFn P g) :
    ∀ f ∈ thruStep P S, ThruFn P f := by
  intro f hf
  simp only [thruStep, List.mem_filter] at hf
  obtain ⟨_, h⟩ := hf
  split at h
  · rename_i fn hfn
    simp only [Bool.or_eq_true, List.any_eq_true, decide_eq_true_eq] at h
    rcases h with h | ⟨g, hg, hgS⟩
    · exact .here hfn h
    · exact .call hfn hg (hS g hgS)
  · cases h

theorem thruIter_sound {P : Prog} : ∀ {n : Nat} {S : List Nat}, (∀ g ∈ S, ThruFn P g) →
    ∀ f ∈ thruIter P n S, ThruFn P f
  | 0, _, hS => hS
  | n + 1, S, hS => by
    simp only [thruIter]
    split
    · exact hS
    · exact thruIter_sound (thruStep_sound hS)

/-- `ThruFn P f`, found: `f` is in the through-changing set. -/
theorem thruSet_sound {P : Prog} {f : Nat} (h : f ∈ thruSet P) : ThruFn P f :=
  thruIter_sound (fun _ h => by cases h) f h

/-- `Implements`, decided: its signature is the interface's with the
    environment as the receiver and the captures after, and what it lends
    and holds is within the interface's; and it changes no elements through
    a borrow (`noThruB`), or the interface is code that does too
    (`thruSet`), with an environment that holds no views, taken lent. -/
def implementsB (P : Prog) (f : Nat) (te : Ty) (cs : List (Var × PMode × Ty)) (σ : Nat) : Bool :=
  match P[f]?, P[σ]? with
  | some fn, some sig =>
    decide (fn.params = (sig.recvMode, te) :: sig.params.tail ++ cs.map (·.2)) &&
    (decide (sig.recvMode = .inp) || cs.isEmpty) &&
    decide (fn.resTy = sig.resTy) && decide (fn.resOwn = sig.resOwn) &&
    fn.lends.all (fun x => decide (x ∈ sig.lends)) && fn.rholds.all (fun x => decide (x ∈ sig.rholds)) &&
    fn.outHolds.all (fun x => decide (x ∈ sig.outHolds)) &&
    (noThruB P f || (decide (σ ∈ thruSet P) && !te.holdsView && decide (sig.recvMode = .inp)))
  | _, _ => false

theorem implementsB_sound {P : Prog} {f : Nat} {te : Ty} {cs : List (Var × PMode × Ty)} {σ : Nat}
    (h : implementsB P f te cs σ = true) : Implements P f te cs σ := by
  unfold implementsB at h
  split at h
  · rename_i fn sig hf hσ
    simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, List.all_eq_true,
      List.isEmpty_iff, Bool.not_eq_true'] at h
    obtain ⟨⟨⟨⟨⟨⟨⟨hp, hcs⟩, hr⟩, ho⟩, hl⟩, hh⟩, hoh⟩, hnt⟩ := h
    refine ⟨fn, sig, hf, hσ, hp, fun hne => ?_, hr, ho, fun x hx => hl x hx, fun x hx => hh x hx,
      fun x hx => hoh x hx, fun ht => ?_⟩
    · rcases hcs with h0 | h0
      · exact absurd h0 hne
      · exact h0
    · rcases hnt with hnt | ⟨⟨hre, hv⟩, hm⟩
      · exact absurd ht (noThruB_sound hnt)
      · exact ⟨thruSet_sound hre, hv, hm⟩
  · cases h

/-- `CodeOK`, decided method by method. -/
def codeOKB (P : Prog) (fs : List Nat) (te : Ty) (ms : List Nat) (cs : List (Var × PMode × Ty)) : Bool :=
  decide (fs.length = ms.length) && (List.range fs.length).all fun j =>
    match fs[j]?, ms[j]? with
    | some f, some σ => implementsB P f te cs σ
    | _, _ => true

theorem codeOKB_sound {P : Prog} {fs : List Nat} {te : Ty} {ms : List Nat} {cs : List (Var × PMode × Ty)}
    (h : codeOKB P fs te ms cs = true) : CodeOK P fs te ms cs := by
  simp only [codeOKB, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  refine ⟨h.1, fun j f σ hf hσ => ?_⟩
  have hj : j < fs.length := (List.getElem?_eq_some_iff.mp hf).1
  have := h.2 j (List.mem_range.mpr hj)
  rw [hf, hσ] at this
  exact implementsB_sound this

/-- `Rhs.codeOK`, decided: a closure package's code implements its
    interfaces (`codeOKB`); an `arc`, a lock or a cell over a
    destructor-free payload reaps nothing (`Ty.Reaps.dtorFree`). -/
def rhsCodeB (P : Prog) : Rhs → Bool
  | .pack fs te ms _ cs => codeOKB P fs te ms cs
  | .arcNew t _ => t.dtorFree
  | .lockNew t _ => t.dtorFree
  | .cellNew t _ => t.dtorFree
  | _ => true

theorem rhsCodeB_sound {P : Prog} {r : Rhs} (h : rhsCodeB P r = true) : r.codeOK P := by
  cases r <;> simp only [rhsCodeB] at h <;> simp only [Rhs.codeOK] <;>
    first
    | trivial
    | exact codeOKB_sound h
    | exact fun f u hr => absurd (Ty.Reaps.dtorFree hr) (by rw [h]; decide)
    | cases h

/-- `Stmt.codesOK`, decided with `rhsCodeB`. -/
def stmtCodesB (P : Prog) : Stmt → Bool
  | .seq a b => stmtCodesB P a && stmtCodesB P b
  | .letv _ r s => rhsCodeB P r && stmtCodesB P s
  | .letcall _ _ _ s => stmtCodesB P s
  | .assign _ r => rhsCodeB P r
  | .ite _ a b => stmtCodesB P a && stmtCodesB P b
  | .while _ s => stmtCodesB P s
  | .scope _ s => stmtCodesB P s
  | .rbind _ s => stmtCodesB P s
  | .frozen _ s => stmtCodesB P s
  | .letrec _ _ s => stmtCodesB P s
  | .catchR _ _ s => stmtCodesB P s
  | .unpair _ _ _ s => stmtCodesB P s
  | .callc _ _ _ _ _ s => stmtCodesB P s
  | .letd _ _ r s => rhsCodeB P r && stmtCodesB P s
  | .scopeD _ _ s => stmtCodesB P s
  | .withLock _ _ s => stmtCodesB P s
  | .scopeL _ _ _ s => stmtCodesB P s
  | .withElem _ _ _ s => stmtCodesB P s
  | .callcE _ _ _ _ s => stmtCodesB P s
  | .block s => stmtCodesB P s
  | .loop s => stmtCodesB P s
  | .takeB _ _ _ s => stmtCodesB P s
  | _ => true

theorem stmtCodesB_sound {P : Prog} : ∀ {s : Stmt}, stmtCodesB P s = true → s.codesOK P := by
  intro s
  induction s <;> intro h <;> simp only [stmtCodesB, Bool.and_eq_true] at h <;> simp only [Stmt.codesOK] <;>
    first
    | trivial
    | exact ⟨‹_ → _› h.1, ‹_ → _› h.2⟩
    | exact ⟨rhsCodeB_sound h.1, ‹_ → _› h.2⟩
    | exact rhsCodeB_sound h
    | exact ‹_ → _› h
    | skip

/-- `FnOK` (A2), decided: the signature's clauses, the destructor clauses,
    and the body checked by `checkA2` from `sigCtx` over `fnDom`, ending as
    the summary says. -/
def fnOK2B (P : Prog) (f : Nat) (fn : Fn) : Bool :=
  fn.body.src && decide (fn.params.length < fn.nvars) && fn.body.vars.all (fun v => decide (v < fn.nvars)) &&
  fn.resTy.ok && (!fn.resOwn || fn.resTy.owning) &&
  fn.params.all (fun pt => pt.2.ok && (!(decide (pt.1 = .sink)) || pt.2.owning) &&
    (match pt.1 with | .inout _ => pt.2.owning | _ => true)) &&
  fn.lends.all (fun jk => lendable2B fn jk.1 && !jk.2.isName) &&
  fn.rholds.all (fun jk => lendable2B fn jk.1 && !jk.2.isName) &&
  fn.outHolds.all (fun o => lendable2B fn o.2.1 && !o.2.2.isName) &&
  (fn.lends ++ fn.rholds).all (fun jk => kindFitsB fn jk.1 jk.2) &&
  fn.outHolds.all (fun o => kindFitsB fn o.2.1 o.2.2) &&
  dtorParamsB P f fn &&
  (match checkX P (inferRhs2p P (fnDom fn)) (callB2 P (fnDom fn)) (fnDom fn) (sigCtx fn) [] fn.body with
   | some r => r.E.isEmpty && noDtorEndB (fnDom fn) r.Δ && resEndB fn r.Δ && inoutEndB fn r.Δ
   | none => false)

theorem fnOK2B_sound {P : Prog} {f : Nat} {fn : Fn} (hf : P[f]? = some fn) (h : fnOK2B P f fn = true) :
    FnOK P fn := by
  simp only [fnOK2B, Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true',
    List.all_eq_true] at h
  obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨⟨hsrc, hlen⟩, hvars⟩, hres⟩, hown⟩, hps⟩, hl⟩, hr⟩, ho⟩, hkf⟩, hkfo⟩, hdp⟩, hchk⟩ := h
  refine ⟨hsrc, hlen, fun v hv => hvars v hv, hres, fun e => ?_, fun pt hpt => ?_,
    fun jk hjk => ?_, fun jk hjk => ?_, fun o hoo => ?_,
    fun jk hjk => kindFitsB_sound (hkf jk hjk), fun o hoo => kindFitsB_sound (hkfo o hoo),
    dtorParamsB_sound hf hdp, ?_⟩
  · rcases hown with h0 | h0
    · rw [e] at h0; cases h0
    · exact h0
  · have := hps pt hpt
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    obtain ⟨⟨hok, hsk⟩, hio⟩ := this
    refine ⟨hok, fun hs => ?_, fun b hb => ?_⟩
    · rcases hsk with h0 | h0
      · exact absurd hs h0
      · exact h0
    · rw [hb] at hio; exact hio
  · have := hl jk hjk
    exact ⟨lendable2B_sound this.1, this.2⟩
  · have := hr jk hjk
    exact ⟨lendable2B_sound this.1, this.2⟩
  · have := ho o hoo
    exact ⟨lendable2B_sound this.1, this.2⟩
  · split at hchk
    · rename_i r hr
      have hD : ∀ v ∈ fn.body.vars, v ∈ fnDom fn := fun v hv =>
        List.mem_range.mpr (Nat.lt_of_lt_of_le (hvars v hv) (Nat.le_add_right _ _))
      obtain ⟨hsΔ, _, ht, _⟩ := checkX_sound (inferRhs2p_OK P _) (callB2_OK P _) (sigCtx_supported2 hlen) hD hr
      simp only [Bool.and_eq_true, List.isEmpty_iff] at hchk
      obtain ⟨⟨⟨hE, hnd⟩, hre⟩, hie⟩ := hchk
      exact ⟨r.Δ, ht .none (by rw [hE]; intro e he; cases he), noDtorEndB_sound hsΔ hnd, resEndB_sound hre,
        inoutEndB_sound hie⟩
    · cases hchk

/-- `ProgOK` and `ProgCodes` (A2), decided function by function, each at
    its index: a glue's clause names the function it is (`glueSelfB`). -/
def progOK2B (P : Prog) : Bool :=
  (List.range P.length).all fun f => match P[f]? with
    | some fn => fnOK2B P f fn && stmtCodesB P fn.body
    | none => true

theorem progOK2B_sound {P : Prog} (h : progOK2B P = true) : ProgOK P ∧ ProgCodes P := by
  have hat : ∀ fn ∈ P, ∃ f, P[f]? = some fn ∧ fnOK2B P f fn = true ∧ stmtCodesB P fn.body = true := by
    intro fn hfn
    obtain ⟨f, hlt, hget⟩ := List.mem_iff_getElem.mp hfn
    have hf : P[f]? = some fn := by rw [List.getElem?_eq_getElem hlt, hget]
    have := List.all_eq_true.mp h f (List.mem_range.mpr hlt)
    rw [hf] at this
    simp only [Bool.and_eq_true] at this
    exact ⟨f, hf, this.1, this.2⟩
  refine ⟨fun fn hfn => ?_, fun fn hfn => ?_⟩
  · obtain ⟨f, hf, h1, _⟩ := hat fn hfn
    exact fnOK2B_sound hf h1
  · obtain ⟨_, _, _, h2⟩ := hat fn hfn
    exact stmtCodesB_sound h2

/-- Phase C for A2, end to end: a program the checker accepts, with an
    entry statement it accepts, never gets stuck from the empty store. -/
theorem checked_program_safe2 {P : Prog} (hP : progOK2B P = true) {s : Stmt} {Δ : Ctx}
    (hc : checkA2 P s.vars (fun _ => none) [] s = some Δ) (hsc : stmtCodesB P s = true)
    (hs : s.src = true) {nv : Nat} (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt}
    (hr : Steps P (emptyMem nv) s (.ok m' s')) : ¬ Stuck P m' s' := by
  obtain ⟨hok, hcodes⟩ := progOK2B_sound hP
  obtain ⟨ht, _⟩ := checkA2_sound (ξ := .none) (fun _ _ => rfl) (fun v hv => hv) hc
  exact memory_safe hok hcodes ht hs (stmtCodesB_sound hsc) hv hr

end C
