import A2.Closure

/-! AGORA-937 (turn-on 3) in A2: a function whose result holds views of its
`sink` parameter's region.

`idv sink (Vec [s) vv → Vec [s` returns `vv`: the result holds what `vv`
holds, views of the caller's memory, which `idv`'s own typing sees as the
region `π vv` (`sigCtx`). `FnOK`'s end check lets a result hold views of a
parameter's region (`isRegionIdx`), so `idv` is well-typed (`idv_ok`); before,
the result could hold only what `rholds` names, of a lendable (`inp` or
`inout`) parameter, and a `sink` one is not (`idv_not_ok0`: no summary made
it `FnOK0`). Its call types, the caller's result holding the views the
argument held (`call_ok`, `callRes_holds`): the call substitutes those for
the region (`CallH.res_props`).

A view of the `sink` parameter's own buffer is still refused: `vw sink
(Vec i) v → [i` returning `( view v )` is well-typed under no summary
(`vw_not_ok`), as no lendable parameter is lent, and neither end check
admits a dependency on a `sink` parameter itself (`sink_dep_refused`:
`lendable` is unchanged, and a parameter is no region).

Turn-on 4: a borrowed result that views a region, `vat sink (Vec [s) vv → [s`
returning `( vec_at vv 0 )`, is well-typed (`vat_ok`). Its path is what `vv`
holds, the region, and `FnOK`'s path check now admits a region as its held
check does (`isRegionIdx`). The path-side negative is `vw_not_ok`: a borrow
of the `sink` parameter's own buffer is still refused, the parameter being
no region and not lendable.

A field of an owned struct that can hold no view or closure depends on the
struct alone, not on what its sibling fields' views point into (`projHeld`):
a truncation through a borrow of the first field of a `sink (prod (Vec i)
(Vec [s))` parameter passes `ThruOK` (`fst_trunc_ok`), where it was refused
with the struct's held view of the region in its path
(`fst_trunc_old_refused`); the second field still carries the region
(`snd_trunc_refused`). -/

namespace A2.RegionResWitness

def vsi : Ty := .vec (.slice .int)

/-- `idv vv`: returns its `sink` parameter. `vv` is 0, the result slot 1,
    `π vv` is `2`. -/
def idv : Fn where
  params   := [(.sink, vsi)]
  resTy    := vsi
  resOwn   := true
  lends    := []
  rholds   := []
  outHolds := []
  body     := .assign 1 (.var 0)
  nvars    := 2

def P : Prog := [idv]

def E0 : Entry := ⟨vsi, .own, true, [], [⟨2, .view⟩], false, false, false, false⟩
def R1 : Entry := ⟨vsi, .own, false, [], [], false, false, false, false⟩

theorem sig_eq : sigCtx idv = fun v =>
    if v = 0 then some E0 else if v = 1 then some R1 else if v = 2 then some regionE else none := by
  funext v
  rcases v with _ | _ | _ | v <;>
    simp [sigCtx, isRegionIdx, regionP, regioned, paramE, idv, vsi, Ty.holdsView, Ty.hasFn, resMode, E0, R1]

theorem sig_flags : ∀ v E, sigCtx idv v = some E → E.dtor = false ∧ E.dbind = false ∧ E.mode ≠ .rootb := by
  intro v E h
  rcases v with _ | _ | _ | v <;> simp [sig_eq] at h <;> subst h <;> simp [E0, R1, regionE]

/-- What `vv`'s move leaves. -/
def G1 : Ctx := setE (kill .replace false 0 (sigCtx idv)) 0 { E0 with live := false, dtor := false }
def Er : Entry := ⟨vsi, .own, true, [], E0.held, false, false, false, false⟩
def D1 : Ctx := setE (kill .replace false 1 G1) 1 { Er with mode := R1.mode }

theorem G1_dtor : ∀ v E, G1 v = some E → E.dtor = false := by
  intro v E h
  simp only [G1, setE, upd] at h
  split at h
  · cases h; rfl
  · simp only [kill] at h
    obtain ⟨E', h', rfl⟩ := Option.map_eq_some_iff.mp h
    rw [killE_dtor]; exact (sig_flags v E' h').1

theorem noPin_sig (y : Var) : NoPin (sigCtx idv) y := fun p E hp hm =>
  absurd hm (sig_flags p E hp).2.2

theorem body_typed : StmtT P .none (sigCtx idv) [] idv.body D1 :=
  StmtT.assign (Ex := R1) (E := Er) (by rw [sig_eq]; rfl) (by simp) (Or.inl ⟨rfl, rfl⟩)
    (RhsT.moveOwn (by rw [sig_eq]; rfl) rfl rfl List.not_mem_nil (noPin_sig 0)
      (DtorSafe.of_none (fun v E h => (sig_flags v E h).1) _ _ _))
    rfl (by simp [Er, E0, roots, Entry.vdeps, Mode.ownSlot]) rfl
    (noPin_sig 1) (DtorSafe.of_none G1_dtor _ _ _) rfl

/-- The result holds a view of `π vv`. -/
theorem res_region : ∀ d ∈ Er.held, isRegionIdx idv d.root = true := by
  intro d hd
  simp only [Er, E0, List.mem_singleton] at hd
  subst hd; rfl

/-- **`idv` is well-typed**: its result holds views of its `sink`
    parameter's region. -/
theorem idv_ok : FnOK P idv := by
  refine ⟨rfl, by decide, by decide, rfl, fun _ => rfl, ?_, by simp [idv],
    by simp [idv], by simp [idv], by simp [idv], by simp [idv],
    dtorParamsOK_of (by simp [idv, vsi, Ty.holdsDtor]) (by simp [idv, vsi, Ty.holdsDtor]), _,
    body_typed, ?_, ⟨{ Er with mode := R1.mode }, rfl, rfl, rfl, rfl, by simp [Er],
      fun d hd => Or.inl (res_region d hd), fun _ h => by simp [idv, vsi, Ty.holdsView] at h⟩,
    fun i hi b hb => ?_⟩
  · intro pt hpt; simp [idv] at hpt; subst hpt; exact ⟨rfl, fun _ => rfl, fun _ h => by cases h⟩
  · intro v E h
    simp only [D1, setE, upd] at h
    split at h
    · cases h; exact ⟨rfl, rfl⟩
    · simp only [kill] at h
      obtain ⟨E', h', rfl⟩ := Option.map_eq_some_iff.mp h
      simp only [G1, setE, upd] at h'
      split at h'
      · cases h'; simp [killE_dtor, killE_dbind, E0]
      · simp only [kill] at h'
        obtain ⟨E'', h'', rfl⟩ := Option.map_eq_some_iff.mp h'
        have := sig_flags v E'' h''
        simp [killE_dtor, killE_dbind, this.1, this.2.1]
  · simp [idv] at hi; subst hi; simp [idv] at hb

/-! ### The one typing of a move, and of a view, into the result slot -/

/-- What every live entry of a binding holds, every live entry of a context
    it is weaker than holds. -/
theorem weaker_held {Γ Γ0 : Ctx} {v : Var} {d : Dep} (hw : Weaker Γ Γ0)
    (h0 : ∀ E, Γ v = some E → E.live = true → d ∈ E.held) :
    ∀ E, Γ0 v = some E → E.live = true → d ∈ E.held := by
  intro E hE hl
  cases hg : Γ v with
  | none => rw [(hw.1 v).1.1 hg] at hE; cases hE
  | some E1 =>
    obtain ⟨hl1, _, hh⟩ := ((hw.1 v).2 E1 E hg hE).live hl
    exact hh (h0 E1 hg hl1)

/-- ... and so it is of a binding's mode ... -/
theorem weaker_mode {Γ Γ0 : Ctx} {v : Var} {m : Mode} (hw : Weaker Γ Γ0)
    (h0 : ∀ E, Γ v = some E → E.live = true → E.mode = m) :
    ∀ E, Γ0 v = some E → E.live = true → E.mode = m := by
  intro E hE hl
  cases hg : Γ v with
  | none => rw [(hw.1 v).1.1 hg] at hE; cases hE
  | some E1 =>
    have hwk := (hw.1 v).2 E1 E hg hE
    rw [hwk.mode]; exact h0 E1 hg (hwk.live hl).1

/-- ... and of a borrow's dependency on a root. -/
theorem weaker_path {Γ Γ0 : Ctx} {v r : Var} (hw : Weaker Γ Γ0)
    (h0 : ∀ E, Γ v = some E → E.live = true → E.mode = .bor ∧ ∃ k, (⟨r, k⟩ : Dep) ∈ E.path) :
    ∀ E, Γ0 v = some E → E.live = true → E.mode = .bor ∧ ∃ k, (⟨r, k⟩ : Dep) ∈ E.path := by
  intro E hE hl
  cases hg : Γ v with
  | none => rw [(hw.1 v).1.1 hg] at hE; cases hE
  | some E1 =>
    have hwk := (hw.1 v).2 E1 E hg hE
    obtain ⟨hl1, hp, _⟩ := hwk.live hl
    obtain ⟨hm, k, hk⟩ := h0 E1 hg hl1
    exact ⟨by rw [hwk.mode, hm], k, hp (by rw [hm]; rfl) hk⟩

/-- Whatever subsumptions it takes, `= r vv` leaves the result holding what
    `vv` held. -/
theorem move_res {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {d : Dep}
    (h : StmtT Q ξ Γ F (.assign 1 (.var 0)) Δ) :
    (∀ E, Γ 0 = some E → E.live = true → d ∈ E.held) →
    ∀ E, Δ 1 = some E → E.live = true → d ∈ E.held := by
  generalize hst : Stmt.assign 1 (.var 0) = st at h
  induction h with
  | assign _ _ _ hr =>
    cases hst
    intro h0 E hE _
    simp only [setE, upd, ↓reduceIte] at hE
    cases hE
    cases hr with
    | moveOwn hy hl => have := h0 _ hy hl; exact this
    | copyRoot hy hl => have := h0 _ hy hl; exact this
    | copyBor hy hl => have := h0 _ hy hl; exact this
    | moveUp hy hl => have := h0 _ hy hl; exact this
    | copyUp hy hl => have := h0 _ hy hl; exact this
  | sub hw _ hΔ ih =>
    intro h0
    rcases hΔ with rfl | hΔ
    · exact ih hst (weaker_held hw h0)
    · exact weaker_held hΔ (ih hst (weaker_held hw h0))
  | _ => cases hst

/-- Whatever subsumptions it takes, `= r ( view v )` of an owned `v` leaves
    the result a borrow of `v`. -/
theorem view_res {Q : Prog} {ξ : Exits} {Γ Δ : Ctx} {F : List Var}
    (h : StmtT Q ξ Γ F (.assign 1 (.view 0)) Δ) :
    (∀ E, Γ 0 = some E → E.live = true → E.mode = .own) →
    ∀ E, Δ 1 = some E → E.live = true → E.mode = .bor ∧ ∃ k, (⟨0, k⟩ : Dep) ∈ E.path := by
  generalize hst : Stmt.assign 1 (.view 0) = st at h
  induction h with
  | assign _ _ hm hr =>
    cases hst
    intro h0 E hE _
    simp only [setE, upd, ↓reduceIte] at hE
    cases hE
    cases hr with
    | view hy hl =>
      have hmo := h0 _ hy hl
      refine ⟨?_, ?_⟩
      · rcases hm with ⟨_, h2⟩ | ⟨_, h2⟩ | ⟨h1, _⟩
        · cases h2
        · cases h2
        · exact h1
      · simp [derive, hmo, Mode.isRoot]
  | sub hw _ hΔ ih =>
    intro h0
    rcases hΔ with rfl | hΔ
    · exact ih hst (weaker_mode hw h0)
    · exact weaker_path hΔ (ih hst (weaker_mode hw h0))
  | _ => cases hst

/-- ... and was not before regions were on: under no summary was it
    `FnOK0`, its result's view of the region being of no lendable
    parameter. -/
theorem idv_not_ok0 (rs : List (Nat × Kind)) : ¬ FnOK0 P { idv with rholds := rs } := by
  rintro ⟨_, _, _, _, _, _, _, hrs, _, _, _, _, Δ, hb, _, ⟨E, hE, hl, _, _, _, hh, _⟩, _⟩
  have hsig : sigCtx { idv with rholds := rs } = sigCtx idv := rfl
  rw [hsig] at hb
  have hd := move_res hb (d := ⟨2, .view⟩) (fun E' hE' _ => by
    rw [sig_eq] at hE'; cases hE'; simp [E0]) E hE hl
  obtain ⟨⟨hlt, _⟩, _⟩ := hrs _ (hh _ hd)
  simp [idv] at hlt

/-! ### A borrowed result viewing the region (turn-on 4) -/

/-- `vat vv`: returns `( vec_at vv 0 )`, a `[s` element of its `sink`
    parameter `vv : Vec [s`, borrowed. `vv` is 0, the result slot 1, `π vv`
    is `2`. -/
def vat : Fn where
  params   := [(.sink, vsi)]
  resTy    := .slice .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := .assign 1 (.at 0 (.lit 0))
  nvars    := 2

def R2 : Entry := ⟨.slice .int, .bor, false, [], [], false, false, false, false⟩

theorem vat_sig_eq : sigCtx vat = fun v =>
    if v = 0 then some E0 else if v = 1 then some R2 else if v = 2 then some regionE else none := by
  funext v
  rcases v with _ | _ | _ | v <;>
    simp [sigCtx, isRegionIdx, regionP, regioned, paramE, vat, vsi, Ty.holdsView, Ty.hasFn, resMode, E0, R2]

theorem vat_sig_flags : ∀ v E, sigCtx vat v = some E → E.dtor = false ∧ E.dbind = false ∧ E.mode ≠ .rootb := by
  intro v E h
  rcases v with _ | _ | _ | v <;> simp [vat_sig_eq] at h <;> subst h <;> simp [E0, R2, regionE]

/-- The element: what `vv` holds, the view of its region, is what it borrows
    and what it holds. -/
def Ea : Entry := ⟨.slice .int, .bor, true, E0.held, E0.held, false, false, false, false⟩
def D2 : Ctx := setE (kill .replace false 1 (sigCtx vat)) 1 Ea

theorem vat_body_typed : StmtT P .none (sigCtx vat) [] vat.body D2 := by
  have h := StmtT.assign (P := P) (ξ := .none) (F := []) (x := 1) (r := .at 0 (.lit 0)) (Ex := R2)
    (E := { elemE 0 E0 (.slice .int) with fresh := false }) (by rw [vat_sig_eq]; rfl) (by simp)
    (Or.inr (Or.inr ⟨rfl, rfl⟩))
    (RhsT.at (by rw [vat_sig_eq]; rfl) rfl rfl ExprT.lit (fun h => by cases h))
    rfl (by simp [elemE, E0, roots, Entry.vdeps, Mode.ownSlot]) (by rw [vat_sig_eq]; rfl)
    (fun p E hp hm => absurd hm (vat_sig_flags p E hp).2.2)
    (DtorSafe.of_none (fun v E h => (vat_sig_flags v E h).1) _ _ _) rfl
  exact h

/-- **`vat` is well-typed**: its result borrows what its `sink` parameter's
    region stands for. Before turn-on 4 the result's path could name only a
    lendable parameter (`lends`), and the view is of none. -/
theorem vat_ok : FnOK P vat := by
  have hro : vat.resOwn = false := rfl
  refine ⟨rfl, by decide, by decide, rfl, fun h => absurd h (by rw [hro]; simp), ?_, by simp [vat],
    by simp [vat], by simp [vat], by simp [vat], by simp [vat],
    dtorParamsOK_of (by simp [vat, vsi, Ty.holdsDtor]) (fun h => absurd h (by rw [hro]; simp)), _,
    vat_body_typed, ?_, ⟨Ea, rfl, rfl, rfl, rfl, ?_, ?_, fun h => absurd h (by rw [hro]; simp)⟩,
    fun i hi b hb => ?_⟩
  · intro pt hpt; simp [vat] at hpt; subst hpt; exact ⟨rfl, fun _ => rfl, fun _ h => by cases h⟩
  · intro v E h
    simp only [D2, setE, upd] at h
    split at h
    · cases h; exact ⟨rfl, rfl⟩
    · simp only [kill] at h
      obtain ⟨E', h', rfl⟩ := Option.map_eq_some_iff.mp h
      have := vat_sig_flags v E' h'
      simp [killE_dtor, killE_dbind, this.1, this.2.1]
  · intro d hd; simp only [Ea, E0, List.mem_singleton] at hd; subst hd; exact Or.inl rfl
  · intro d hd; simp only [Ea, E0, List.mem_singleton] at hd; subst hd; exact Or.inl rfl
  · simp [vat] at hi; subst hi; simp [vat] at hb

/-! ### The call -/

/-- The caller: `w` (0) owns a `Vec`, `v` (1) a `Vec` of slices viewing it. -/
def Ew : Entry := ⟨.vec .int, .own, true, [], [], false, false, false, false⟩
def Ev : Entry := ⟨vsi, .own, true, [], [⟨0, .view⟩], false, false, false, false⟩
def K : Ctx := setE (setE (fun _ => none) 0 Ew) 1 Ev

theorem K_flags : ∀ v E, K v = some E → E.dtor = false ∧ E.dbind = false ∧ E.mode ≠ .rootb := by
  intro v E h
  rcases v with _ | _ | v <;> simp [K, setE, upd] at h <;> subst h <;> simp [Ew, Ev]

theorem idv_not_thru : ¬ ThruFn P 0 := by
  intro h
  cases h with
  | here hf hb => simp [P] at hf; subst hf; simp [idv, Stmt.hasThru] at hb
  | call hf hg _ => simp [P] at hf; subst hf; simp [idv, Stmt.calls] at hg

theorem mutNames_v : mutNames K [1] = [] := by
  simp [mutNames, argNames, argE, K, setE, upd, Ev, nameDeps, Entry.vdeps, Mode.ownSlot, Kind.isName, vsi]

/-- **`( idv v )` types**: `v` handed over, `sink`. -/
theorem call_ok : CallT P K [] 0 [1] (callRes K idv [1]) (callPost K idv [1]) := by
  refine ⟨idv, rfl, rfl, fun i hi => ?_, fun d hd => ?_,
    CallDtorSafe.of_none (fun v E h => ⟨(K_flags v E h).1, (K_flags v E h).2.1⟩) _ _, rfl, rfl,
    fun h => absurd h idv_not_thru⟩
  · have hi' : i = 0 := by simpa [idv] using hi
    subst hi'
    refine ⟨Ev, by simp [K, setE, upd], rfl, ⟨rfl, rfl, rfl⟩, fun _ => ⟨by simp, ?_, fun _ => ?_, ?_, ?_⟩,
      fun _ p E hp hm => absurd hm (K_flags p E hp).2.2⟩
    · simp [Ev, roots, memDeps, Entry.vdeps, Mode.ownSlot, Kind.isName]
    · simp [Ev, roots, Entry.vdeps, Mode.ownSlot]
    · intro b hb; simp [idv] at hb
    · intro j hj hji; simp [idv] at hj; omega
  · rw [mutNames_v] at hd; cases hd

/-- **The caller's result holds the views the argument held**: what the
    callee's region stood for. -/
theorem callRes_holds : (⟨0, .view⟩ : Dep) ∈ (callRes K idv [1]).held := by
  simp [callRes, heldOfArgs, allKinds, argE, K, setE, upd, Ev, roots, memDeps, Kind.isName, ownHeld, idv, vsi,
    Ty.holdsView]

/-! ### A view of the `sink` parameter's own buffer is refused -/

/-- `vw v`: returns `( view v )` of its `sink` parameter `v`, under any
    summary. -/
def vw (ls rs : List (Nat × Kind)) : Fn where
  params   := [(.sink, .vec .int)]
  resTy    := .slice .int
  resOwn   := false
  lends    := ls
  rholds   := rs
  outHolds := []
  body     := .assign 1 (.view 0)
  nvars    := 2

/-- **A function returning a view of its `sink` parameter's own buffer is
    well-typed under no summary**: the view is of no lendable parameter, and
    the region is not what it views. -/
theorem vw_not_ok (ls rs : List (Nat × Kind)) : ¬ FnOK P (vw ls rs) := by
  rintro ⟨_, _, _, _, _, _, hls, _, _, _, _, _, Δ, hb, _, ⟨E, hE, hl, _, _, hp, _, _⟩, _⟩
  obtain ⟨_, k, hk⟩ := view_res hb (fun E' hE' _ => by
    simp [sigCtx, regionP, regioned, paramE, vw, Ty.holdsView] at hE'; subst hE'; rfl) E hE hl
  rcases hp _ hk with hr | hr
  · -- (turn-on 4: a borrow may be of a region, and `v` is none)
    simp [isRegionIdx, vw] at hr
  · obtain ⟨⟨hlt, hm⟩, _⟩ := hls _ hr
    simp [vw] at hm

/-- **Neither end check admits a dependency on a `sink` parameter**: it is
    no region's index, and not lendable. -/
theorem sink_dep_refused {fn : Fn} (hnv : fn.params.length < fn.nvars) {p : Nat} {t : Ty}
    (hp : fn.params[p]? = some (.sink, t))
    (hrs : ∀ jk ∈ fn.rholds, lendable fn jk.1 ∧ jk.2.isName = false) (k : Kind) :
    ¬ (isRegionIdx fn p = true ∨ (p, k) ∈ fn.rholds) := by
  have hpl := (List.getElem?_eq_some_iff.mp hp).1
  rintro (hr | hr)
  · have := isRegionIdx_ge hr; omega
  · obtain ⟨⟨hl, hm⟩, _⟩ := hrs _ hr
    have he : fn.params[p] = (.sink, t) := (List.getElem?_eq_some_iff.mp hp).2
    simp only [he] at hm
    rcases hm with hm | ⟨_, hm⟩ <;> cases hm

/-! ### A field of an owned struct, read past a sibling field's region -/

/-- `ftr sink (prod (Vec i) (Vec [s)) p`: its first field holds no view, its
    second views the caller's memory, the region `π p` (`2`). -/
def pvt : Ty := .prod (.vec .int) vsi

def ftr : Fn where
  params   := [(.sink, pvt)]
  resTy    := .int
  resOwn   := false
  lends    := []
  rholds   := []
  outHolds := []
  body     := .assign 1 (.expr (.lit 0))
  nvars    := 2

def Ep : Entry := ⟨pvt, .own, true, [], [⟨2, .view⟩], false, false, false, false⟩

theorem ftr_sig0 : sigCtx ftr 0 = some Ep := by
  simp [sigCtx, regionP, regioned, paramE, ftr, pvt, vsi, Ty.holdsView, Ty.hasFn, Ep]

theorem ftr_sig2 : sigCtx ftr 2 = some regionE := by
  simp [sigCtx, isRegionIdx, regioned, ftr, pvt, vsi, Ty.holdsView]

/-- **A borrow of the first field depends on the struct alone**: what the
    second field's views point into is no part of it (`projHeld`). -/
theorem fst_path : (projE 0 Ep (.vec .int)).path = [⟨0, .inner⟩] := by
  simp [projE, projDeps, projHeld, Ep, Mode.ownSlot, Ty.holdsView, Ty.hasFn]

/-- **So a truncation through it passes `ThruOK`**: the struct is an owned
    `sink` parameter, which may drop its elements. -/
theorem fst_trunc_ok : ThruOK (sigCtx ftr) [] (.trunc (.lit 0)) (.vec .int) (projE 0 Ep (.vec .int)).path := by
  rw [fst_path]
  intro d hd
  simp only [memDeps, List.filter_cons, Kind.isName, Bool.not_false, ↓reduceIte, List.filter_nil,
    List.mem_singleton] at hd
  subst hd
  refine ⟨List.not_mem_nil, fun y hy => (by simp [Edit.stored] at hy), Ep, ftr_sig0, rfl, Or.inl rfl,
    DtorSafe.of_none (fun v E h => ?_) _ _ _, (by decide)⟩
  rcases v with _ | _ | _ | v <;>
    simp [sigCtx, isRegionIdx, regionP, regioned, paramE, ftr, pvt, vsi, Ty.holdsView, Ty.hasFn, resMode] at h <;>
    subst h <;> rfl

/-- **Before, it did not**: the field's path carried the struct's held view of
    the region, which no change may go through. -/
theorem fst_trunc_old_refused :
    ¬ ThruOK (sigCtx ftr) [] (.trunc (.lit 0)) (.vec .int) (projDeps 0 Ep ++ Ep.held) := by
  intro h
  obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := h ⟨2, .view⟩ (by simp [memDeps, Kind.isName, Ep, projDeps, Mode.ownSlot])
  rw [ftr_sig2] at hEr; cases hEr
  rcases hcan with h | ⟨_, h, _⟩ <;> cases h

/-- **The second field still carries the region**: a slice of the caller's
    memory is lent with what it depends on, and a truncation through it is
    refused. -/
theorem snd_trunc_refused :
    ¬ ThruOK (sigCtx ftr) [] (.trunc (.lit 0)) vsi (projE 0 Ep vsi).path := by
  intro h
  obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := h ⟨2, .view⟩
    (by simp [memDeps, Kind.isName, Ep, projE, projDeps, projHeld, Mode.ownSlot, vsi, Ty.holdsView])
  rw [ftr_sig2] at hEr; cases hEr
  rcases hcan with h | ⟨_, h, _⟩ <;> cases h

end A2.RegionResWitness
