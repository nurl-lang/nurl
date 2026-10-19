import A2.CallInv

/-! A2 — a call through a package (a closure or a trait object).

Where the call is typed, the code the package holds is not known; what is
known is the interface of the method called, a function of the program whose
first parameter is the receiver.  The call is typed as a call of the
interface, with the package lent as the receiver.  Every package names code
that implements its interfaces (`MemCodes`): code that takes the package's
environment where the interface takes the receiver, the other parameters as
the interface does, and returns, lends and stores no more than it says.

The call opens the package: its environment, lent, is bound to a fresh
borrowed parameter `e` of the caller, whose dependencies are held still for
the call; the code is called on `e` and the arguments as an ordinary call;
when it returns, what it lent from the environment depends on what the
package depended on. -/

namespace A2

/-- A live package binding holds a package of its interfaces. -/
theorem pkg_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c : Var} {E : Entry} (hc : Γ c = some E)
    (hl : E.live = true) {ms : List Nat} (ht : E.ty = .fn ms) :
    ∃ o fs te env cs, m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩ := by
  rcases hi.mode_cases hc with hm | hm | hm
  · obtain ⟨T, hT, hw, _⟩ := hi.own_val hc hl (by rw [hm]; rfl)
    rw [ht] at hw; cases hw
    exact ⟨_, _, _, _, _, hT⟩
  all_goals
    obtain ⟨v, hv, hok⟩ := hi.bor_val hc hl (by rw [hm]; rfl)
    rw [ht] at hok; obtain ⟨fs, te, x, cs, rfl, _⟩ := valOK_fn.mp hok
    exact ⟨_, _, _, _, _, hv⟩

/-- The captures a live package names are live, owning, view-free bindings of
    the context, of the recorded types, each read or changed as recorded.  (A
    capture it may change is reached from nothing else the package holds, by
    `PkgsOK`, but that is used where the call is set up.) -/
theorem pkg_caps {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c : Var} {Ec : Entry} (hc : Γ c = some Ec)
    (hl : Ec.live = true) {ms : List Nat} (ht : Ec.ty = .fn ms) {o : Bool} {fs : List Nat} {te : Ty}
    {env : Val} {cs : List (Var × PMode × Ty)} (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩) :
    (cs.map (·.1)).Nodup ∧
    (∀ ci ∈ cs, ∀ ci' ∈ env.names, ci.1 = ci'.1 → ci.2.1 = .inp ∧ ci'.2.1 = .inp) ∧
    ∀ ci ∈ cs, ∃ Ev, Γ ci.1 = some Ev ∧ Ev.live = true ∧ Ev.held = [] ∧ Ev.ty = ci.2.2 ∧
      Ev.mode.ownSlot = true ∧ ci.2.2.holdsView = false ∧
      (ci.2.1.bound = .none ∨ ci.2.1.bound ≠ .replace ∧ canDo Ev.mode ci.2.1.bound) := by
  have hpk := hi.pkgs c _ _ hslot rfl
  obtain ⟨hnd, _, hcap⟩ := hpk fs te ms env cs (Sub.refl _)
  have hnames := hi.held c Ec _ _ hc hl hslot rfl
  have hN := (hi.names c Ec hc hl (Or.inl (by rw [ht]; simp))).held
  refine ⟨hnd, fun ci hci ci' hci' hcc => (hpk fs te ms env cs (Sub.refl _)).2.2 ci hci ci' hci' hcc,
    fun ci hci => ?_⟩
  have hin : (⟨ci.1, .name ci.2.1.bound ci.2.2⟩ : Dep) ∈ Ec.held :=
    hnames ci (by simp only [Val.names, List.mem_append]; exact Or.inl hci)
  obtain ⟨Ev, hEv, hlv, hhv, htv, hov, hcc, hvv⟩ :=
    hN ⟨ci.1, .name ci.2.1.bound ci.2.2⟩ hin ci.2.1.bound ci.2.2 rfl
  exact ⟨Ev, hEv, hlv, hhv, htv, hov, hvv, hcc⟩

/-- The environment of a package, opened for a call: a borrowed parameter of
    the caller, valid through what the package depends on. -/
def envE (c : Var) (Ec : Entry) (te : Ty) : Entry :=
  ⟨te, .rootb, true, derive c Ec .self ++ Ec.held, Ec.held⟩

theorem derive_bor_self {y : Var} {E : Entry} (h : E.mode.isRoot = false) : derive y E .self = E.path := by
  unfold derive
  simp only [h, Bool.false_eq_true, ↓reduceIte]
  conv => rhs; rw [← List.map_id E.path]
  congr; funext dep; cases dep with | mk r k => cases k <;> rfl

/-- Adding a borrowed parameter. -/
theorem MInv.addRootb {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} (hx : Γ x = none) (hxn : x < m.nv)
    {E : Entry} {v : Val} (hm : E.mode = .rootb) (hl : E.live = true) (htok : E.ty.ok = true)
    (hok : ValOK m E.ty v E.path E.held)
    (hwf : ∀ r ∈ roots E.vdeps, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true)
    (hlt : ∀ r ∈ roots E.vdeps, r < x)
    (hvnames : NamesIn v E.held) (hvpkgs : PkgsOK v) (hnameOK : NameOK (setE Γ x E) E) :
    MInv (m.set x ⟨false, some v⟩) (setE Γ x E) := by
  have hmx : m.st x = none := by
    have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
  have hext : ∀ o', m.st o' ≠ none → (m.set x ⟨false, some v⟩).st o' = m.st o' := by
    intro o' ho'
    have : o' ≠ x := fun h => ho' (h ▸ hmx)
    simp [upd_ne _ _ this]
  have hroot : ∀ r Er, Γ r = some Er → r ≠ x := fun r Er h hr => by rw [hr, hx] at h; cases h
  have hos : E.mode.ownSlot = false := by rw [hm]; rfl
  constructor
  · intro w
    by_cases hw : w = x
    · subst hw; simp [setE]
    · simp only [setE, upd_ne _ _ hw, Mem.set_st]; exact hi.dom w
  · intro w Ew hw
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      refine ⟨⟨false, some v⟩, by simp, htok, ⟨by show false = E.mode.ownSlot; rw [hos],
        (fun h => by rw [hos] at h; cases h), fun _ _ => ⟨v, rfl, hok.keep (fun dep _ => ?_) (fun dep _ => ?_)⟩⟩⟩
      · exact ⟨(rootKeep_ext hext dep.root).vkeep, (rootKeep_ext hext dep.root).hkeep⟩
      · exact ⟨(rootKeep_ext hext dep.root).vkeep, (rootKeep_ext hext dep.root).hkeep⟩
    · simp only [setE, upd_ne _ _ hwx] at hw
      obtain ⟨sl, hsl, hok', hslot⟩ := hi.slot w Ew hw
      exact ⟨sl, by simp [upd_ne _ _ hwx, hsl], hok', hslot.ext hext⟩
  · exact hi.heap.set_bor x _
  · intro w hw
    by_cases hwx : w = x
    · subst hwx; exact hxn
    · simp only [Mem.set_st, upd_ne _ _ hwx] at hw; exact hi.nvSt w hw
  · intro w Ew b hw
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw; rw [hm]; simp
    · simp only [setE, upd_ne _ _ hwx] at hw; exact hi.noInout w Ew b hw
  · intro w Ew hw hl' hn r hr
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw
      subst hw
      obtain ⟨Er, hEr, hro⟩ := hwf r hr
      exact ⟨Er, by simp [setE, upd_ne _ _ (hroot r Er hEr), hEr], hro⟩
    · simp only [setE, upd_ne _ _ hwx] at hw
      obtain ⟨Er, hEr, hro⟩ := hi.wf w Ew hw hl' hn r hr
      exact ⟨Er, by simp [setE, upd_ne _ _ (hroot r Er hEr), hEr], hro⟩
  · intro p Ep hp hm'
    by_cases hpx : p = x
    · subst hpx
      simp only [setE, upd_same, Option.some.injEq] at hp
      subst hp; exact hl
    · simp only [setE, upd_ne _ _ hpx] at hp; exact hi.rootbLive p Ep hp hm'
  · intro p Ep hp hm'
    by_cases hpx : p = x
    · subst hpx
      simp only [setE, upd_same, Option.some.injEq] at hp
      subst hp; exact hlt
    · simp only [setE, upd_ne _ _ hpx] at hp; exact hi.rootbLt p Ep hp hm'
  · intro w Ew hw hl' hn
    by_cases hwx : w = x
    · subst hwx; simp only [setE, upd_same, Option.some.injEq] at hw; subst hw; exact hnameOK
    · simp only [setE, upd_ne _ _ hwx] at hw
      have hk : Keeps Γ (setE Γ x E) [] := fun y Ey hy =>
        ⟨Ey, by have hne : y ≠ x := fun e => by rw [e, hx] at hy; cases hy
                simp [setE, upd_ne _ _ hne, hy], rfl, rfl, fun _ h => h⟩
      exact (hi.names w Ew hw hl' hn).keeps hk (fun d hd hkd hX => by cases hX)
  · intro w Ew sl T hw hl' hsl hT
    by_cases hwx : w = x
    · subst hwx
      simp only [setE, upd_same, Option.some.injEq] at hw; subst hw
      simp only [Mem.set, upd_same, Option.some.injEq] at hsl; subst hsl
      simp only [Option.some.injEq] at hT; subst hT; exact hvnames
    · simp only [setE, upd_ne _ _ hwx] at hw
      rw [Mem.set_st, upd_ne _ _ hwx] at hsl
      exact hi.held w Ew sl T hw hl' hsl hT
  · intro w sl T hsl hT
    by_cases hwx : w = x
    · subst hwx
      simp only [Mem.set, upd_same, Option.some.injEq] at hsl; subst hsl
      simp only [Option.some.injEq] at hT; subst hT; exact hvpkgs
    · rw [Mem.set_st, upd_ne _ _ hwx] at hsl; exact hi.pkgs w sl T hsl hT

/-- The receiver of a call through a package is live. -/
theorem callT_recv_live {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {σ : Nat} {c : Var} {zs : List Var}
    {E Ec : Entry} (hcT : CallT P Γ F σ (c :: zs) E Γ1) (hc : Γ c = some Ec) : Ec.live = true := by
  obtain ⟨sig, _, hlen, hargs, _, _⟩ := hcT
  obtain ⟨Ea, hEa, hl, _⟩ := hargs 0 (by rw [← hlen]; simp)
  simp only [List.getD_cons_zero] at hEa
  rw [hc] at hEa; cases hEa; exact hl

/-- The code a package runs for its method `j`, implementing the method's
    interface. -/
theorem pkg_code {P : Prog} {m : Mem} (hcd : MemCodes P m) {c : Var} {o : Bool} {fs : List Nat}
    {te : Ty} {ms : List Nat} {env : Val} {cs : List (Var × PMode × Ty)}
    (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩)
    {j σ : Nat} (hj : ms[j]? = some σ) {sig : Fn} (hσ : P[σ]? = some sig) :
    ∃ f fn, fs[j]? = some f ∧ P[f]? = some fn ∧
      fn.params = (.inp, te) :: sig.params.tail ++ cs.map (·.2) ∧
      fn.resTy = sig.resTy ∧ fn.resOwn = sig.resOwn ∧ fn.lends ⊆ sig.lends ∧
      fn.rholds ⊆ sig.rholds ∧ fn.outHolds ⊆ sig.outHolds := by
  obtain ⟨hlen, himpl⟩ := hcd c o _ fs te ms env cs hslot (Sub.refl _)
  have hjl : j < fs.length := by rw [hlen]; exact (List.getElem?_eq_some_iff.mp hj).1
  have hfs : fs[j]? = some fs[j] := List.getElem?_eq_getElem hjl
  obtain ⟨fn, sig', hf, hσ', h⟩ := himpl j fs[j] σ hfs hj
  rw [hσ] at hσ'; cases hσ'
  exact ⟨fs[j], fn, hfs, hf, h⟩

/-- The roots the opened environment depends on: the package, or what it
    depends on. -/
theorem envE_roots {c : Var} {Ec : Entry} {te : Ty} {r : Var} (hr : r ∈ roots (envE c Ec te).vdeps) :
    r = c ∨ r ∈ roots Ec.vdeps := by
  simp only [envE, Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, roots, List.map_append,
    List.mem_append] at hr
  rcases hr with (hr | hr) | hr
  · rcases derive_roots_cases hr with ⟨rfl, _⟩ | ⟨_, h⟩
    · exact Or.inl rfl
    · exact Or.inr h
  · exact Or.inr (held_vdeps hr)
  · exact Or.inr (held_vdeps hr)

/-! ### The cleaned context

The code of a package runs where every dead or integer binding has
forgotten what it depended on, as the frame of an ordinary call does: what
it depended on says nothing, and the environment's binding, fresh, must be
on no dependency when it is dropped. -/

noncomputable def cleanC (Γ : Ctx) : Ctx := fun v => (Γ v).map Entry.clean

theorem clean_weaker (E : Entry) : EntryWeaker E.clean E := by
  unfold Entry.clean; split
  · rename_i h
    exact ⟨rfl, rfl, fun hr => absurd (by simpa [Entry.fixed_def] using hr) h.1,
      fun hl => ⟨hl, fun _ => List.nil_subset _, List.nil_subset _⟩⟩
  · exact EntryWeaker.refl E

theorem clean_path_sub (E : Entry) : E.clean.path ⊆ E.path := by
  unfold Entry.clean; split <;> try split
  · exact List.nil_subset _
  · exact List.Subset.refl _

theorem clean_held_sub (E : Entry) : E.clean.held ⊆ E.held := by
  unfold Entry.clean; split
  · exact List.nil_subset _
  · exact List.Subset.refl _

theorem clean_vdeps_sub (E : Entry) : E.clean.vdeps ⊆ E.vdeps := by
  unfold Entry.vdeps; rw [clean_mode]
  intro d hd
  rcases List.mem_append.mp hd with hd | hd
  · refine List.mem_append_left _ ?_
    split
    · split at hd <;> simp_all
    · split at hd
      · simp_all
      · exact clean_path_sub E hd
  · exact List.mem_append_right _ (clean_held_sub E hd)

theorem clean_rootb {E : Entry} (h : E.mode = .rootb) : E.clean = E :=
  clean_fixed (Or.inl h)

/-- A cleaned binding depends on no binding outside the context. -/
theorem clean_noE {Γ : Ctx} (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    {e : Var} (he : Γ e = none) {v : Var} {E : Entry} (hv : Γ v = some E) :
    ∀ d ∈ E.clean.vdeps, d.root ≠ e := by
  intro d hd hde
  unfold Entry.clean at hd; split at hd
  · simp [Entry.vdeps] at hd
  · rename_i h
    have hc : E.live = true ∧ (E.ty ≠ .int ∨ E.mode = .rootb) := by
      by_cases hm : E.mode = .rootb
      · exact ⟨hrl v E hv hm, Or.inr hm⟩
      · have hnf : ¬ E.fixed := by
          rintro (hrb | ⟨b, hb, _⟩)
          · exact hm hrb
          · exact hni v E b hv hb
        have : ¬ (E.ty = .int ∨ E.live = false) := fun h' => h ⟨hnf, h'⟩
        simp only [not_or, Bool.not_eq_false] at this
        exact ⟨this.2, Or.inl this.1⟩
    obtain ⟨Er, hEr, _⟩ := hw v E hv hc.1 hc.2 d.root (List.mem_map_of_mem hd)
    rw [hde, he] at hEr; cases hEr

theorem cleanC_some {Γ : Ctx} {v : Var} {E : Entry} (h : cleanC Γ v = some E) :
    ∃ E0, Γ v = some E0 ∧ E = E0.clean := by
  unfold cleanC at h
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp h
  exact ⟨E0, h0, rfl⟩

theorem cleanC_of {Γ : Ctx} {v : Var} {E : Entry} (h : Γ v = some E) : cleanC Γ v = some E.clean := by
  simp [cleanC, h]

theorem cleanC_none {Γ : Ctx} {v : Var} : cleanC Γ v = none ↔ Γ v = none := by
  simp [cleanC]

theorem argE_clean (Γ : Ctx) (a : Var) : argE (cleanC Γ) a = (argE Γ a).clean := by
  unfold argE cleanC
  cases Γ a <;> simp [Entry.clean, intE, Entry.fixed_def]

theorem clean_held_nil {E : Entry} (h : E.held = []) : E.clean.held = [] :=
  List.eq_nil_of_subset_nil (h ▸ clean_held_sub E)

theorem cleanC_names {Γ : Ctx} (hn : NameWF Γ) : NameWF (cleanC Γ) := by
  intro v E hv hl hnn
  obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
  rw [clean_live] at hl; rw [clean_ty, clean_mode] at hnn
  have hid : E0.clean = E0 := clean_id hnn hl
  rw [hid] at hv ⊢
  intro d hd b t hk
  obtain ⟨Er, hEr, hlr, hhr, htr, hor, hcr, hvr⟩ := hn v E0 h0 hl hnn d hd b t hk
  exact ⟨Er.clean, cleanC_of hEr, by rw [clean_live]; exact hlr, clean_held_nil hhr,
    by rw [clean_ty]; exact htr, by rw [clean_mode]; exact hor, by rw [clean_mode]; exact hcr, hvr⟩

theorem MInv.clean {m : Mem} {Γ : Ctx} (hi : MInv m Γ) : MInv m (cleanC Γ) where
  names := cleanC_names hi.names
  held v E sl T hv hl hsl hT := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
    rw [clean_live] at hl
    by_cases hint : E0.ty = .int
    · obtain ⟨sl', hsl', hty0, hslot⟩ := hi.slot v E0 h0
      rw [hsl] at hsl'; cases hsl'
      have hnm : T.names = [] := names_nil_of_int hslot hint hl hT
      intro c hc; rw [hnm] at hc; cases hc
    · rw [clean_id (Or.inl hint) hl]; exact hi.held v E0 sl T h0 hl hsl hT
  pkgs v sl T hsl hT := hi.pkgs v sl T hsl hT
  dom v := by rw [← hi.dom v]; simp [cleanC]
  slot v E hv := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
    obtain ⟨sl, hsl, hty, hok⟩ := hi.slot v E0 h0
    exact ⟨sl, hsl, by rw [clean_ty]; exact hty, hok.clean⟩
  heap := hi.heap
  nvSt := hi.nvSt
  noInout v E b hv := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
    rw [clean_mode]; exact hi.noInout v E0 b h0
  wf v E hv hl hn r hr := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
    rw [clean_live] at hl; rw [clean_ty, clean_mode] at hn
    have hid : E0.clean = E0 := by
      rcases hn with hn | hn
      · exact clean_id (Or.inl hn) hl
      · exact clean_rootb hn
    rw [hid] at hr
    obtain ⟨Er, hEr, hro⟩ := hi.wf v E0 h0 hl hn r hr
    exact ⟨Er.clean, cleanC_of hEr, by rw [clean_mode]; exact hro⟩
  rootbLive p E hp hm := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hp
    rw [clean_mode] at hm; rw [clean_live]; exact hi.rootbLive p E0 h0 hm
  rootbLt p E hp hm := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hp
    rw [clean_mode] at hm; rw [clean_rootb hm]; exact hi.rootbLt p E0 h0 hm

theorem Inv.clean {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) :
    Inv m (cleanC Γ) F s :=
  { toMInv := hi.toMInv.clean
    nvS := hi.nvS
    nvF := hi.nvF
    anch := fun p E hp hm hs => by
      obtain ⟨E0, h0, rfl⟩ := cleanC_some hp
      rw [clean_mode] at hm; rw [clean_rootb hm]; exact hi.anch p E0 h0 hm hs
    spineNd := hi.spineNd
    spineDom := fun v hv => by
      obtain ⟨E, hE⟩ := hi.spineDom v hv
      exact ⟨_, cleanC_of hE⟩
    catchOK := hi.catchOK
    cover := hi.cover }

theorem derive_clean_sub (y : Var) (E : Entry) (k : Kind) : derive y E.clean k ⊆ derive y E k := by
  unfold derive; rw [clean_mode, clean_ty]
  split
  · exact List.Subset.refl _
  · exact List.map_subset _ (clean_path_sub E)

/-- Cleaning only shrinks what the arguments hold by name. -/
theorem argNames_clean (Γ : Ctx) (args : List Var) : argNames (cleanC Γ) args ⊆ argNames Γ args := by
  intro d hd
  simp only [argNames, List.mem_flatMap] at hd ⊢
  obtain ⟨a, ha, hda⟩ := hd
  refine ⟨a, ha, ?_⟩
  rw [argE_clean, clean_ty] at hda
  split at hda
  · simp at hda
  · rename_i hne; rw [if_neg hne]
    simp only [nameDeps, List.mem_filter] at hda ⊢
    exact ⟨clean_vdeps_sub _ hda.1, hda.2⟩

theorem mutNames_clean (Γ : Ctx) (args : List Var) : mutNames (cleanC Γ) args ⊆ mutNames Γ args := by
  intro d hd
  simp only [mutNames, List.mem_filter] at hd ⊢
  exact ⟨argNames_clean Γ args hd.1, hd.2⟩

/-- A call checked in a context is checked in its cleaned form. -/
theorem CallT.clean {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) {fn : Fn} (hf : P[f]? = some fn) :
    CallT P (cleanC Γ) F f args (callRes (cleanC Γ) fn args) (callPost (cleanC Γ) fn args) := by
  obtain ⟨fn', hf', hlen, hargs, hnf, _, _⟩ := hc
  rw [hf] at hf'; cases hf'
  refine ⟨fn, hf, hlen, fun i hi => ?_, fun d hd => ?_, rfl, rfl⟩
  rotate_left
  · simp only [argE_clean, clean_mode, clean_ty]
    obtain ⟨hcan, hvec, hnF, hnA, huniq⟩ := hnf d (mutNames_clean Γ args hd)
    refine ⟨hcan, hvec, hnF, hnA, fun a ha hc' d' hd' hdr => ?_⟩
    exact huniq a ha hc' d' (clean_vdeps_sub _ hd') hdr
  obtain ⟨Ea, hEa, hl, hok, hmv, hpin⟩ := hargs i hi
  refine ⟨Ea.clean, cleanC_of hEa, by rw [clean_live]; exact hl, ?_, fun hm => ?_, fun hs => ?_⟩
  · revert hok
    generalize fn.params[i] = p
    obtain ⟨pm, t⟩ := p
    cases pm <;> simp only [paramOK, clean_ty, clean_mode] <;> exact id
  · obtain ⟨hnF, hnr, hd⟩ := hmv hm
    refine ⟨hnF, fun h => hnr (List.map_subset _ (clean_vdeps_sub Ea) h), fun j hj hji => ?_⟩
    obtain ⟨hne, hnr'⟩ := hd j hj hji
    refine ⟨hne, fun h => hnr' ?_⟩
    rw [argE_clean] at h
    exact List.map_subset _ (clean_vdeps_sub _) h
  · -- NoPin transfers: cleaning keeps borrowed parameters as they are
    intro p E hp hrb d hd hbd
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hp
    rw [clean_mode] at hrb
    rw [clean_rootb hrb] at hd
    exact hpin hs p E0 h0 hrb d hd hbd

/-! ### After the opened call -/

/-- Outside the environment `e`, the bindings after the opened call say no
    less than those after the call through the package, and depend on no `e`. -/
def PostRel (e : Var) (Γd Γs : Ctx) : Prop :=
  ∀ v, v ≠ e → (Γd v = none ↔ Γs v = none) ∧
    ∀ Ed Es, Γd v = some Ed → Γs v = some Es → EntryWeaker Ed Es ∧ ∀ d ∈ Ed.vdeps, d.root ≠ e

theorem PostRel.kill {e : Var} {Γd Γs : Ctx} (h : PostRel e Γd Γs) (b : Eff) (hv : Bool) (a : Var) :
    PostRel e (kill b hv a Γd) (kill b hv a Γs) := by
  intro v hve
  obtain ⟨hn, hw⟩ := h v hve
  refine ⟨by simp [A2.kill, hn], fun Ed Es hd hs => ?_⟩
  simp only [A2.kill] at hd hs
  obtain ⟨Ed0, hd0, rfl⟩ := Option.map_eq_some_iff.mp hd
  obtain ⟨Es0, hs0, rfl⟩ := Option.map_eq_some_iff.mp hs
  obtain ⟨hw', hne⟩ := hw Ed0 Es0 hd0 hs0
  exact ⟨killE_weaker hw', by rw [killE_vdeps]; exact hne⟩

theorem PostRel.set {e : Var} {Γd Γs : Ctx} (h : PostRel e Γd Γs) {a : Var} (hae : a ≠ e) {Ed Es : Entry}
    (hw : EntryWeaker Ed Es) (hne : ∀ d ∈ Ed.vdeps, d.root ≠ e) :
    PostRel e (setE Γd a Ed) (setE Γs a Es) := by
  intro v hve
  by_cases hva : v = a
  · subst hva
    refine ⟨by simp [setE], fun Ed' Es' hd hs => ?_⟩
    simp only [setE, upd_same, Option.some.injEq] at hd hs
    subst hd hs; exact ⟨hw, hne⟩
  · simp only [setE, upd_ne _ _ hva]; exact h v hve

theorem post_rel {Γe Γ : Ctx} {fn sig : Fn} {A C : List Var} {e : Var}
    (hout : ∀ i, 1 ≤ i → outHeld Γe fn A i ⊆ outHeld Γ sig C i ∧ ∀ d ∈ outHeld Γe fn A i, d.root ≠ e)
    (hheld : heldOfArgs Γe A ⊆ heldOfArgs Γ C ∧ ∀ d ∈ heldOfArgs Γe A, d.root ≠ e) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γd Γs : Ctx), 1 ≤ i →
      (∀ a ∈ as, a ≠ e ∧ argE Γe a = (argE Γ a).clean ∧ ∀ d ∈ (argE Γe a).vdeps, d.root ≠ e) →
      (∀ p a, (p, a) ∈ ps.zip as → p.1 ≠ .inp → ¬ (argE Γ a).fixed) →
      PostRel e Γd Γs → PostRel e (callPostAux Γe fn A ps as i Γd) (callPostAux Γ sig C ps as i Γs) := by
  intro ps
  induction ps with
  | nil => intro as i Γd Γs _ _ _ h; cases as <;> simpa [callPostAux] using h
  | cons p ps ih =>
    intro as i Γd Γs hi has hrb h
    cases as with
    | nil => simpa [callPostAux] using h
    | cons a as =>
      obtain ⟨hae, hcl, hne⟩ := has a (by simp)
      have has' : ∀ a' ∈ as, _ := fun a' ha' => has a' (by simp [ha'])
      have hrb' : ∀ p' a', (p', a') ∈ ps.zip as → p'.1 ≠ .inp → ¬ (argE Γ a').fixed :=
        fun p' a' hm => hrb p' a' (by simp [hm])
      obtain ⟨pm, t⟩ := p
      have hrba : pm ≠ .inp → ¬ (argE Γ a).fixed := fun hp => hrb (pm, t) a (by simp) hp
      cases pm with
      | inp => exact ih as (i + 1) Γd Γs (by omega) has' hrb' h
      | sink =>
        refine ih as (i + 1) _ _ (by omega) has' hrb' ((h.kill _ _ a).set hae ?_ ?_)
        · rw [hcl]
          exact RSetup.EntryWeaker.mk' (by simp [clean_ty]) (by simp [clean_mode])
            (by rw [fixed_setLive, clean_fixed_iff]; exact hrba (by simp)) rfl
            (fun _ => clean_path_sub _) (clean_held_sub _)
        · exact fun d hd => hne d (by simpa [Entry.vdeps] using hd)
      | inout b =>
        refine ih as (i + 1) _ _ (by omega) has' hrb' ((h.kill _ _ a).set hae ?_ ?_)
        · rw [hcl]
          refine RSetup.EntryWeaker.mk' (by simp [clean_ty]) (by simp [clean_mode])
            (by rw [fixed_setHeld, clean_fixed_iff]; exact hrba (by simp)) (by simp [clean_live])
            (fun _ => clean_path_sub _) ?_
          intro d hd
          by_cases hvv : t.holdsView = true
          · rw [if_pos hvv] at hd ⊢
            simp only [List.mem_append] at hd ⊢
            rcases hd with (hd | hd) | hd
            · exact Or.inl (Or.inl (clean_held_sub _ hd))
            · exact Or.inl (Or.inr ((hout i hi).1 hd))
            · exact Or.inr (hheld.1 hd)
          · rw [if_neg hvv] at hd ⊢
            exact clean_held_sub _ hd
        · intro d hd
          have hv : ∀ d' ∈ (argE Γe a).vdeps, d'.root ≠ e := hne
          simp only [Entry.vdeps] at hd hv
          rcases List.mem_append.mp hd with hpath | hH
          · exact hv d (List.mem_append_left _ hpath)
          · split at hH
            · simp only [List.mem_append] at hH
              rcases hH with (hd' | hd') | hd'
              · exact hv d (List.mem_append_right _ hd')
              · exact (hout i hi).2 d hd'
              · exact hheld.2 d hd'
            · exact hv d (List.mem_append_right _ hH)
          all_goals exact hv d (List.mem_append_left _ hpath)

/-! ### What the opened call lends and holds

`e` binds the environment in the cleaned context; the arguments past the
receiver are the call's own. -/

section opened
variable {Γ : Ctx} {e c : Var} {Ec : Entry} {te : Ty} {zs : List Var}

theorem argE_open {a : Var} (ha : a ≠ e) :
    argE (setE (cleanC Γ) e (envE c Ec te)) a = (argE Γ a).clean := by
  unfold argE; rw [show setE (cleanC Γ) e (envE c Ec te) a = cleanC Γ a by simp [setE, upd_ne _ _ ha]]
  exact argE_clean Γ a

theorem argE_noE (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (a : Var) : ∀ d ∈ (argE Γ a).clean.vdeps, d.root ≠ e := by
  unfold argE
  cases h : Γ a with
  | none => simp [Entry.clean, intE, Entry.vdeps, Entry.fixed_def]
  | some E => exact clean_noE hw hrl hni he h

theorem argDeps_open (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) {jk : Nat × Kind} (hj : jk.1 ≠ 0) :
    argDeps (setE (cleanC Γ) e (envE c Ec te)) (e :: zs) jk ⊆ argDeps Γ (c :: zs) jk ∧
      ∀ d ∈ argDeps (setE (cleanC Γ) e (envE c Ec te)) (e :: zs) jk, d.root ≠ e := by
  obtain ⟨j, k⟩ := jk
  obtain ⟨j, rfl⟩ : ∃ j', j = j' + 1 := ⟨j - 1, by simp at hj; omega⟩
  unfold argDeps
  simp only [List.getD_cons_succ]
  rw [argE_open (hzs j), clean_ty]
  split
  · exact ⟨List.nil_subset _, by simp⟩
  · refine ⟨derive_clean_sub _ _ _, fun d hd hde => ?_⟩
    rcases derive_roots_cases (List.mem_map_of_mem (f := Dep.root) hd) with ⟨h, _⟩ | ⟨_, h⟩
    · exact hzs j (h ▸ hde)
    · obtain ⟨d', hd', hr⟩ := List.mem_map.mp h
      exact argE_noE hw hrl hni he _ d' hd' (hr.trans hde)

theorem argDeps_zero {jk : Nat × Kind} (hj : jk.1 = 0) :
    ∀ d ∈ argDeps (setE (cleanC Γ) e (envE c Ec te)) (e :: zs) jk, d.root = e := by
  obtain ⟨j, k⟩ := jk
  simp only at hj; subst hj
  have hE : argE (setE (cleanC Γ) e (envE c Ec te)) e = envE c Ec te := by simp [argE, setE]
  unfold argDeps
  simp only [List.getD_cons_zero, hE]
  split
  · simp
  · simp [derive, envE, Mode.isRoot]

theorem outHeld_open {fn sig : Fn} (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hsub : fn.outHolds ⊆ sig.outHolds)
    (hnz : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0) (i : Nat) :
    outHeld (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs) i ⊆ outHeld Γ sig (c :: zs) i ∧
      ∀ d ∈ outHeld (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs) i, d.root ≠ e := by
  unfold outHeld
  refine ⟨fun d hd => ?_, fun d hd => ?_⟩
  · obtain ⟨o, ho, hdo⟩ := List.mem_flatMap.mp hd
    obtain ⟨ho1, ho2⟩ := List.mem_filter.mp ho
    have hos := hsub ho1
    exact List.mem_flatMap.mpr ⟨o, List.mem_filter.mpr ⟨hos, ho2⟩,
      (argDeps_open hw hrl hni he hzs (hnz o hos)).1 hdo⟩
  · obtain ⟨o, ho, hdo⟩ := List.mem_flatMap.mp hd
    exact (argDeps_open hw hrl hni he hzs (hnz o (hsub (List.mem_filter.mp ho).1))).2 d hdo

theorem heldOfArgs_open (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hc : Γ c = some Ec) (hlc : Ec.live = true)
    (htc : Ec.ty ≠ .int) :
    heldOfArgs (setE (cleanC Γ) e (envE c Ec te)) (e :: zs) ⊆ heldOfArgs Γ (c :: zs) ∧
      ∀ d ∈ heldOfArgs (setE (cleanC Γ) e (envE c Ec te)) (e :: zs), d.root ≠ e := by
  have hE : argE (setE (cleanC Γ) e (envE c Ec te)) e = envE c Ec te := by simp [argE, setE]
  have hEc : argE Γ c = Ec := by simp [argE, hc]
  have hzs' : ∀ a ∈ zs, a ≠ e := by
    intro a ha
    obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem ha
    have := hzs k; rwa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk, Option.getD_some] at this
  -- the roots, argument by argument
  have hR : ∀ r ∈ (e :: zs).flatMap (fun a => if (argE (setE (cleanC Γ) e (envE c Ec te)) a).ty = .int then []
      else roots (argE (setE (cleanC Γ) e (envE c Ec te)) a).held),
      r ∈ (c :: zs).flatMap (fun a => if (argE Γ a).ty = .int then [] else roots (argE Γ a).held) ∧ r ≠ e := by
    intro r hr
    simp only [List.flatMap_cons, List.mem_append] at hr
    rcases hr with hr | hr
    · rw [hE] at hr
      split at hr
      · simp at hr
      · have hr' : r ∈ roots Ec.held := by simpa [envE] using hr
        refine ⟨by simp only [List.flatMap_cons, List.mem_append, hEc, htc, ↓reduceIte]; exact Or.inl hr', ?_⟩
        intro hre
        obtain ⟨Er, hEr, _⟩ := hw c Ec hc hlc (Or.inl htc) r (held_vdeps hr')
        rw [hre, he] at hEr; cases hEr
    · obtain ⟨a, ha, hra⟩ := List.mem_flatMap.mp hr
      rw [argE_open (hzs' a ha), clean_ty] at hra
      split at hra
      · simp at hra
      · rename_i hnt
        refine ⟨List.mem_append_right _ (List.mem_flatMap.mpr ⟨a, ha, by
          simp only [hnt, ↓reduceIte]; exact List.map_subset _ (clean_held_sub _) hra⟩), ?_⟩
        intro hre
        obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hra
        exact argE_noE hw hrl hni he a d (by unfold Entry.vdeps; exact List.mem_append_right _ hd) (hdr.trans hre)
  unfold heldOfArgs
  refine ⟨fun d hd => ?_, fun d hd => ?_⟩
  · rw [RSetup.mem_allKinds_iff] at hd ⊢; exact (hR _ hd).1
  · rw [RSetup.mem_allKinds_iff] at hd; exact (hR _ hd).2

theorem deps_open (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hc : Γ c = some Ec) (hlc : Ec.live = true)
    (htc : Ec.ty ≠ .int) {L L' : List (Nat × Kind)} (hL : L ⊆ L') :
    reroot e ((envE c Ec te).path ++ (envE c Ec te).held)
        (L.flatMap (argDeps (setE (cleanC Γ) e (envE c Ec te)) (e :: zs)) ++
          heldOfArgs (setE (cleanC Γ) e (envE c Ec te)) (e :: zs)) ⊆
      (L'.flatMap (argDeps Γ (c :: zs)) ++ heldOfArgs Γ (c :: zs)) ++ allKinds (recvRoots c Ec) := by
  intro d hd
  rcases mem_reroot hd with ⟨hd, hne⟩ | ⟨k, d', _, hd', rfl⟩
  · refine List.mem_append_left _ ?_
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨jk, hjk, hdj⟩ := List.mem_flatMap.mp hd
      by_cases hj : jk.1 = 0
      · exact absurd (argDeps_zero hj d hdj) hne
      · exact List.mem_append_left _ (List.mem_flatMap.mpr ⟨jk, hL hjk,
          (argDeps_open hw hrl hni he hzs hj).1 hdj⟩)
    · exact List.mem_append_right _ ((heldOfArgs_open hw hrl hni he hzs hc hlc htc).1 hd)
  · refine List.mem_append_right _ (RSetup.mem_allKinds_iff.mpr ?_)
    simp only [envE, List.mem_append] at hd'
    show d'.root ∈ recvRoots c Ec
    unfold recvRoots
    rcases hd' with (hd' | hd') | hd'
    · exact List.mem_append_left _ (List.mem_map_of_mem (f := Dep.root) hd')
    · exact List.mem_append_right _ (List.mem_map_of_mem (f := Dep.root) hd')
    · exact List.mem_append_right _ (List.mem_map_of_mem (f := Dep.root) hd')

/-- Rerooting an `ownHeld` stays inside the `ownHeld` of a bound for it. -/
theorem reroot_ownHeld {p : Var} {D : List Dep} {o : Bool} {t : Ty} {L X R : List Dep}
    (h : reroot p D L ⊆ X ++ R) :
    reroot p D (ownHeld o t L) ⊆ ownHeld o t (ownHeld o t X ++ R) := by
  unfold ownHeld
  split
  · simp [reroot]
  · simpa using h

/-- A call result, rerooted, is not fixed. -/
theorem rerootE_callRes_not_fixed {p : Var} {D : List Dep} (Γ' : Ctx) (fn' : Fn) (args' : List Var) :
    ¬ (rerootE p D (callRes Γ' fn' args')).fixed := by
  simp only [Entry.fixed_def, rerootE, callRes]
  rintro (h | ⟨b, h, _⟩)
  · exact resMode_ne' fn' h
  · exact resMode_inout fn' b h

/-- The opened call's result, once the environment is dropped, says no less
    than the call through the package's. -/
theorem res_open {fn sig : Fn} (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hc : Γ c = some Ec) (hlc : Ec.live = true)
    (htc : Ec.ty ≠ .int) (hty : fn.resTy = sig.resTy) (hown : fn.resOwn = sig.resOwn)
    (hl : fn.lends ⊆ sig.lends) (hr : fn.rholds ⊆ sig.rholds) :
    EntryWeaker (rerootE e ((envE c Ec te).path ++ (envE c Ec te).held)
        (callRes (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs)))
      (recvRes c Ec (callRes Γ sig (c :: zs))) := by
  refine RSetup.EntryWeaker.mk' (by simp [recvRes, rerootE, callRes, hty, hown, resMode])
    (by simp [recvRes, rerootE, callRes, resMode, hown]) (rerootE_callRes_not_fixed _ _ _)
    (by simp [recvRes, rerootE, callRes]) (fun _ => ?_) ?_
  · show reroot e _ (callRes (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs)).path ⊆ _
    exact deps_open hw hrl hni he hzs hc hlc htc hl
  · show reroot e _ (ownHeld fn.resOwn fn.resTy _) ⊆
        ownHeld (resMode (callRes Γ sig (c :: zs)).mode).ownSlot _ _
    rw [show (resMode (callRes Γ sig (c :: zs)).mode).ownSlot = fn.resOwn by
          simp only [callRes]; rw [resMode]; cases fn.resOwn <;> rfl,
      show (callRes Γ sig (c :: zs)).ty = fn.resTy by simp [callRes, hty]]
    refine reroot_ownHeld ?_
    refine (deps_open hw hrl hni he hzs hc hlc htc hr).trans ?_
    intro d hd
    simp only [callRes, List.append_assoc] at hd ⊢
    rcases List.mem_append.mp hd with h1 | h1
    · exact List.mem_append_left _ h1
    · exact List.mem_append_right _ h1

end opened

/-- A binding on no `p` is untouched by `p`'s rerooting, but for an owner's
    `path`, which says nothing. -/
theorem rerootE_noE {p : Var} {D : List Dep} {E E' : Entry} (hw : EntryWeaker E E')
    (hne : ∀ d ∈ E.vdeps, d.root ≠ p) : EntryWeaker (rerootE p D E) E' := by
  have hh : reroot p D E.held = E.held :=
    reroot_id fun d hd => hne d (by unfold Entry.vdeps; exact List.mem_append_right _ hd)
  have hp : E.mode.ownSlot = false → reroot p D E.path = E.path := fun ho =>
    reroot_id fun d hd => hne d (by unfold Entry.vdeps; rw [ho]; exact List.mem_append_left _ hd)
  obtain ⟨ht, hm, hrb, hl⟩ := hw
  refine ⟨ht, hm, fun h => ?_, fun h' => ?_⟩
  · have hf : E.fixed := by simp only [Entry.fixed_def] at h ⊢; rw [rerootE] at h; exact h
    have := hrb hf
    rw [this]; unfold rerootE
    rcases hf with h' | ⟨b, h', _⟩
    · rw [hh, hp (by rw [h']; rfl)]
    · rw [hh]
      have ho : E.mode.ownSlot = true := by rw [h']; rfl
      congr 1; apply reroot_id
      intro d hd; exact hne d (by unfold Entry.vdeps; rw [ho]; exact List.mem_append_left _ hd)
  · obtain ⟨hl1, hp1, hh1⟩ := hl h'
    refine ⟨hl1, fun ho => ?_, ?_⟩
    · show reroot p D E.path ⊆ E'.path
      rw [hp ho]; exact hp1 ho
    · show reroot p D E.held ⊆ E'.held
      rw [hh]; exact hh1

/-- Once the environment is dropped, the context after the opened call says
    no less than the one after the call through the package. -/
theorem weaker_open {Γ : Ctx} {e c x : Var} {Ec : Entry} {te t0 : Ty} {zs : List Var} {fn sig : Fn}
    {rest : List (PMode × Ty)} (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hc : Γ c = some Ec) (hlc : Ec.live = true)
    (htc : Ec.ty ≠ .int) (hxe : x ≠ e)
    (hps : fn.params = (.inp, te) :: rest) (hsp : sig.params = (.inp, t0) :: rest)
    (hty : fn.resTy = sig.resTy) (hown : fn.resOwn = sig.resOwn)
    (hl : fn.lends ⊆ sig.lends) (hr : fn.rholds ⊆ sig.rholds) (ho : fn.outHolds ⊆ sig.outHolds)
    (hnz : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0)
    (hrb : ∀ p a, (p, a) ∈ rest.zip zs → p.1 ≠ .inp → (argE Γ a).mode ≠ .rootb)
    (hse : callPost Γ sig (c :: zs) e = none)
    (hwf : CtxWF (setE (callPost Γ sig (c :: zs)) x (recvRes c Ec (callRes Γ sig (c :: zs))))) :
    Weaker (exitRoot e ((envE c Ec te).path ++ (envE c Ec te).held)
        (setE (callPost (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs)) x
          (callRes (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs))))
      (setE (callPost Γ sig (c :: zs)) x (recvRes c Ec (callRes Γ sig (c :: zs)))) := by
  have hzs' : ∀ a ∈ zs, a ≠ e := by
    intro a ha
    obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem ha
    have := hzs k; rwa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk, Option.getD_some] at this
  have hd : callPost (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs) =
      callPostAux (setE (cleanC Γ) e (envE c Ec te)) fn (e :: zs) rest zs 1 (setE (cleanC Γ) e (envE c Ec te)) := by
    unfold callPost; rw [hps]; rfl
  have hs : callPost Γ sig (c :: zs) = callPostAux Γ sig (c :: zs) rest zs 1 Γ := by
    unfold callPost; rw [hsp]; rfl
  have h0 : PostRel e (setE (cleanC Γ) e (envE c Ec te)) Γ := by
    intro v hve
    simp only [setE, upd_ne _ _ hve]
    refine ⟨cleanC_none, fun Ed Es hd hs => ?_⟩
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hd
    rw [h0] at hs; cases hs
    exact ⟨clean_weaker _, clean_noE hw hrl hni he h0⟩
  have hR := post_rel (Γe := setE (cleanC Γ) e (envE c Ec te)) (Γ := Γ) (fn := fn) (sig := sig)
    (A := e :: zs) (C := c :: zs) (outHeld_open hw hrl hni he hzs ho hnz · |> fun h _ => h)
    (heldOfArgs_open hw hrl hni he hzs hc hlc htc) rest zs 1 _ _ (Nat.le_refl _)
    (fun a ha => ⟨hzs' a ha, argE_open (hzs' a ha), by rw [argE_open (hzs' a ha)]; exact argE_noE hw hrl hni he a⟩)
    hrb h0
  rw [← hd, ← hs] at hR
  refine ⟨fun v => ?_, hwf⟩
  by_cases hve : v = e
  · subst hve
    have h1 : exitRoot v ((envE c Ec te).path ++ (envE c Ec te).held)
        (setE (callPost (setE (cleanC Γ) v (envE c Ec te)) fn (v :: zs)) x
          (callRes (setE (cleanC Γ) v (envE c Ec te)) fn (v :: zs))) v = none := by simp [exitRoot]
    have h2 : setE (callPost Γ sig (c :: zs)) x (recvRes c Ec (callRes Γ sig (c :: zs))) v = none := by
      simp [setE, upd_ne _ _ (Ne.symm hxe), hse]
    rw [h1, h2]; exact ⟨Iff.rfl, fun _ _ h => by cases h⟩
  · by_cases hvx : v = x
    · subst hvx
      simp only [exitRoot, setE, upd_ne _ _ hve, upd_same, Option.map_some]
      refine ⟨by simp, fun Ed Es h1 h2 => ?_⟩
      cases h1; cases h2
      exact res_open hw hrl hni he hzs hc hlc htc hty hown hl hr
    · simp only [exitRoot, setE, upd_ne _ _ hve, upd_ne _ _ hvx]
      obtain ⟨hn, hwk⟩ := hR v hve
      refine ⟨by rw [Option.map_eq_none_iff]; exact hn, fun Ed Es h1 h2 => ?_⟩
      obtain ⟨Ed0, hd0, rfl⟩ := Option.map_eq_some_iff.mp h1
      obtain ⟨hw', hne⟩ := hwk Ed0 Es hd0 h2
      exact rerootE_noE hw' hne

/-- Opening a package for a call: the environment bound to `e` as a borrowed
    parameter, and the call of the code on it and the arguments, well-typed. -/
theorem open_pkg {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec E : Entry} {ms : List Nat} {σ : Nat} {sig : Fn} {m : Mem}
    (hx : Γ x = none) (hc : Γ c = some Ec) (htc : Ec.ty = .fn ms)
    (hσ : P[σ]? = some sig) (hhd : sig.params.head? = some (.inp, .fn ms))
    (hcT : CallT P Γ F σ (c :: zs) E Γ1) (hi : Inv m Γ F (.callc x c j zs k))
    {o : Bool} {fs : List Nat} {te : Ty} {env : Val} (hslot : m.st c = some ⟨o, some (.pkg fs te ms env)⟩)
    {f : Nat} {fn : Fn} (hf : P[f]? = some fn) (hps : fn.params = (.inp, te) :: sig.params.tail) :
    MInv (envMem m env) (setE Γ m.nv (envE c Ec te)) ∧
    (∀ r ∈ roots (envE c Ec te).vdeps, r ∈ heldFor fn.params (m.nv :: zs) m.nv x) ∧
    CallT P (setE Γ m.nv (envE c Ec te)) (F ++ heldFor fn.params (m.nv :: zs) m.nv x) f (m.nv :: zs)
      (callRes (setE Γ m.nv (envE c Ec te)) fn (m.nv :: zs))
      (callPost (setE Γ m.nv (envE c Ec te)) fn (m.nv :: zs)) := by
  obtain ⟨sig', hσ', hlen, hargs, _, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨p0, rest, hsp⟩ : ∃ p0 rest, sig.params = p0 :: rest := by
    cases h : sig.params with
    | nil => rw [h] at hhd; cases hhd
    | cons p0 rest => exact ⟨p0, rest, rfl⟩
  rw [hsp] at hps
  have hslen : sig.params.length = fn.params.length := by rw [hsp, hps]; rfl
  -- the receiver's argument
  obtain ⟨Ea0, hEa0, hlc, _, hmv0⟩ := hargs 0 (by rw [hsp]; simp)
  simp only [List.getD_cons_zero] at hEa0
  rw [hc] at hEa0; cases hEa0
  have hteok : te.ok = true := by
    obtain ⟨_, _, _, _, _, hpar, _⟩ := hP fn (List.mem_of_getElem? hf)
    exact (hpar (.inp, te) (by rw [hps]; simp)).1
  have hlt : ∀ v E, Γ v = some E → v < m.nv := fun v E h => hi.nvSt v (by rw [← hi.dom, h]; rfl)
  have hΓe0 : Γ m.nv = none := by
    cases h : Γ m.nv with
    | none => rfl
    | some E0 => exact absurd (hlt _ _ h) (Nat.lt_irrefl _)
  have hxlt : x < m.nv := hi.nvS x (by simp [Stmt.vars])
  have hxe : x ≠ m.nv := fun e => by have := vlt hxlt; have := veq e; omega
  have hnint : Ec.ty ≠ .int := by rw [htc]; simp
  -- the environment, valid through what the package depends on
  have hEw : ∀ r ∈ roots (envE c Ec te).vdeps, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro r hr
    simp only [envE, Entry.vdeps, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, roots, List.map_append,
      List.mem_append] at hr
    rcases hr with (hr | hr) | hr
    · exact derive_roots hi.wf hc hlc (Or.inl hnint) .self r hr
    · exact hi.wf c Ec hc hlc (Or.inl hnint) r (held_vdeps hr)
    · exact hi.wf c Ec hc hlc (Or.inl hnint) r (held_vdeps hr)
  have hval0 : ValOK m te (lendOf env) (derive c Ec .self ++ Ec.held) Ec.held := by
    rcases hi.mode_cases hc with hm | hm | hm
    · obtain ⟨T, hT, hw, hvs⟩ := hi.own_val hc hlc (by rw [hm]; rfl)
      rw [hslot] at hT; cases hT
      rw [htc] at hw hvs
      cases hw with
      | pkg hwe =>
        have hd : derive c Ec .self = [⟨c, .view⟩] := by simp [derive, hm, Mode.isRoot, htc, rootKind]
        rw [hd]
        refine lend_valOK' hwe (fun t c' d es ht => ⟨⟨c, .view⟩, by simp, _,
          Or.inl ⟨_, hslot, Top.pkg ht⟩, Or.inr (Or.inl ⟨rfl, rfl⟩)⟩)
          (fun s v hin => hvs s v (ViewIn.pkg hin)) (fun s _ => ?_)
        exact ViewsOK.mono (List.subset_append_right _ _) (fun s v hin => hvs s v (ViewIn.pkg hin))
    · obtain ⟨v, hv, hok⟩ := hi.bor_val hc hlc (by rw [hm]; rfl)
      rw [hslot] at hv; cases hv
      rw [htc] at hok
      cases hok with
      | pkg hokE =>
        have hd : derive c Ec .self = [⟨c, .view⟩] := by simp [derive, hm, Mode.isRoot, htc, rootKind]
        rw [hd, hokE.lend]
        exact valOK_via hslot hokE (Top.pkg (Top.refl _)) (by simp)
    · obtain ⟨v, hv, hok⟩ := hi.bor_val hc hlc (by rw [hm]; rfl)
      rw [hslot] at hv; cases hv
      rw [htc] at hok
      cases hok with
      | pkg hokE =>
        rw [derive_bor_self (by rw [hm]; rfl), hokE.lend]; exact hokE
  let mn : Mem := { m with nv := m.nv + 1 }
  have hin : MInv mn Γ :=
    hi.toMInv.of_st rfl ⟨hi.heap.nodup, hi.heap.disj, hi.heap.alloc, hi.heap.self⟩ (Nat.le_succ _)
  have hval : ValOK mn te (lendOf env) (derive c Ec .self ++ Ec.held) Ec.held := by
    have hk : ∀ dep : Dep, VKeep m mn dep ∧ HKeep m mn dep := fun dep => by
      have hr : RootKeep m mn dep.root := fun n hn => rootNode_st rfl hn
      exact ⟨hr.vkeep, hr.hkeep⟩
    exact hval0.keep (fun d _ => hk d) (fun d _ => hk d)
  have hie : MInv (envMem m env) (setE Γ m.nv (envE c Ec te)) :=
    hin.addRootb hΓe0 (Nat.lt_succ_self _) rfl rfl hteok hval hEw
      (fun r hr => by obtain ⟨Er, hEr, _⟩ := hEw r hr; exact hlt r Er hEr)
  -- the roots the environment depends on are held still for the call
  have hZ : ∀ r ∈ roots (envE c Ec te).vdeps, r ∈ heldFor fn.params (m.nv :: zs) m.nv x := by
    intro r hr
    obtain ⟨Er, hEr, _⟩ := hEw r hr
    simp only [heldFor, List.mem_filter, List.mem_range, Bool.and_eq_true, bne_iff_ne, ne_eq,
      Bool.not_eq_eq_eq_not, Bool.not_true, List.contains_eq_mem, decide_eq_false_iff_not]
    refine ⟨hlt r Er hEr, ⟨(fun e => by rw [e, hx] at hEr; cases hEr), fun hm => ?_⟩⟩
    obtain ⟨i, p, hp, hpm, ha⟩ := mem_movedArgs hm
    cases i with
    | zero => rw [hps] at hp; simp at hp; subst hp; exact hpm rfl
    | succ i =>
      have hp' : sig.params[i + 1]? = some p := by rw [hsp]; rw [hps] at hp; simpa using hp
      have hil := (List.getElem?_eq_some_iff.mp hp').1
      obtain ⟨_, _, _, _, hmv⟩ := hargs (i + 1) hil
      have hget : sig.params[i + 1] = p := (List.getElem?_eq_some_iff.mp hp').2
      have hmoves : sig.params[i + 1].1.moves = true := by
        rw [hget]; obtain ⟨pm, t⟩ := p; cases pm <;> simp_all [PMode.moves]
      obtain ⟨_, _, hdist⟩ := hmv hmoves
      obtain ⟨hne, hnr⟩ := hdist 0 (by rw [hsp]; simp) (by omega)
      have ha' : r = (c :: zs).getD (i + 1) 0 := ha
      simp only [List.getD_cons_zero] at hne hnr
      rcases envE_roots hr with h | h
      · exact hne (h ▸ ha')
      · exact hnr (by rw [← ha']; unfold argE; rw [hc]; exact h)
  refine ⟨hie, hZ, fn, hf, ?_, fun i hil => ?_, rfl, rfl⟩
  · have : (c :: zs).length = fn.params.length := by rw [hlen, hslen]
    simpa using this
  -- the arguments past the receiver are the call's own
  have hzlt : ∀ a ∈ zs, a < m.nv := fun a ha => hi.nvS a (by simp [Stmt.vars, ha])
  have hΓe : ∀ a ∈ zs, setE Γ m.nv (envE c Ec te) a = Γ a := by
    intro a ha
    have : a ≠ m.nv := fun e => by have := vlt (hzlt a ha); have := veq e; omega
    simp [setE, upd_ne _ _ this]
  have hcne : c ≠ m.nv := fun e => by rw [e, hΓe0] at hc; cases hc
  have hzs : ∀ i, i < zs.length → zs.getD i 0 ∈ zs := fun i h => by
    simp [List.getD, List.getElem?_eq_getElem h]
  have hargE : ∀ i, i < zs.length → argE (setE Γ m.nv (envE c Ec te)) (zs.getD i 0) =
      argE Γ (zs.getD i 0) := by
    intro i hz; unfold argE; rw [hΓe _ (hzs i hz)]
  have hzlen : zs.length + 1 = fn.params.length := by
    have : (c :: zs).length = fn.params.length := by rw [hlen, hslen]
    simpa using this
  have hil' : i < sig.params.length := by rw [hslen]; exact hil
  cases i with
  | zero =>
    have hp0 : fn.params[0] = (.inp, te) := by simp [hps]
    refine ⟨envE c Ec te, by simp [setE], rfl, ?_, fun hmv => ?_⟩
    · rw [hp0]; rfl
    · rw [hp0] at hmv; cases hmv
  | succ i =>
    have hiz : i < zs.length := by omega
    obtain ⟨Ea, hEa, hla, hpa, hmva⟩ := hargs (i + 1) hil'
    have hpe : fn.params[i + 1] = sig.params[i + 1] := by simp [hps, hsp]
    simp only [List.getD_cons_succ] at hEa hmva ⊢
    refine ⟨Ea, by rw [hΓe _ (hzs i hiz)]; exact hEa, hla, by rw [hpe]; exact hpa, fun hmv => ?_⟩
    rw [hpe] at hmv
    obtain ⟨hnF, hnr, hdist⟩ := hmva hmv
    have hnm : (sig.params[i + 1]).1 ≠ .inp := fun h => by rw [h] at hmv; cases hmv
    have hmoved : zs.getD i 0 ∈ movedArgs fn.params (m.nv :: zs) := by
      have := mem_movedArgs_of (args := m.nv :: zs) (i := i + 1)
        (by rw [List.getElem?_eq_getElem hil, hpe]) hnm
      simpa using this
    refine ⟨fun h => ?_, hnr, fun j hj hji => ?_⟩
    · rcases List.mem_append.mp h with h | h
      · exact hnF h
      · simp only [heldFor, List.mem_filter, List.contains_eq_mem, hmoved, decide_true,
          Bool.not_true, Bool.and_false, Bool.false_eq_true, and_false] at h
    · have hj' : j < sig.params.length := by rw [hslen]; exact hj
      cases j with
      | zero =>
        obtain ⟨hne, hnr0⟩ := hdist 0 hj' hji
        simp only [List.getD_cons_zero] at hne hnr0 ⊢
        refine ⟨fun e => by have := vlt (hzlt _ (hzs i hiz)); have := veq e; omega, fun hr => ?_⟩
        unfold argE at hr; simp only [setE, upd_same, Option.getD_some] at hr
        rcases envE_roots hr with h | h
        · exact hne h.symm
        · exact hnr0 (by unfold argE; rw [hc]; exact h)
      | succ j =>
        obtain ⟨hne, hnr0⟩ := hdist (j + 1) hj' hji
        simp only [List.getD_cons_succ] at hne hnr0 ⊢
        exact ⟨hne, by rw [hargE j (by omega)]; exact hnr0⟩

theorem cloProgress {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec E : Entry} {ms : List Nat} {σ : Nat} {sig : Fn} {m : Mem}
    (hx : Γ x = none) (hc : Γ c = some Ec) (htc : Ec.ty = .fn ms) (hj : ms[j]? = some σ)
    (hσ : P[σ]? = some sig) (hhd : sig.params.head? = some (.inp, .fn ms))
    (hcT : CallT P Γ F σ (c :: zs) E Γ1) (hcd : MemCodes P m) (hi : Inv m Γ F (.callc x c j zs k)) :
    ∃ s, Step P m (.callc x c j zs k) s := by
  obtain ⟨o, fs, te, env, hslot⟩ := pkg_slot hi.toMInv hc (callT_recv_live hcT hc) htc
  obtain ⟨f, fn, hfs, hf, hps, _⟩ := pkg_code hcd hslot hj hσ
  obtain ⟨hie, _, hcT'⟩ := open_pkg hP hx hc htc hσ hhd hcT hi hslot hf hps
  have hxlt : x < m.nv := hi.nvS x (by simp [Stmt.vars])
  have hxe : x ≠ m.nv := fun e => by have := vlt hxlt; have := veq e; omega
  have hx' : setE Γ m.nv (envE c Ec te) x = none := by simp [setE, upd_ne _ _ hxe, hx]
  obtain ⟨r, hs⟩ := callProgress (k := k) hx' hcT' hie
  cases hs with
  | letcall hf' hmx hb =>
    rw [hf] at hf'; cases hf'
    exact ⟨_, Step.callc hslot hfs hf (by simpa [envMem, Mem.set, upd_ne _ _ hxe] using hmx) hb⟩

theorem cloCase {P : Prog} (hP : ProgOK P) : CloCase P := by
  intro Γ Γ1 F x c j zs k Ec E ms σ sig Δ m m' s' hk hx hxF hc htc hj hσ hhd hnz hcT hkT hcd hi hst
  cases hst with
  | callc hslot hfs hf hmx hb =>
    rename_i m1 o fs te ms' env f fn
    obtain ⟨_, _, _, _, hslot'⟩ := pkg_slot hi.toMInv hc (callT_recv_live hcT hc) htc
    rw [hslot] at hslot'; cases hslot'
    -- the code, implementing the method's interface
    obtain ⟨f', fn', hfs', hf', hps, hty, hown, hl, hr, ho⟩ := pkg_code hcd hslot hj hσ
    rw [hfs] at hfs'; cases hfs'; rw [hf] at hf'; cases hf'
    obtain ⟨rest, hsp⟩ : ∃ rest, sig.params = (.inp, .fn ms) :: rest := by
      cases h : sig.params with
      | nil => rw [h] at hhd; cases hhd
      | cons p0 rest => rw [h] at hhd; simp at hhd; exact ⟨rest, by rw [hhd]⟩
    rw [hsp] at hps; simp only [List.tail_cons] at hps
    have hlc := callT_recv_live hcT hc
    have hnint : Ec.ty ≠ .int := by rw [htc]; simp
    -- where things are
    have hlt : ∀ v E, Γ v = some E → v < m.nv := fun v E h => hi.nvSt v (by rw [← hi.dom, h]; rfl)
    have hΓe0 : Γ m.nv = none := by
      cases h : Γ m.nv with
      | none => rfl
      | some E0 => exact absurd (hlt _ _ h) (Nat.lt_irrefl _)
    have hxlt : x < m.nv := hi.nvS x (by simp [Stmt.vars])
    have hxe : x ≠ m.nv := fun e => by have := vlt hxlt; have := veq e; omega
    have hclt : c < m.nv := hlt c Ec hc
    have hzlt : ∀ a ∈ zs, a < m.nv := fun a ha => hi.nvS a (by simp [Stmt.vars, ha])
    have hzs : ∀ k, zs.getD k 0 ≠ m.nv := by
      intro k' he
      by_cases hk' : k' < zs.length
      · have hm : zs.getD k' 0 ∈ zs := by
          rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk', Option.getD_some]
          exact List.getElem_mem hk'
        have := hzlt _ hm
        rw [he] at this; exact Nat.lt_irrefl _ this
      · rw [List.getD_eq_getElem?_getD, List.getElem?_eq_none (by omega)] at he
        simp at he; rw [← he] at hclt; exact Nat.not_lt_zero _ hclt
    have hFe : m.nv ∉ F := fun h => by have := vlt (hi.nvF _ h); omega
    let H := heldFor fn.params (m.nv :: zs) m.nv x
    have hHlt : ∀ v ∈ H, v < m.nv := fun v hv => List.mem_range.mp (List.mem_filter.mp hv).1
    have hHe : m.nv ∉ H := fun h => Nat.lt_irrefl _ (hHlt _ h)
    have hxH : x ∉ H := fun h => by simp [H, heldFor] at h
    have hxF' : x ∉ F ++ H := fun h => (List.mem_append.mp h).elim hxF hxH
    have hFe' : m.nv ∉ F ++ H := fun h => (List.mem_append.mp h).elim hFe hHe
    -- the package opened, in the cleaned context
    have hic := hi.clean
    have hcc : cleanC Γ c = some Ec := by rw [cleanC_of hc, clean_id (Or.inl hnint) hlc]
    have hxc : cleanC Γ x = none := cleanC_none.mpr hx
    have hps' : fn.params = (.inp, te) :: sig.params.tail := by rw [hsp, hps]; rfl
    obtain ⟨hie, hZ, hcT'⟩ := open_pkg hP hxc hcc htc hσ hhd (hcT.clean hσ) hic hslot hf hps'
    let Ee := envE c Ec te
    let Γe := setE (cleanC Γ) m.nv Ee
    have hEe : Γe m.nv = some Ee := by simp [Γe, setE]
    have hxe' : Γe x = none := by simp [Γe, setE, upd_ne _ _ hxe, hxc]
    have hIe : Inv (envMem m env) Γe (F ++ H) (.letcall x f (m.nv :: zs) k) :=
      { toMInv := hie
        nvS := by
          intro v hv
          show v < m.nv + 1
          simp only [Stmt.vars, List.cons_append, List.mem_cons, List.mem_append] at hv
          rcases hv with rfl | rfl | hv | hv
          · exact Nat.lt_succ_of_lt hxlt
          · exact Nat.lt_succ_self _
          · exact Nat.lt_succ_of_lt (hzlt v hv)
          · exact Nat.lt_succ_of_lt (hi.nvS v (by simp [Stmt.vars, hv]))
        nvF := fun v hv => by
          show v < m.nv + 1
          rcases List.mem_append.mp hv with hv | hv
          · exact Nat.lt_succ_of_lt (hi.nvF v hv)
          · exact Nat.lt_succ_of_lt (hHlt v hv)
        anch := fun p E hp hm _ => by
          by_cases hpe : p = m.nv
          · subst hpe; simp only [Γe, setE, upd_same, Option.some.injEq] at hp; subst hp
            exact fun r hr => List.mem_append_right _ (hZ r hr)
          · simp only [Γe, setE, upd_ne _ _ hpe] at hp
            exact fun r hr => List.mem_append_left _ (hic.anch p E hp hm (by simp [Stmt.spine]) r hr)
        spineNd := by simp [Stmt.spine]
        spineDom := by simp [Stmt.spine]
        catchOK := catchOK_src (by simp [Stmt.src, hk])
        cover := fun i hia => by
          obtain ⟨o', T, hT, hiT⟩ := hi.cover i hia
          have ho : o' ≠ m.nv := fun e => by
            subst e; unfold OwnedAt at hT
            have := hi.dom m.nv; rw [hΓe0, hT] at this; cases this
          exact ⟨o', T, by unfold OwnedAt at hT ⊢; simp [envMem, Mem.set, upd_ne _ _ ho, hT], hiT⟩ }
    have h := callH_of hP hf hxe' hxF' hcT' hIe
    have hI := h.inv hIe hb
    -- the environment's binding, where the call leaves it
    have hρ : ∀ v, callRen fn.params (m.nv :: zs) (envMem m env).nv v ≠ m.nv := by
      intro v hv
      obtain ⟨b, t, hvp, hva⟩ := h.ren_dom hv (by show m.nv < m.nv + 1; omega)
      cases v with
      | zero => rw [hps] at hvp; cases hvp
      | succ v => simp only [List.getD_cons_succ] at hva; exact hzs v hva
    have hΓ'e : (callS Γe (F ++ H) fn (m.nv :: zs) (envMem m env).nv x).canon (sigCtx fn) m.nv = some Ee := by
      rw [RSetup.canon_frame _ hρ, h.frame_of hρ hxe.symm, h.post_rootb hEe rfl]
      simp [Ee, envE, Entry.clean]
    -- the static context after the call
    obtain ⟨sig', hσ', hlen, hargs, rfl, rfl⟩ := hcT
    rw [hσ] at hσ'; cases hσ'
    have hcT0 : CallT P Γ F σ (c :: zs) (callRes Γ sig (c :: zs)) (callPost Γ sig (c :: zs)) :=
      ⟨sig, hσ, hlen, hargs, rfl, rfl⟩
    obtain ⟨hw1, hdm, hE⟩ := hcT0.wf hP hi.wf
    have hx1 : callPost Γ sig (c :: zs) x = none := by
      have := hdm.1 x; rw [hx] at this; cases h' : callPost Γ sig (c :: zs) x <;> simp_all
    have hse : callPost Γ sig (c :: zs) m.nv = none := by
      have := hdm.1 m.nv; rw [hΓe0] at this; cases h' : callPost Γ sig (c :: zs) m.nv <;> simp_all
    have hrb : ∀ p a, (p, a) ∈ rest.zip zs → p.1 ≠ .inp → (argE Γ a).mode ≠ .rootb := by
      intro p a hpa hpm
      obtain ⟨i, hi1, hi2, he⟩ := RSetup.mem_zip_getD hpa
      simp only [Prod.mk.injEq] at he; obtain ⟨rfl, rfl⟩ := he
      have hil : i + 1 < sig.params.length := by rw [hsp]; simp; omega
      obtain ⟨Ea, hEa, _, hok, _⟩ := hargs (i + 1) hil
      simp only [List.getD_cons_succ] at hEa
      have hp : sig.params[i + 1]'hil = rest[i]'hi1 := by simp [hsp]
      rw [hp] at hok
      unfold argE; rw [hEa]; simp only [Option.getD_some]
      generalize rest[i]'hi1 = q at hok hpm
      obtain ⟨pm, t⟩ := q
      cases pm with
      | inp => exact absurd rfl hpm
      | sink => obtain ⟨_, hm, _⟩ := hok; rw [hm]; simp
      | inout b =>
        obtain ⟨_, hcan, _⟩ := hok
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
    have hW := weaker_open (x := x) (te := te) hi.wf hi.rootbLive hΓe0 hzs hc hlc hnint hxe hps hsp hty hown hl hr ho hnz
      hrb hse (hw1.add hx1 (fun _ _ => recvRes_roots hi.wf hdm hc hlc hnint hE))
    -- the residual, typed
    have hIn := h.typedIn
    have hrbT := StmtT.rbind (P := P) hΓ'e rfl rfl (fun r hr => List.mem_append_right _ (hZ r hr)) hFe' hIn
    have hT := StmtT.scope (P := P) ⟨callX fn, h.canon_x _, by simp [callX, resMode_ne' fn]⟩ hxF
      (StmtT.seq hk (StmtT.frozen hrbT) (hkT.weakenIn hW))
    -- where the call's scopes are
    have hbs := h.body_spine (m := envMem m env)
    have hcin : ∀ v ∈ (callIn fn (m.nv :: zs) (m.nv + 1) x).spine, m.nv < v := by
      intro v hv
      rw [callIn_spine] at hv
      simp only [envMem] at hbs
      rw [hbs, List.append_nil] at hv
      rcases List.mem_cons.mp hv with rfl | hv
      · omega
      · obtain ⟨k', _, _, _, rfl⟩ := mem_wrapSpine hv; omega
    have hcsp : (callStmt fn (m.nv :: zs) (m.nv + 1) x k).spine =
        x :: (callIn fn (m.nv :: zs) (m.nv + 1) x).spine := by
      rw [callStmt_spine, callIn_spine]
    have hssp : ∀ v, v ∈ (Stmt.scope x (.seq (.frozen H (.rbind m.nv (callIn fn (m.nv :: zs) (m.nv + 1) x))) k)).spine ↔
        v = m.nv ∨ v ∈ (callStmt fn (m.nv :: zs) (m.nv + 1) x k).spine := by
      intro v
      rw [hcsp]; simp only [Stmt.spine, List.mem_cons]
      constructor
      · rintro (h | h | h)
        · exact Or.inr (Or.inl h)
        · exact Or.inl h
        · exact Or.inr (Or.inr h)
      · rintro (h | h | h)
        · exact Or.inr (Or.inl h)
        · exact Or.inl h
        · exact Or.inr (Or.inr h)
    have hkeep := h.keep (f := f) (k := k)
    refine ⟨_, hT, ?_, by show m.nv ≤ m.nv + 1 + fn.nvars; omega, ⟨fun v E hv _ => ?_, fun v E' hv hvs => ?_⟩,
      fun v hv => ?_⟩
    · have hnd : (callStmt fn (m.nv :: zs) (m.nv + 1) x k).spine.Nodup := hI.spineNd
      have hdom : ∀ v ∈ (callStmt fn (m.nv :: zs) (m.nv + 1) x k).spine, ∃ E,
          (callS Γe (F ++ H) fn (m.nv :: zs) (envMem m env).nv x).canon (sigCtx fn) v = some E := hI.spineDom
      have hnv : ∀ v ∈ (callStmt fn (m.nv :: zs) (m.nv + 1) x k).vars, v < m.nv + 1 + fn.nvars := hI.nvS
      rw [hcsp] at hnd hdom
      exact { toMInv := hI.toMInv
              nvS := fun v hv => by
                simp only [Stmt.vars, List.mem_cons, List.mem_append] at hv
                rcases hv with rfl | ((hv | rfl | hv) | hv)
                · exact hnv _ (by simp [callStmt, Stmt.vars])
                · exact Nat.lt_of_lt_of_le (hHlt v hv) (Nat.le_trans (Nat.le_succ _) (Nat.le_add_right _ _))
                · show m.nv < m.nv + 1 + fn.nvars; omega
                · exact hnv _ (by simp [callStmt, Stmt.vars, hv])
                · exact hnv _ (by simp [callStmt, Stmt.vars, hv])
              nvF := fun v hv => hI.nvF v (List.mem_append_left _ hv)
              anch := fun p Ep hp hm hs r hr => by
                have hs' : p ≠ m.nv ∧ p ∉ (callStmt fn (m.nv :: zs) (m.nv + 1) x k).spine := by
                  refine ⟨fun e => hs ((hssp p).mpr (Or.inl e)), fun h' => hs ((hssp p).mpr (Or.inr h'))⟩
                rcases h.ctx_cases p with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ |
                    ⟨k', b', t, hk', rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hp <;> (try cases hp)
                · exact absurd hm (resMode_ne' fn)
                · exact absurd hm (resMode_ne' fn)
                · exfalso; apply hs'.2
                  rw [callStmt_spine]
                  exact List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_append_left _
                    (mem_wrapSpine_of hk' (fun b h => by cases h))))
                · cases hm
                · cases hm
                · obtain ⟨E1', h1', rfl⟩ := Option.map_eq_some_iff.mp hp
                  rw [clean_mode] at hm
                  obtain ⟨E0, h0, hm0⟩ := h.postdm.2 p E1' h1'
                  have := h.post_rootb h0 (hm0 ▸ hm)
                  rw [h1'] at this; cases this
                  rw [clean_rootb hm] at hr
                  simp only [Γe, setE, upd_ne _ _ hs'.1] at h0
                  exact hic.anch p E1' h0 hm (by simp [Stmt.spine]) r hr
              spineNd := by
                simp only [Stmt.spine, List.nodup_cons, List.mem_cons, not_or] at hnd ⊢
                exact ⟨⟨hxe, hnd.1⟩, fun h' => Nat.lt_irrefl _ (hcin _ h'), hnd.2⟩
              spineDom := fun v hv => by
                simp only [Stmt.spine, List.mem_cons] at hv
                rcases hv with rfl | rfl | hv
                · exact hdom _ (List.mem_cons_self)
                · exact ⟨_, hΓ'e⟩
                · exact hdom _ (List.mem_cons_of_mem _ hv)
              catchOK := hI.catchOK
              cover := hI.cover }
    · have hve : v ≠ m.nv := fun e => by rw [e, hΓe0] at hv; cases hv
      have hv' : Γe v = some E.clean := by simp only [Γe, setE, upd_ne _ _ hve]; exact cleanC_of hv
      obtain ⟨hns, E', h', hm', ht', hrb'⟩ := hkeep.1 v E.clean hv' (by simp [Stmt.spine])
      refine ⟨fun h'' => (((hssp v).mp h'').elim hve hns), E', h', by rw [hm', clean_mode],
        by rw [ht', clean_ty], fun hr => ?_⟩
      rw [hrb' (by rw [clean_mode]; exact hr), clean_rootb hr]
    · have hve : v ≠ m.nv := fun e => hvs ((hssp v).mpr (Or.inl e))
      have hns : v ∉ (callStmt fn (m.nv :: zs) (m.nv + 1) x k).spine := fun h' => hvs ((hssp v).mpr (Or.inr h'))
      obtain ⟨_, E0, h0⟩ := hkeep.2 v E' hv hns
      simp only [Γe, setE, upd_ne _ _ hve] at h0
      obtain ⟨E1, h1, _⟩ := cleanC_some h0
      exact ⟨by simp [Stmt.spine], E1, h1⟩
    · have hve : v ≠ m.nv := fun e => hFe (e ▸ hv)
      refine Eq.trans (h.frz hIe.toMInv hb v (List.mem_append_left _ hv)) ?_
      simp [envMem, Mem.set, upd_ne _ _ hve]

end A2
