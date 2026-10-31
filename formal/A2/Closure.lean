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
    the caller, valid through what the package depends on and what it holds
    but its changes by name — its by-name captures are handed to the call as
    arguments of their own, and the environment never names them. -/
def envE (c : Var) (Ec : Entry) (te : Ty) (cs : List (Var × PMode × Ty)) : Entry :=
  ⟨te, .rootb, true, envDeps cs (derive c Ec .self ++ Ec.held), envDeps cs Ec.held, false, false⟩

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
    (hvnames : NamesIn v E.held) (hvpkgs : PkgsOK v) (hnameOK : NameOK (setE Γ x E) E)
    (hdt : E.dtor = false := by rfl) :
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
  · exact hi.wf.add hx (fun _ _ r hr => hwf r hr) (fun _ hos => by rw [hm] at hos; cases hos)
      (fun h => by rw [hdt] at h; cases h)
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

theorem memDeps_mono {a b : List Dep} (h : a ⊆ b) : memDeps a ⊆ memDeps b :=
  fun _ hd => List.mem_filter.mpr ⟨h (List.mem_filter.mp hd).1, (List.mem_filter.mp hd).2⟩

theorem roots_subset {a b : List Dep} (h : a ⊆ b) : roots a ⊆ roots b := List.map_subset _ h

/-- What the opened environment depends on is what the package derives or
    holds, and it changes nothing by name. -/
theorem mem_envE_deps {c : Var} {Ec : Entry} {te : Ty} {cs : List (Var × PMode × Ty)} {d : Dep}
    (hd : d ∈ (envE c Ec te cs).path ++ (envE c Ec te cs).held) :
    (d ∈ derive c Ec .self ∨ d ∈ Ec.held) ∧ ownWriter cs d = false := by
  simp only [envE, List.mem_append] at hd
  rcases hd with hd | hd
  · obtain ⟨hd, hb⟩ := mem_envDeps.mp hd
    exact ⟨List.mem_append.mp hd, hb⟩
  · obtain ⟨hd, hb⟩ := mem_envDeps.mp hd
    exact ⟨Or.inr hd, hb⟩

theorem envE_vdeps (c : Var) (Ec : Entry) (te : Ty) (cs : List (Var × PMode × Ty)) :
    (envE c Ec te cs).vdeps = (envE c Ec te cs).path ++ (envE c Ec te cs).held := by
  simp [envE, Entry.vdeps, Mode.ownSlot]

/-- A name the package derives lies in what it depends on. -/
theorem derive_name_vdeps {c : Var} {Ec : Entry} {d : Dep} (hd : d ∈ derive c Ec .self)
    (hn : d.kind.isName = true) : d ∈ Ec.vdeps := by
  by_cases hr : Ec.mode.isRoot
  · unfold derive at hd; rw [ite_eq_left hr] at hd
    simp only [List.mem_singleton] at hd; subst hd
    exact absurd hn (by cases Ec.ty <;> simp [rootKind, Kind.isName])
  · rw [derive_bor_self (by simpa using hr)] at hd
    have hos : Ec.mode.ownSlot = false := by
      cases hm : Ec.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    unfold Entry.vdeps; rw [hos]; exact List.mem_append_left _ hd

/-- What the opened environment holds by name, the package holds by name. -/
theorem envE_names {c : Var} {Ec : Entry} {te : Ty} {cs : List (Var × PMode × Ty)} {d : Dep}
    (hd : d ∈ nameDeps (envE c Ec te cs).vdeps) : d ∈ nameDeps Ec.vdeps := by
  simp only [nameDeps, List.mem_filter] at hd ⊢
  refine ⟨?_, hd.2⟩
  rw [envE_vdeps] at hd
  rcases (mem_envE_deps hd.1).1 with hdd | hh
  · exact derive_name_vdeps hdd hd.2
  · unfold Entry.vdeps; exact List.mem_append_right _ hh

/-- The roots the opened environment depends on: the package, or what it
    depends on. -/
theorem envE_roots {c : Var} {Ec : Entry} {te : Ty} {cs : List (Var × PMode × Ty)} {r : Var}
    (hr : r ∈ roots (envE c Ec te cs).vdeps) :
    r = c ∨ r ∈ roots Ec.vdeps := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  rw [envE_vdeps] at hd
  rcases (mem_envE_deps hd).1 with hd | hd
  · rcases derive_roots_cases (List.mem_map_of_mem (f := Dep.root) hd) with ⟨h, _⟩ | ⟨_, h⟩
    · exact Or.inl h
    · exact Or.inr h
  · exact Or.inr (held_vdeps (List.mem_map_of_mem (f := Dep.root) hd))

/-! ### The cleaned context

The code of a package runs where every dead or integer binding has
forgotten what it depended on, as the frame of an ordinary call does: what
it depended on says nothing, and the environment's binding, fresh, must be
on no dependency when it is dropped. -/

noncomputable def cleanC (Γ : Ctx) : Ctx := fun v => (Γ v).map Entry.clean

theorem clean_path_sub (E : Entry) : E.clean.path ⊆ E.path := by
  unfold Entry.clean; split
  · exact List.nil_subset _
  · exact List.Subset.refl _

theorem clean_held_sub (E : Entry) : E.clean.held ⊆ E.held := by
  intro d hd
  unfold Entry.clean at hd
  split at hd
  · simp only at hd
    split at hd
    · exact (List.mem_filter.mp hd).1
    · cases hd
  · exact hd

theorem clean_vdeps_sub (E : Entry) : E.clean.vdeps ⊆ E.vdeps := fun _ hd => Entry.clean_vdeps_sub hd

/-- A cleaned entry says no less than the entry: it only forgets what a dead
    or integer binding depended on, and keeps what one `letd` made views in
    memory. -/
theorem clean_weaker (E : Entry) : EntryWeaker E.clean E := by
  by_cases hfx : E.fixed
  · rw [clean_fixed hfx]; exact EntryWeaker.refl E
  exact ⟨(clean_ty E).symm, (clean_mode E).symm, fun hf => absurd ((clean_fixed_iff E).mp hf) hfx,
    fun hl => ⟨by rw [clean_live]; exact hl, fun _ => clean_path_sub E, clean_held_sub E⟩,
    fun hd => ⟨by rw [Entry.clean_dtor] at hd; exact hd, clean_held_sub E⟩, (Entry.clean_dbind E).symm,
    fun hd => Or.inl (by rw [Entry.clean_dtor]; exact hd),
    fun hd hos hn d hnm => by
      rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos; rw [clean_ty, clean_mode] at hn
      exact (Entry.clean_vdeps_mem hd hos hn hnm).symm⟩

theorem clean_rootb {E : Entry} (h : E.mode = .rootb) : E.clean = E :=
  clean_fixed (Or.inl h)

/-- A cleaned binding depends on no binding outside the context. -/
theorem clean_noE {Γ : Ctx} (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    {e : Var} (he : Γ e = none) {v : Var} {E : Entry} (hv : Γ v = some E) :
    ∀ d ∈ E.clean.vdeps, d.root ≠ e := by
  intro d hd hde
  unfold Entry.clean at hd; split at hd
  · -- a dead binding `letd` made keeps its views, of bound roots
    simp [Entry.vdeps] at hd
    obtain ⟨⟨hdb, hos, hnt⟩, hdm⟩ := hd
    obtain ⟨Er, hEr, _⟩ := hw.dtor v E hv hdb hos (Or.inl hnt) d
      (by simp only [Entry.vdeps, hos, ↓reduceIte, List.nil_append]; exact (List.mem_filter.mp hdm).1)
      (by simpa using (List.mem_filter.mp hdm).2)
    rw [hde, he] at hEr; cases hEr
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

theorem clean_clean (E : Entry) : E.clean.clean = E.clean := by
  have key : ∀ E : Entry, (¬ E.fixed ∧ (E.ty = .int ∨ E.live = false)) →
      E.clean =
        { E with path := [], held := if E.dbind = true ∧ E.mode.ownSlot = true ∧ E.ty ≠ .int then memDeps E.held else [] } :=
    fun E h => by unfold Entry.clean; rw [if_pos h]
  by_cases h : ¬ E.fixed ∧ (E.ty = .int ∨ E.live = false)
  · have h' : ¬ E.clean.fixed ∧ (E.clean.ty = .int ∨ E.clean.live = false) := by
      rwa [clean_fixed_iff, clean_ty, clean_live]
    rw [key E.clean h', Entry.clean_dbind, clean_mode, clean_ty, key E h]
    by_cases hc : E.dbind = true ∧ E.mode.ownSlot = true ∧ E.ty ≠ .int
    · simp only [if_pos hc, memDeps, List.filter_filter, Bool.and_self]
    · simp only [if_neg hc, memDeps, List.filter_nil]
  · have h1 : E.clean = E := by unfold Entry.clean; rw [ite_eq_right h]
    rw [h1, h1]

theorem cleanC_clean {Γ : Ctx} : ∀ v E, cleanC Γ v = some E → E.clean = E := fun _ _ h => by
  obtain ⟨E0, _, rfl⟩ := cleanC_some h; exact clean_clean E0

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

theorem CtxWF.clean {Γ : Ctx} (hw : CtxWF Γ) : CtxWF (cleanC Γ) where
  live v E hv hl hn r hr := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
    rw [clean_live] at hl; rw [clean_ty, clean_mode] at hn
    have hid : E0.clean = E0 := by
      rcases hn with hn | hn
      · exact clean_id (Or.inl hn) hl
      · exact clean_rootb hn
    rw [hid] at hr
    obtain ⟨Er, hEr, hro⟩ := hw v E0 h0 hl hn r hr
    exact ⟨Er.clean, cleanC_of hEr, by rw [clean_mode]; exact hro⟩
  dtor v E hv hd hos hn d hdd hnm := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
    rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos; rw [clean_ty, clean_mode] at hn
    obtain ⟨Er, hEr, hro⟩ := hw.dtor v E0 h0 hd hos hn d (Entry.clean_vdeps_sub hdd) hnm
    exact ⟨Er.clean, cleanC_of hEr, by rw [clean_mode]; exact hro⟩
  arm v E hv ha := by
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
    rw [Entry.clean_dtor] at ha; rw [Entry.clean_dbind]; exact hw.arm v E0 h0 ha

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
  wf := hi.wf.clean
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
    cover := hi.cover
    pinOut := fun p E hp hm hs => by
      obtain ⟨E0, h0, rfl⟩ := cleanC_some hp
      rw [clean_mode] at hm; rw [clean_rootb hm]; exact hi.pinOut p E0 h0 hm hs
    pinIn := hi.pinIn.of_rootb fun p E hp hm => by
      obtain ⟨E0, h0, rfl⟩ := cleanC_some hp
      rw [clean_mode] at hm; rw [clean_rootb hm]; exact h0
    dtorOut := fun v E hv hd hos hn hvs d hdd hnm => by
      obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
      rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos; rw [clean_ty, clean_mode] at hn
      exact hi.dtorOut v E0 h0 hd hos hn hvs d (Entry.clean_vdeps_sub hdd) hnm
    dtorIn := hi.dtorIn.of_dbind fun v E hv hd hos hn => by
      obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
      rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos; rw [clean_ty, clean_mode] at hn
      exact ⟨E0, h0, hd, hos, hn, fun d hdd _ => Entry.clean_vdeps_sub hdd⟩ }

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
  · rename_i hne; rw [ite_eq_right hne]
    simp only [nameDeps, List.mem_filter] at hda ⊢
    exact ⟨clean_vdeps_sub _ hda.1, hda.2⟩

theorem mutNames_clean (Γ : Ctx) (args : List Var) : mutNames (cleanC Γ) args ⊆ mutNames Γ args := by
  intro d hd
  simp only [mutNames, List.mem_filter] at hd ⊢
  exact ⟨argNames_clean Γ args hd.1, hd.2⟩

/-- Cleaning keeps whether a binding runs a destructor, and forgets
    dependencies only. -/
theorem DtorSafe.clean {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : DtorSafe Γ e hv x) :
    DtorSafe (cleanC Γ) e hv x := by
  intro v E hE hd hos
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hE
  rw [Entry.clean_dtor] at hd; rw [clean_mode] at hos
  have h1 := h v E0 h0 hd hos
  unfold hitsMem at h1 ⊢
  rw [clean_ty, clean_mode]
  simp only [Bool.and_eq_false_iff, List.any_eq_false] at h1 ⊢
  rcases h1 with h1 | h1
  · exact Or.inl h1
  · exact Or.inr fun d hd => h1 d (clean_vdeps_sub _ hd)

theorem CallDtorSafe.clean {Γ : Ctx} {ps : List (PMode × Ty)} {args : List Var}
    (h : CallDtorSafe Γ ps args) : CallDtorSafe (cleanC Γ) ps args :=
  ⟨fun i hi => ⟨fun hs => ((h.1 i hi).1 hs).clean, fun b hb => ((h.1 i hi).2 b hb).clean⟩,
    fun d hd => (h.2.1 d (mutNames_clean Γ args hd)).clean, fun i hi b hb Ea ha => by
      obtain ⟨E0, h0, rfl⟩ := cleanC_some ha
      rw [Entry.clean_dbind]; exact h.2.2 i hi b hb E0 h0⟩

/-- A call checked in a context is checked in its cleaned form. -/
theorem CallT.clean {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) {fn : Fn} (hf : P[f]? = some fn) :
    CallT P (cleanC Γ) F f args (callRes (cleanC Γ) fn args) (callPost (cleanC Γ) fn args) := by
  obtain ⟨fn', hf', hlen, hargs, hnf, hds, _, _⟩ := hc
  rw [hf] at hf'; cases hf'
  refine ⟨fn, hf, hlen, fun i hi => ?_, fun d hd => ?_, hds.clean, rfl, rfl⟩
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
  · obtain ⟨hnF, hnr, hns, hself, hd⟩ := hmv hm
    have hcs : ∀ E : Entry, roots (memDeps E.clean.vdeps) ⊆ roots (memDeps E.vdeps) := fun E =>
      List.map_subset _ (fun d hd => List.mem_filter.mpr
        ⟨clean_vdeps_sub E (List.mem_filter.mp hd).1, (List.mem_filter.mp hd).2⟩)
    refine ⟨hnF, fun h => hnr (hcs Ea h), fun hs h => hns hs (List.map_subset _ (clean_vdeps_sub Ea) h),
      fun b hb d hd' hdr => hself b hb d (clean_vdeps_sub Ea hd') hdr, fun j hj hji => ?_⟩
    obtain ⟨hne, hnr', hns', hnb'⟩ := hd j hj hji
    rw [argE_clean]
    exact ⟨hne, fun h => hnr' (hcs _ h), fun hs h => hns' hs (List.map_subset _ (clean_vdeps_sub _) h),
      fun b hb d hd' hdr => hnb' b hb d (clean_vdeps_sub _ hd') hdr⟩
  · -- NoPin transfers: cleaning keeps borrowed parameters as they are
    intro p E hp hrb d hd hbd
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hp
    rw [clean_mode] at hrb
    rw [clean_rootb hrb] at hd
    exact hpin hs p E0 h0 hrb d hd hbd

/-! ### After the opened call -/

/-- A call leaves no binding `inout` if none was. -/
theorem kill_noInout {Γ : Ctx} (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b) (e : Eff) (hv : Bool)
    (x : Var) : ∀ v E b, A2.kill e hv x Γ v = some E → E.mode ≠ .inout b := by
  intro v E b hv'
  simp only [A2.kill] at hv'
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hv'
  rw [killE_mode]; exact hni v E0 b h0

theorem killNames_noInout {Γ : Ctx} (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b) :
    ∀ ds, ∀ v E b, killNames ds Γ v = some E → E.mode ≠ .inout b
  | [] => hni
  | _ :: ds => kill_noInout (killNames_noInout hni ds) _ _ _

theorem callPostAux_noInout {Γ0 : Ctx} {fn : Fn} {args : List Var}
    (hni0 : ∀ v E b, Γ0 v = some E → E.mode ≠ .inout b) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ v E b, Γ v = some E → E.mode ≠ .inout b) →
      ∀ v E b, callPostAux Γ0 fn args ps as i Γ v = some E → E.mode ≠ .inout b := by
  intro ps
  induction ps with
  | nil => intro as i Γ hni; cases as <;> exact hni
  | cons p ps ih =>
    intro as i Γ hni
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> exact hni
    | cons a as =>
      have hargn : ∀ b, (argE Γ0 a).mode ≠ .inout b := by
        intro b; unfold argE
        cases h : Γ0 a with
        | none => simp [intE]
        | some E0 => simp only [Option.getD_some]; exact hni0 a E0 b h
      cases pm with
      | inp => exact ih as (i + 1) Γ hni
      | sink =>
        refine ih as (i + 1) _ (fun v E b hv => ?_)
        by_cases hva : v = a
        · subst hva; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; exact hargn b
        · simp only [A2.setE, upd_ne _ _ hva] at hv; exact kill_noInout hni _ _ _ v E b hv
      | inout b' =>
        refine ih as (i + 1) _ (fun v E b hv => ?_)
        by_cases hva : v = a
        · subst hva; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv; exact hargn b
        · simp only [A2.setE, upd_ne _ _ hva] at hv; exact kill_noInout hni _ _ _ v E b hv

theorem callPost_noInout {Γ : Ctx} (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (fn : Fn) (args : List Var) : ∀ v E b, callPost Γ fn args v = some E → E.mode ≠ .inout b :=
  fun v E b => killNames_noInout
    (callPostAux_noInout (Γ0 := Γ) (fn := fn) (args := args) hni fn.params args 0 Γ hni) _ v E b

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
      -- (an `inout` argument is no binding `letd` made: `CallDtorSafe`)
      (∀ p a, (p, a) ∈ ps.zip as → ∀ b, p.1 = .inout b → (argE Γ a).dbind = false) →
      PostRel e Γd Γs → PostRel e (callPostAux Γe fn A ps as i Γd) (callPostAux Γ sig C ps as i Γs) := by
  intro ps
  induction ps with
  | nil => intro as i Γd Γs _ _ _ _ h; cases as <;> simpa [callPostAux] using h
  | cons p ps ih =>
    intro as i Γd Γs hi has hrb hio h
    cases as with
    | nil => simpa [callPostAux] using h
    | cons a as =>
      obtain ⟨hae, hcl, hne⟩ := has a (by simp)
      have has' : ∀ a' ∈ as, _ := fun a' ha' => has a' (by simp [ha'])
      have hrb' : ∀ p' a', (p', a') ∈ ps.zip as → p'.1 ≠ .inp → ¬ (argE Γ a').fixed :=
        fun p' a' hm => hrb p' a' (by simp [hm])
      have hio' : ∀ p' a', (p', a') ∈ ps.zip as → ∀ b, p'.1 = .inout b → (argE Γ a').dbind = false :=
        fun p' a' hm => hio p' a' (by simp [hm])
      obtain ⟨pm, t⟩ := p
      have hrba : pm ≠ .inp → ¬ (argE Γ a).fixed := fun hp => hrb (pm, t) a (by simp) hp
      cases pm with
      | inp => exact ih as (i + 1) Γd Γs (by omega) has' hrb' hio' h
      | sink =>
        refine ih as (i + 1) _ _ (by omega) has' hrb' hio' ((h.kill _ _ a).set hae ?_ ?_)
        · rw [hcl]
          exact RSetup.EntryWeaker.mk' (by simp [clean_ty]) (by simp [clean_mode])
            (by rw [fixed_moveOut, clean_fixed_iff]; exact hrba (by simp)) rfl
            (fun _ => clean_path_sub _) (clean_held_sub _)
            (hdh := fun hd hos hn d hnm => (Entry.clean_vdeps_mem (by simpa using hd)
              (by simpa [clean_mode] using hos) (by simpa [clean_ty, clean_mode] using hn) hnm).symm)
        · exact fun d hd => hne d (by simpa [Entry.vdeps] using hd)
      | inout b =>
        have hdba : (argE Γ a).dbind = false := hio (.inout b, t) a (by simp) b rfl
        refine ih as (i + 1) _ _ (by omega) has' hrb' hio' ((h.kill _ _ a).set hae ?_ ?_)
        · rw [hcl]
          refine RSetup.EntryWeaker.mk' (by simp [clean_ty]) (by simp [clean_mode])
            (by rw [fixed_setHeld, clean_fixed_iff]; exact hrba (by simp)) (by simp [clean_live])
            (fun _ => clean_path_sub _) ?_ (hdh := fun hd => absurd hd (by simp [hdba]))
          intro d hd
          by_cases hvv : t.holdsView = true
          · rw [ite_eq_left hvv] at hd ⊢
            simp only [List.mem_append] at hd ⊢
            rcases hd with (hd | hd) | hd
            · exact Or.inl (Or.inl (clean_held_sub _ hd))
            · exact Or.inl (Or.inr ((hout i hi).1 hd))
            · exact Or.inr (hheld.1 hd)
          · rw [ite_eq_right hvv] at hd ⊢
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
variable {Γ : Ctx} {e c : Var} {Ec : Entry} {te : Ty} {zs : List Var} {cs : List (Var × PMode × Ty)}

theorem argE_open {a : Var} (ha : a ≠ e) :
    argE (setE (cleanC Γ) e (envE c Ec te cs)) a = (argE Γ a).clean := by
  unfold argE; rw [show setE (cleanC Γ) e (envE c Ec te cs) a = cleanC Γ a by simp [setE, upd_ne _ _ ha]]
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
    argDeps (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs) jk ⊆ argDeps Γ (c :: zs) jk ∧
      ∀ d ∈ argDeps (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs) jk, d.root ≠ e := by
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
    ∀ d ∈ argDeps (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs) jk, d.root = e := by
  obtain ⟨j, k⟩ := jk
  simp only at hj; subst hj
  have hE : argE (setE (cleanC Γ) e (envE c Ec te cs)) e = envE c Ec te cs := by simp [argE, setE]
  unfold argDeps
  simp only [List.getD_cons_zero, hE]
  split
  · simp
  · simp [derive, envE, Mode.isRoot]

theorem outHeld_open {fn sig : Fn} (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hsub : fn.outHolds ⊆ sig.outHolds)
    (hnz : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0) (i : Nat) :
    outHeld (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs) i ⊆ outHeld Γ sig (c :: zs) i ∧
      ∀ d ∈ outHeld (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs) i, d.root ≠ e := by
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
    heldOfArgs (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs) ⊆ heldOfArgs Γ (c :: zs) ∧
      ∀ d ∈ heldOfArgs (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs), d.root ≠ e := by
  have hE : argE (setE (cleanC Γ) e (envE c Ec te cs)) e = envE c Ec te cs := by simp [argE, setE]
  have hEc : argE Γ c = Ec := by simp [argE, hc]
  have hzs' : ∀ a ∈ zs, a ≠ e := by
    intro a ha
    obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem ha
    have := hzs k; rwa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk, Option.getD_some] at this
  -- the memory roots, argument by argument
  have hR : ∀ r ∈ (e :: zs).flatMap (fun a => if (argE (setE (cleanC Γ) e (envE c Ec te cs)) a).ty = .int then []
      else roots (memDeps (argE (setE (cleanC Γ) e (envE c Ec te cs)) a).held)),
      r ∈ (c :: zs).flatMap (fun a => if (argE Γ a).ty = .int then [] else roots (memDeps (argE Γ a).held)) ∧ r ≠ e := by
    intro r hr
    simp only [List.flatMap_cons, List.mem_append] at hr
    rcases hr with hr | hr
    · rw [hE] at hr
      split at hr
      · simp at hr
      · have hr' : r ∈ roots (memDeps Ec.held) :=
          roots_subset (memDeps_mono (envDeps_sub _ _)) (by simpa [envE] using hr)
        refine ⟨by simp only [List.flatMap_cons, List.mem_append, hEc, htc, ↓reduceIte]; exact Or.inl hr', ?_⟩
        intro hre
        obtain ⟨Er, hEr, _⟩ := hw c Ec hc hlc (Or.inl htc) r (held_vdeps (roots_memDeps hr'))
        rw [hre, he] at hEr; cases hEr
    · obtain ⟨a, ha, hra⟩ := List.mem_flatMap.mp hr
      rw [argE_open (hzs' a ha), clean_ty] at hra
      split at hra
      · simp at hra
      · rename_i hnt
        refine ⟨List.mem_append_right _ (List.mem_flatMap.mpr ⟨a, ha, by
          simp only [hnt, ↓reduceIte]
          exact roots_subset (memDeps_mono (clean_held_sub _)) hra⟩), ?_⟩
        intro hre
        obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hra
        exact argE_noE hw hrl hni he a d
          (by unfold Entry.vdeps; exact List.mem_append_right _ (List.mem_filter.mp hd).1) (hdr.trans hre)
  -- what the arguments hold by name
  have hN : ∀ d ∈ argNames (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs),
      d ∈ argNames Γ (c :: zs) ∧ d.root ≠ e := by
    intro d hd
    simp only [argNames, List.flatMap_cons, List.mem_append] at hd
    rcases hd with hd | hd
    · -- the receiver's by-name holds: the package's captures
      rw [hE] at hd
      split at hd
      · simp at hd
      · have hdh : d ∈ nameDeps Ec.vdeps := envE_names hd
        refine ⟨?_, ?_⟩
        · simp only [argNames, List.flatMap_cons, List.mem_append]
          refine Or.inl ?_
          simp only [hEc, htc, ↓reduceIte]; exact hdh
        · intro hre
          obtain ⟨Er, hEr, _⟩ := hw c Ec hc hlc (Or.inl htc) d.root
            (List.mem_map_of_mem (f := Dep.root) (List.mem_filter.mp hdh).1)
          rw [hre, he] at hEr; cases hEr
    · obtain ⟨a, ha, hda⟩ := List.mem_flatMap.mp hd
      rw [argE_open (hzs' a ha), clean_ty] at hda
      refine ⟨?_, ?_⟩
      · simp only [argNames, List.flatMap_cons, List.mem_append]
        refine Or.inr (List.mem_flatMap.mpr ⟨a, ha, ?_⟩)
        split at hda
        · simp at hda
        · rename_i hnt; rw [ite_eq_right hnt]
          simp only [nameDeps, List.mem_filter] at hda ⊢
          exact ⟨clean_vdeps_sub _ hda.1, hda.2⟩
      · split at hda
        · simp at hda
        · exact argE_noE hw hrl hni he a d (List.mem_filter.mp hda).1
  unfold heldOfArgs
  refine ⟨fun d hd => ?_, fun d hd => ?_⟩
  · rcases List.mem_append.mp hd with hd | hd
    · rw [RSetup.mem_allKinds_iff] at hd
      exact List.mem_append_left _ (RSetup.mem_allKinds_iff.mpr ⟨(hR _ hd.1).1, hd.2⟩)
    · exact List.mem_append_right _ (hN d hd).1
  · rcases List.mem_append.mp hd with hd | hd
    · rw [RSetup.mem_allKinds_iff] at hd; exact (hR _ hd.1).2
    · exact (hN d hd).2

theorem deps_open (hw : CtxWF Γ) (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hc : Γ c = some Ec) (hlc : Ec.live = true)
    (htc : Ec.ty ≠ .int) {L L' : List (Nat × Kind)} (hL : L ⊆ L')
    (hLn : ∀ jk ∈ L, jk.2.isName = false) :
    reroot e ((envE c Ec te cs).path ++ (envE c Ec te cs).held)
        (L.flatMap (argDeps (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs)) ++
          heldOfArgs (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs)) ⊆
      (L'.flatMap (argDeps Γ (c :: zs)) ++ heldOfArgs Γ (c :: zs)) ++ allKinds (recvRoots c Ec) := by
  intro d hd
  rcases mem_reroot hd with ⟨hd, hne⟩ | ⟨k, d', hek, hd', rfl⟩
  · refine List.mem_append_left _ ?_
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨jk, hjk, hdj⟩ := List.mem_flatMap.mp hd
      by_cases hj : jk.1 = 0
      · exact absurd (argDeps_zero hj d hdj) hne
      · exact List.mem_append_left _ (List.mem_flatMap.mpr ⟨jk, hL hjk,
          (argDeps_open hw hrl hni he hzs hj).1 hdj⟩)
    · exact List.mem_append_right _ ((heldOfArgs_open hw hrl hni he hzs hc hlc htc).1 hd)
  · -- the replaced dep had root `e`, so its kind is a memory kind
    have hkn : k.isName = false := by
      rcases List.mem_append.mp hek with hke | hke
      · obtain ⟨jk, hjk, hkj⟩ := List.mem_flatMap.mp hke
        by_cases hj0 : jk.1 = 0
        · unfold argDeps at hkj
          have hE : argE (setE (cleanC Γ) e (envE c Ec te cs)) ((e :: zs).getD jk.1 0) = envE c Ec te cs := by
            rw [hj0]; simp [argE, setE]
          rw [hE] at hkj
          split at hkj
          · simp at hkj
          · unfold derive at hkj
            rw [ite_eq_left (by simp [envE, Mode.isRoot])] at hkj
            simp only [List.mem_singleton, Dep.mk.injEq] at hkj
            rw [hkj.2, rootKind_isName]; exact hLn jk hjk
        · exact absurd rfl ((argDeps_open hw hrl hni he hzs hj0).2 ⟨e, k⟩ hkj)
      · exact absurd ((heldOfArgs_open hw hrl hni he hzs hc hlc htc).2 _ hke) (by simp)
    replace hd' := (mem_envE_deps hd').1
    by_cases hnm : d'.kind.isName = true
    · -- a captured name, reproduced as is: it is `c`'s by-name hold
      have hcomp : comp d'.kind k = d'.kind := by
        obtain ⟨b, t, hk⟩ : ∃ b t, d'.kind = .name b t := by
          cases hdk : d'.kind <;> simp_all [Kind.isName]
        rw [hk]; cases k <;> rfl
      rw [hcomp]
      have hdEc : d' ∈ Ec.vdeps := by
        rcases hd' with hd' | hd'
        · exact derive_name_vdeps hd' hnm
        · exact (by unfold Entry.vdeps; exact List.mem_append_right _ hd')
      refine List.mem_append_left _ (List.mem_append_right _ (List.mem_append_right _ ?_))
      simp only [argNames, List.flatMap_cons, List.mem_append]
      refine Or.inl ?_
      have hci : argE Γ c = Ec := by simp [argE, hc]
      simp only [hci, htc, ↓reduceIte, nameDeps, List.mem_filter]
      exact ⟨hdEc, hnm⟩
    · refine List.mem_append_right _ (RSetup.mem_allKinds_iff.mpr
        ⟨?_, by
          have hd'n : d'.kind.isName = false := by simpa using hnm
          cases hdk : d'.kind <;> cases hkk : k <;>
            simp_all [comp, Kind.isName]⟩)
      show d'.root ∈ recvRoots c Ec
      unfold recvRoots
      have hd'm : d' ∈ memDeps (derive c Ec .self) ∨ d' ∈ memDeps Ec.held := by
        rcases hd' with hd' | hd'
        · exact Or.inl (List.mem_filter.mpr ⟨hd', by simp only [Bool.not_eq_true] at hnm; simp [hnm]⟩)
        · exact Or.inr (List.mem_filter.mpr ⟨hd', by simp only [Bool.not_eq_true] at hnm; simp [hnm]⟩)
      rcases hd'm with h | h
      · exact List.mem_append_left _ (List.mem_map_of_mem (f := Dep.root) h)
      · exact List.mem_append_right _ (List.mem_map_of_mem (f := Dep.root) h)

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
    (hl : fn.lends ⊆ sig.lends) (hr : fn.rholds ⊆ sig.rholds)
    (hln : ∀ jk ∈ fn.lends, jk.2.isName = false) (hrn : ∀ jk ∈ fn.rholds, jk.2.isName = false) :
    EntryWeaker (rerootE e ((envE c Ec te cs).path ++ (envE c Ec te cs).held)
        (callRes (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs)))
      (recvRes c Ec (callRes Γ sig (c :: zs))) := by
  refine RSetup.EntryWeaker.mk' (by simp [recvRes, rerootE, callRes, hty, hown, resMode])
    (by simp [recvRes, rerootE, callRes, resMode, hown]) (rerootE_callRes_not_fixed _ _ _)
    (by simp [recvRes, rerootE, callRes]) (fun _ => ?_) ?_
  · show reroot e _ (callRes (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs)).path ⊆ _
    exact deps_open hw hrl hni he hzs hc hlc htc hl hln
  · show reroot e _ (ownHeld fn.resOwn fn.resTy _) ⊆
        ownHeld (callRes Γ sig (c :: zs)).mode.ownSlot _ _
    rw [show (callRes Γ sig (c :: zs)).mode.ownSlot = fn.resOwn by
          simp only [callRes, resMode, hown]; cases sig.resOwn <;> rfl,
      show (callRes Γ sig (c :: zs)).ty = fn.resTy by simp [callRes, hty]]
    rw [show (callRes Γ sig (c :: zs)).held
          = ownHeld fn.resOwn fn.resTy (sig.rholds.flatMap (argDeps Γ (c :: zs)) ++ heldOfArgs Γ (c :: zs))
          by simp [callRes, hty, hown]]
    refine reroot_ownHeld ?_
    refine (deps_open hw hrl hni he hzs hc hlc htc hr hrn).trans ?_
    intro d hd
    simp only [List.append_assoc] at hd ⊢
    rcases List.mem_append.mp hd with h1 | h1
    · exact List.mem_append_left _ h1
    · exact List.mem_append_right _ h1

end opened

/-- A binding on no `p` is untouched by `p`'s rerooting, but for an owner's
    `path`, which says nothing. -/
theorem rerootE_noE {p : Var} {D : List Dep} {E E' : Entry} (hw : EntryWeaker E E')
    (hio : ∀ b, E.mode ≠ .inout b) (hne : ∀ d ∈ E.vdeps, d.root ≠ p) :
    EntryWeaker (rerootE p D E) E' := by
  have hh : reroot p D E.held = E.held :=
    reroot_id fun d hd => hne d (by unfold Entry.vdeps; exact List.mem_append_right _ hd)
  have hp : E.mode.ownSlot = false → reroot p D E.path = E.path := fun ho =>
    reroot_id fun d hd => hne d (by unfold Entry.vdeps; rw [ho]; exact List.mem_append_left _ hd)
  refine ⟨hw.ty, hw.mode, fun h => ?_, fun h' => ?_,
      fun h => ⟨(hw.dtor h).1, by show reroot p D E.held ⊆ E'.held; rw [hh]; exact (hw.dtor h).2⟩,
      hw.dbind, hw.raise, fun hd hos hn d hnm => by
        show d ∈ E'.held ↔ d ∈ reroot p D E.held
        rw [hh]; exact hw.dheld hd hos hn d hnm⟩
  · have hf : E.fixed := by simp only [Entry.fixed_def] at h ⊢; rw [rerootE] at h; exact h
    have := hw.fixed hf
    rw [this]; unfold rerootE
    have hrbm : E.mode = .rootb := by
      rcases hf with h' | ⟨b, h', _⟩
      · exact h'
      · exact absurd h' (hio b)
    rw [hh, hp (by rw [hrbm]; rfl)]
  · obtain ⟨hl1, hp1, hh1⟩ := hw.live h'
    refine ⟨hl1, fun ho => ?_, ?_⟩
    · show reroot p D E.path ⊆ E'.path
      rw [hp ho]; exact hp1 ho
    · show reroot p D E.held ⊆ E'.held
      rw [hh]; exact hh1

/-! ### The captures, past the arguments of the call through the package

A capture is an argument of the opened call of its own, after those the
call through the package passes.  It depends on nothing, so the call lends
and holds nothing more through it; a capture it may change ends what the
call through the package ends by that name. -/

theorem flatMap_congr' {α β : Type} {l : List α} {f g : α → List β} (h : ∀ a ∈ l, f a = g a) :
    l.flatMap f = l.flatMap g := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    simp only [List.flatMap_cons]
    rw [h a List.mem_cons_self, ih (fun a' ha' => h a' (List.mem_cons_of_mem _ ha'))]

theorem flatMap_nil_of {α β : Type} {l : List α} {f : α → List β} (h : ∀ a ∈ l, f a = []) :
    l.flatMap f = [] := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    simp only [List.flatMap_cons]
    rw [h a List.mem_cons_self, ih (fun a' ha' => h a' (List.mem_cons_of_mem _ ha'))]; rfl

theorem getD_append_left {as caps : List Var} {j : Nat} (h : j < as.length) :
    (as ++ caps).getD j 0 = as.getD j 0 := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_append_left h]

theorem argDeps_append {Γ : Ctx} {as caps : List Var} {jk : Nat × Kind} (h : jk.1 < as.length) :
    argDeps Γ (as ++ caps) jk = argDeps Γ as jk := by
  unfold argDeps; rw [getD_append_left h]

theorem outHeld_append {Γ : Ctx} {fn : Fn} {as caps : List Var} (ho : ∀ o ∈ fn.outHolds, o.2.1 < as.length)
    (i : Nat) : outHeld Γ fn (as ++ caps) i = outHeld Γ fn as i := by
  unfold outHeld
  exact flatMap_congr' (fun o ho' => argDeps_append (ho o (List.mem_filter.mp ho').1))

theorem heldOfArgs_append_nil {Γ : Ctx} {as caps : List Var} (h : ∀ a ∈ caps, (argE Γ a).vdeps = []) :
    heldOfArgs Γ (as ++ caps) = heldOfArgs Γ as := by
  have hh : ∀ a ∈ caps, (argE Γ a).held = [] := fun a ha => by
    have := h a ha; unfold Entry.vdeps at this; exact (List.append_eq_nil_iff.mp this).2
  unfold heldOfArgs argNames
  rw [List.flatMap_append, List.flatMap_append, flatMap_nil_of (l := caps) (fun a ha => ?_),
    flatMap_nil_of (l := caps) (fun a ha => ?_), List.append_nil, List.append_nil]
  · simp [h a ha, nameDeps]
  · simp [hh a ha, memDeps, roots]

theorem callRes_append {Γ : Ctx} {fn : Fn} {as caps : List Var}
    (hl : ∀ jk ∈ fn.lends, jk.1 < as.length) (hr : ∀ jk ∈ fn.rholds, jk.1 < as.length)
    (hc : ∀ a ∈ caps, (argE Γ a).vdeps = []) : callRes Γ fn (as ++ caps) = callRes Γ fn as := by
  unfold callRes
  rw [heldOfArgs_append_nil hc,
    flatMap_congr' (l := fn.lends) (f := argDeps Γ (as ++ caps)) (g := argDeps Γ as)
      (fun jk hjk => argDeps_append (hl jk hjk)),
    flatMap_congr' (l := fn.rholds) (f := argDeps Γ (as ++ caps)) (g := argDeps Γ as)
      (fun jk hjk => argDeps_append (hr jk hjk))]

theorem callPostAux_append {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps1 ps2 : List (PMode × Ty)) (as1 as2 : List Var) (i : Nat) (Γ : Ctx), ps1.length = as1.length →
      callPostAux Γ0 fn args (ps1 ++ ps2) (as1 ++ as2) i Γ =
        callPostAux Γ0 fn args ps2 as2 (i + ps1.length) (callPostAux Γ0 fn args ps1 as1 i Γ)
  | [], _, [], _, i, Γ, _ => by simp [callPostAux]
  | [], _, _ :: _, _, _, _, h => by simp at h
  | _ :: _, _, [], _, _, _, h => by simp at h
  | (pm, t) :: ps1, ps2, a :: as1, as2, i, Γ, h => by
      have h' : ps1.length = as1.length := by simpa using h
      have hi : i + 1 + ps1.length = i + ((pm, t) :: ps1).length := by simp; omega
      cases pm <;> simp only [List.cons_append, callPostAux] <;>
        rw [callPostAux_append ps1 ps2 as1 as2 _ _ h', hi]

/-- A binding no argument names, depending on nothing, is left as it is. -/
theorem callPostAux_nil_deps {Γ0 : Ctx} {fn : Fn} {args : List Var} {v : Var} {E : Entry}
    (hvd : E.vdeps = []) : ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      v ∉ as → Γ v = some E → callPostAux Γ0 fn args ps as i Γ v = some E := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ h; cases as <;> exact h
  | cons q ps ih =>
    intro as i Γ hva h
    obtain ⟨pm, t⟩ := q
    cases as with
    | nil => cases pm <;> exact h
    | cons a as =>
      have hva' : v ∉ as := fun h' => hva (List.mem_cons_of_mem _ h')
      have hne : v ≠ a := fun h' => hva (h' ▸ List.mem_cons_self)
      have hk : ∀ e hv', A2.kill e hv' a Γ v = some E := fun e hv' => by
        simp [A2.kill, h, killE_nil hvd]
      cases pm with
      | inp => exact ih as (i + 1) Γ hva' h
      | sink => exact ih as (i + 1) _ hva' (by simp only [setE, upd_ne _ _ hne]; exact hk _ _)
      | inout b => exact ih as (i + 1) _ hva' (by simp only [setE, upd_ne _ _ hne]; exact hk _ _)

/-- A borrowed parameter after a call was one before, as it was but for
    being live: the call sets only the arguments it moves or changes. -/
theorem callPostAux_rootb_src {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ p a, (p, a) ∈ ps.zip as → p.1 ≠ .inp → (argE Γ0 a).mode ≠ .rootb) →
      ∀ v E, callPostAux Γ0 fn args ps as i Γ v = some E → E.mode = .rootb →
        ∃ E0, Γ v = some E0 ∧ E0.ty = E.ty ∧ E0.mode = E.mode ∧ E0.vdeps = E.vdeps := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ v E h _; cases as <;> exact ⟨E, h, rfl, rfl, rfl⟩
  | cons q ps ih =>
    intro as i Γ hrb v E h hm
    obtain ⟨pm, t⟩ := q
    cases as with
    | nil => cases pm <;> exact ⟨E, h, rfl, rfl, rfl⟩
    | cons a as =>
      have hrb' : ∀ p a', (p, a') ∈ ps.zip as → p.1 ≠ .inp → (argE Γ0 a').mode ≠ .rootb :=
        fun p a' hm' => hrb p a' (by simp [hm'])
      have hstep : ∀ (e : Eff) (hv : Bool) (Ea : Entry) (E1 : Entry), setE (A2.kill e hv a Γ) a Ea v = some E1 →
          Ea.mode = (argE Γ0 a).mode → pm ≠ .inp → E1.mode = .rootb →
          ∃ E0, Γ v = some E0 ∧ E0.ty = E1.ty ∧ E0.mode = E1.mode ∧ E0.vdeps = E1.vdeps := by
        intro e hv Ea E1 h1 hEa hp hm1
        by_cases hva : v = a
        · subst hva; simp only [setE, upd_same, Option.some.injEq] at h1; subst h1
          exact absurd (hEa ▸ hm1) (hrb (pm, t) v (by simp) hp)
        · simp only [setE, upd_ne _ _ hva, A2.kill] at h1
          obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp h1
          exact ⟨E0, h0, (killE_ty ..).symm, (killE_mode ..).symm, (killE_vdeps ..).symm⟩
      cases pm with
      | inp => exact ih as (i + 1) Γ hrb' v E h hm
      | sink =>
        obtain ⟨E1, h1, ht, hm', hv'⟩ := ih as (i + 1) _ hrb' v E h hm
        obtain ⟨E0, h0, ht0, hm0, hv0⟩ := hstep _ _ _ E1 h1 rfl (by simp) (hm' ▸ hm)
        exact ⟨E0, h0, ht0.trans ht, hm0.trans hm', hv0.trans hv'⟩
      | inout b =>
        obtain ⟨E1, h1, ht, hm', hv'⟩ := ih as (i + 1) _ hrb' v E h hm
        obtain ⟨E0, h0, ht0, hm0, hv0⟩ := hstep _ _ _ E1 h1 rfl (by simp) (hm' ▸ hm)
        exact ⟨E0, h0, ht0.trans ht, hm0.trans hm', hv0.trans hv'⟩

theorem hits_congr {e : Eff} {hv : Bool} {x : Var} {E E' : Entry} (ht : E.ty = E'.ty)
    (hm : E.mode = E'.mode) (hvd : E.vdeps = E'.vdeps) : hits e hv x E = hits e hv x E' := by
  unfold hits; rw [ht, hm, hvd]

theorem hits_none {hv : Bool} {x : Var} {E : Entry} : hits .none hv x E = false := by
  unfold hits; simp [Eff.kills]

theorem killAll_vdeps (ds : List Dep) (E : Entry) : (RSetup.killAll ds E).vdeps = E.vdeps := by
  unfold RSetup.killAll; split <;> rfl

theorem killAll_fixed {ds : List Dep} {E : Entry} : (RSetup.killAll ds E).fixed ↔ E.fixed := by
  unfold RSetup.killAll; split <;> exact Iff.rfl

theorem killAll_id {ds : List Dep} {E : Entry} (h : ∀ d ∈ ds, hits d.kind.bound false d.root E = false) :
    RSetup.killAll ds E = E := by
  unfold RSetup.killAll; rw [ite_eq_right]
  intro hany
  obtain ⟨d, hd, hh⟩ := List.any_eq_true.mp hany
  rw [h d hd] at hh; cases hh

theorem killAll_live {ds : List Dep} {E : Entry} (h : (RSetup.killAll ds E).live = true) :
    (∀ d ∈ ds, hits d.kind.bound false d.root E = false) ∧ RSetup.killAll ds E = E := by
  unfold RSetup.killAll at h ⊢
  split at h
  · simp at h
  · rename_i hn
    refine ⟨fun d hd => ?_, by rw [ite_eq_right hn]⟩
    cases hh : hits d.kind.bound false d.root E
    · rfl
    · exact absurd (List.any_eq_true.mpr ⟨d, hd, hh⟩) hn

theorem killAll_killE (d : Dep) (ds : List Dep) (E : Entry) :
    RSetup.killAll ds (killE d.kind.bound false d.root E) = RSetup.killAll (d :: ds) E := by
  have hl : ∀ (E0 : Entry) (l : Bool), (fun d' : Dep => hits d'.kind.bound false d'.root { E0 with live := l }) =
      (fun d' : Dep => hits d'.kind.bound false d'.root E0) := fun _ _ => rfl
  unfold killE RSetup.killAll
  by_cases h1 : hits d.kind.bound false d.root E = true <;>
  by_cases h2 : ds.any (fun d' => hits d'.kind.bound false d'.root E) = true <;>
    simp [h1, h2, hl]

theorem killAll_cons_none {d : Dep} (hd : d.kind.bound = .none) (ds : List Dep) (E : Entry) :
    RSetup.killAll (d :: ds) E = RSetup.killAll ds E := by
  unfold RSetup.killAll; simp [List.any_cons, hd, hits_none]

/-- The opened call ends no more than the call through the package (`Mc`
    among `M`, or ending nothing), and a fixed binding neither ends. -/
theorem weaker_killAll_more {Mc M : List Dep} {Ed Es : Entry} (hw : EntryWeaker Ed Es)
    (hsub : ∀ d ∈ Mc, d ∈ M ∨ d.kind.bound = .none)
    (hfix : Ed.fixed → ∀ d ∈ M, hits d.kind.bound false d.root Ed = false) :
    EntryWeaker (RSetup.killAll Mc Ed) (RSetup.killAll M Es) := by
  have hMc : (∀ d ∈ M, hits d.kind.bound false d.root Ed = false) → RSetup.killAll Mc Ed = Ed := fun hM =>
    killAll_id fun d hd => by
      rcases hsub d hd with h | h
      · exact hM d h
      · rw [h]; exact hits_none
  have hkt : ∀ (ds : List Dep) (E : Entry), (RSetup.killAll ds E).ty = E.ty ∧ (RSetup.killAll ds E).mode = E.mode :=
    fun ds E => by unfold RSetup.killAll; split <;> exact ⟨rfl, rfl⟩
  have hkd : ∀ (ds : List Dep) (E : Entry), (RSetup.killAll ds E).dtor = E.dtor ∧
      (RSetup.killAll ds E).held = E.held ∧ (RSetup.killAll ds E).dbind = E.dbind :=
    fun ds E => by unfold RSetup.killAll; split <;> exact ⟨rfl, rfl, rfl⟩
  refine ⟨by rw [(hkt _ _).1, (hkt _ _).1, hw.ty], by rw [(hkt _ _).2, (hkt _ _).2, hw.mode], fun hf => ?_,
      fun hl => ?_,
      fun h => by
        rw [(hkd _ _).1] at h; rw [(hkd _ _).1, (hkd _ _).2.1, (hkd _ _).2.1]; exact hw.dtor h,
      by rw [(hkd _ _).2.2, (hkd _ _).2.2, hw.dbind],
      fun h => by rw [(hkd _ _).1] at h; rw [(hkd _ _).1, (hkd _ _).2.2]; exact hw.raise h,
      fun hd hos hn d hnm => by
        rw [(hkd _ _).2.2] at hd; rw [(hkt _ _).2] at hos; rw [(hkt _ _).1, (hkt _ _).2] at hn
        rw [(hkd _ _).2.1, (hkd _ _).2.1]; exact hw.dheld hd hos hn d hnm⟩
  · have hf' := killAll_fixed.mp hf
    have hM := hfix hf'
    rw [hw.fixed hf', hMc hM, killAll_id hM]
  · obtain ⟨hno, heq⟩ := killAll_live hl
    rw [heq] at hl ⊢
    have hM : ∀ d ∈ M, hits d.kind.bound false d.root Ed = false := fun d hd => by
      cases hh : hits d.kind.bound false d.root Ed
      · rfl
      · have := hits_mono hw hl hh
        rw [hno d hd] at this; cases this
    rw [hMc hM]; exact hw.live hl

/-- What the captures end, by name. -/
def capKills (cs : List (Var × PMode × Ty)) : List Dep :=
  cs.map (fun ci => ⟨ci.1, .name ci.2.1.bound ci.2.2⟩)

theorem holdsView_elem {t : Ty} (h : t.holdsView = false) : t.elem.holdsView = false := by
  cases t <;> simp_all [Ty.elem, Ty.holdsView]

/-- The opened call's captures, past the other arguments: one it may change
    is as it was (it depends on nothing, and is handed back), and what may
    depend on it ends as the change says. -/
theorem callPostAux_caps {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (cs : List (Var × PMode × Ty)) (i : Nat) (Γ : Ctx),
      (∀ ci ∈ cs, (argE Γ0 ci.1).vdeps = [] ∧ ci.2.2.holdsView = false ∧
        (ci.2.1 = .inp ∨ ∃ b, ci.2.1 = .inout b)) →
      ∀ v, ((∃ ci ∈ cs, ci.1 = v ∧ ci.2.1 ≠ .inp) →
          callPostAux Γ0 fn args (cs.map (·.2)) (cs.map (·.1)) i Γ v = some (argE Γ0 v)) ∧
        ((∀ ci ∈ cs, ci.1 = v → ci.2.1 = .inp) →
          callPostAux Γ0 fn args (cs.map (·.2)) (cs.map (·.1)) i Γ v =
            (Γ v).map (RSetup.killAll (capKills cs))) := by
  intro cs
  induction cs with
  | nil =>
    intro i Γ _ v
    refine ⟨fun ⟨_, h, _⟩ => (by cases h), fun _ => ?_⟩
    cases h : Γ v <;> simp [callPostAux, capKills, RSetup.killAll, h]
  | cons ci cs ih =>
    intro i Γ hcs v
    obtain ⟨v0, pm, t⟩ := ci
    obtain ⟨hv0, hvf, hpm⟩ := hcs (v0, pm, t) List.mem_cons_self
    have hcs' : ∀ ci ∈ cs, _ := fun ci hci => hcs ci (List.mem_cons_of_mem _ hci)
    simp only at hv0 hvf hpm
    rcases hpm with rfl | ⟨b, rfl⟩
    · have hst : callPostAux Γ0 fn args (((v0, PMode.inp, t) :: cs).map (·.2))
          (((v0, PMode.inp, t) :: cs).map (·.1)) i Γ =
          callPostAux Γ0 fn args (cs.map (·.2)) (cs.map (·.1)) (i + 1) Γ := by
        simp only [List.map_cons, callPostAux]
      rw [hst]
      have hih := ih (i + 1) Γ hcs' v
      refine ⟨fun ⟨ci, hci, hv, hn⟩ => ?_, fun hall => ?_⟩
      · rcases List.mem_cons.mp hci with rfl | hci
        · exact absurd rfl hn
        · exact hih.1 ⟨ci, hci, hv, hn⟩
      · rw [hih.2 (fun ci hci => hall ci (List.mem_cons_of_mem _ hci))]
        unfold capKills
        simp only [List.map_cons]
        cases Γ v with
        | none => rfl
        | some E => simp only [Option.map_some]; rw [killAll_cons_none (by rfl)]
    · have hst : callPostAux Γ0 fn args (((v0, PMode.inout b, t) :: cs).map (·.2))
          (((v0, PMode.inout b, t) :: cs).map (·.1)) i Γ =
          callPostAux Γ0 fn args (cs.map (·.2)) (cs.map (·.1)) (i + 1)
            (setE (A2.kill b false v0 Γ) v0 (argE Γ0 v0)) := by
        simp only [List.map_cons, callPostAux, holdsView_elem hvf, hvf, Bool.false_eq_true, ↓reduceIte]
      rw [hst]
      have hih := ih (i + 1) (setE (A2.kill b false v0 Γ) v0 (argE Γ0 v0)) hcs' v
      refine ⟨fun ⟨ci, hci, hv, hn⟩ => ?_, fun hall => ?_⟩
      · by_cases hex : ∃ ci' ∈ cs, ci'.1 = v ∧ ci'.2.1 ≠ .inp
        · exact hih.1 hex
        · have hall : ∀ ci' ∈ cs, ci'.1 = v → ci'.2.1 = .inp := fun ci' hci' hv' =>
            Classical.byContradiction fun hn' => hex ⟨ci', hci', hv', hn'⟩
          rw [hih.2 hall]
          have hv0v : v0 = v := by
            rcases List.mem_cons.mp hci with rfl | hci
            · exact hv
            · exact absurd (hall ci hci hv) hn
          subst hv0v
          simp only [setE, upd_same, Option.map_some]
          rw [killAll_id (fun d _ => RSetup.hits_false_of (fun d' hd' _ => by rw [hv0] at hd'; cases hd'))]
      · have hne : v ≠ v0 := fun h => by
          subst h; exact absurd (hall _ List.mem_cons_self rfl) (by simp)
        rw [hih.2 (fun ci hci => hall ci (List.mem_cons_of_mem _ hci))]
        simp only [setE, upd_ne _ _ hne, A2.kill, Option.map_map]
        unfold capKills
        simp only [List.map_cons]
        cases Γ v with
        | none => rfl
        | some E =>
          simp only [Option.map_some, Function.comp]
          exact congrArg some (killAll_killE ⟨v0, .name b t⟩ _ E)

/-- Past the arguments, the captures keep the relation: one the opened call
    may change is handed back as it was, which says no less than what the
    call through the package leaves of it. -/
theorem killAll_append (A B : List Dep) (E : Entry) :
    RSetup.killAll A (RSetup.killAll B E) = RSetup.killAll (A ++ B) E := by
  have hv : ∀ (l : Bool), (fun d : Dep => hits d.kind.bound false d.root { E with live := l }) =
      (fun d : Dep => hits d.kind.bound false d.root E) := fun _ => rfl
  unfold RSetup.killAll
  by_cases hB : B.any (fun d => hits d.kind.bound false d.root E) = true <;>
  by_cases hA : A.any (fun d => hits d.kind.bound false d.root E) = true <;>
    simp [hA, hB, hv, List.any_append]

theorem PostRel.caps {e : Var} {Γd Γs Γe : Ctx} {Mc M : List Dep} {cs : List (Var × PMode × Ty)}
    {fn : Fn} {args : List Var} {i : Nat} (h : PostRel e Γd Γs)
    (hMc : ∀ d ∈ Mc, d ∈ M ∨ d.kind.bound = .none)
    (hcs : ∀ ci ∈ cs, (argE Γe ci.1).vdeps = [] ∧ ci.2.2.holdsView = false ∧
      (ci.2.1 = .inp ∨ ∃ b, ci.2.1 = .inout b))
    (hcd : ∀ ci ∈ cs, ci.2.1 ≠ .inp →
      ∃ Es, Γs ci.1 = some Es ∧ EntryWeaker (argE Γe ci.1) Es ∧ ¬ (argE Γe ci.1).fixed)
    (hM : ∀ d ∈ capKills cs, d ∈ M ∨ d.kind.bound = .none)
    (hfix : ∀ v Ed, v ≠ e → Γd v = some Ed → Ed.fixed → ∀ d ∈ M, hits d.kind.bound false d.root Ed = false) :
    PostRel e (killNames Mc (callPostAux Γe fn args (cs.map (·.2)) (cs.map (·.1)) i Γd)) (killNames M Γs) := by
  intro v hve
  have hC := callPostAux_caps (Γ0 := Γe) (fn := fn) (args := args) cs i Γd hcs v
  rw [RSetup.killNames_eq, RSetup.killNames_eq]
  by_cases hex : ∃ ci ∈ cs, ci.1 = v ∧ ci.2.1 ≠ .inp
  · rw [hC.1 hex]
    obtain ⟨ci, hci, rfl, hni⟩ := hex
    obtain ⟨Es, hEs, hw, hnf⟩ := hcd ci hci hni
    rw [hEs]
    refine ⟨by simp, fun Ed Es' h1 h2 => ?_⟩
    simp only [Option.map_some, Option.some.injEq] at h1 h2; subst h1 h2
    refine ⟨?_, fun d hd => by rw [killAll_vdeps, (hcs ci hci).1] at hd; cases hd⟩
    exact weaker_killAll_more hw hMc (fun hf => absurd hf hnf)
  · have hall : ∀ ci ∈ cs, ci.1 = v → ci.2.1 = .inp := fun ci hci hv =>
      Classical.byContradiction fun hn => hex ⟨ci, hci, hv, hn⟩
    rw [hC.2 hall]
    obtain ⟨hn, hw⟩ := h v hve
    refine ⟨by simp [hn], fun Ed Es h1 h2 => ?_⟩
    obtain ⟨Ed1, hd1, rfl⟩ := Option.map_eq_some_iff.mp h1
    obtain ⟨Ed0, hd0, rfl⟩ := Option.map_eq_some_iff.mp hd1
    obtain ⟨Es0, hs0, rfl⟩ := Option.map_eq_some_iff.mp h2
    obtain ⟨hw', hne⟩ := hw Ed0 Es0 hd0 hs0
    rw [killAll_append]
    refine ⟨weaker_killAll_more hw' (fun d hd => ?_) (hfix v Ed0 hve hd0), by rw [killAll_vdeps]; exact hne⟩
    rcases List.mem_append.mp hd with hd | hd
    · exact hMc d hd
    · exact hM d hd

/-- Once the environment is dropped, the context after the opened call says
    no less than the one after the call through the package. -/
theorem weaker_open {Γ : Ctx} {e c x : Var} {Ec : Entry} {te t0 : Ty} {zs : List Var} {fn sig : Fn}
    {rest : List (PMode × Ty)} {cs : List (Var × PMode × Ty)} (hw : CtxWF Γ)
    (hrl : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true)
    (hni : ∀ v E b, Γ v = some E → E.mode ≠ .inout b)
    (he : Γ e = none) (hzs : ∀ k, zs.getD k 0 ≠ e) (hc : Γ c = some Ec) (hlc : Ec.live = true)
    (htc : Ec.ty ≠ .int) (hxe : x ≠ e)
    (hps : fn.params = (.inp, te) :: rest ++ cs.map (·.2)) (hsp : sig.params = (.inp, t0) :: rest)
    (hzr : zs.length = rest.length)
    (hty : fn.resTy = sig.resTy) (hown : fn.resOwn = sig.resOwn)
    (hl : fn.lends ⊆ sig.lends) (hr : fn.rholds ⊆ sig.rholds) (ho : fn.outHolds ⊆ sig.outHolds)
    (hln : ∀ jk ∈ fn.lends, jk.2.isName = false) (hrn : ∀ jk ∈ fn.rholds, jk.2.isName = false)
    (hnz : ∀ o ∈ sig.outHolds, o.2.1 ≠ 0)
    (hbl : ∀ jk ∈ sig.lends, jk.1 < zs.length + 1) (hbr : ∀ jk ∈ sig.rholds, jk.1 < zs.length + 1)
    (hbo : ∀ o ∈ sig.outHolds, o.2.1 < zs.length + 1)
    (hrb : ∀ p a, (p, a) ∈ rest.zip zs → p.1 ≠ .inp → (argE Γ a).mode ≠ .rootb)
    (hio : ∀ p a, (p, a) ∈ rest.zip zs → ∀ b, p.1 = .inout b → (argE Γ a).dbind = false)
    (hcap : ∀ ci ∈ cs, ∃ Ev, Γ ci.1 = some Ev ∧ Ev.vdeps = [] ∧ Ev.mode = .own ∧ ci.2.2.holdsView = false ∧
      (ci.2.1 = .inp ∨ ∃ b, ci.2.1 = .inout b ∧ ci.1 ∉ zs ∧
        (⟨ci.1, .name b ci.2.2⟩ : Dep) ∈ mutNames Γ (c :: zs)))
    (hMr : ∀ v E, Γ v = some E → E.mode = .rootb →
      ∀ d ∈ mutNames Γ (c :: zs), hits d.kind.bound false d.root E = false)
    (hMc : ∀ d ∈ mutNames (setE (cleanC Γ) e (envE c Ec te cs)) (e :: zs ++ cs.map (·.1)),
      d ∈ mutNames Γ (c :: zs))
    (hse : callPost Γ sig (c :: zs) e = none)
    (hwf : CtxWF (setE (callPost Γ sig (c :: zs)) x (recvRes c Ec (callRes Γ sig (c :: zs)))))
    (hnf : NameWF (setE (callPost Γ sig (c :: zs)) x (recvRes c Ec (callRes Γ sig (c :: zs))))) :
    Weaker (exitRoot e ((envE c Ec te cs).path ++ (envE c Ec te cs).held)
        (setE (callPost (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs ++ cs.map (·.1))) x
          (callRes (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs ++ cs.map (·.1)))))
      (setE (callPost Γ sig (c :: zs)) x (recvRes c Ec (callRes Γ sig (c :: zs)))) := by
  have hzs' : ∀ a ∈ zs, a ≠ e := by
    intro a ha
    obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem ha
    have := hzs k; rwa [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk, Option.getD_some] at this
  let Γe := setE (cleanC Γ) e (envE c Ec te cs)
  -- the captures, in the opened call's context
  have hcE : ∀ ci ∈ cs, ∃ Ev, Γ ci.1 = some Ev ∧ argE Γe ci.1 = Ev.clean ∧ Ev.vdeps = [] := by
    intro ci hci
    obtain ⟨Ev, hEv, hvd, _⟩ := hcap ci hci
    have hne : ci.1 ≠ e := fun h => by rw [h, he] at hEv; cases hEv
    exact ⟨Ev, hEv, (argE_open (Γ := Γ) (c := c) (Ec := Ec) (te := te) hne).trans (by simp [argE, hEv]), hvd⟩
  have hcv : ∀ a ∈ cs.map (·.1), (argE Γe a).vdeps = [] := by
    intro a ha
    obtain ⟨ci, hci, hca⟩ := List.mem_map.mp ha
    subst hca
    obtain ⟨Ev, _, hE, hvd⟩ := hcE ci hci
    show (argE Γe ci.1).vdeps = []
    rw [hE]; exact List.eq_nil_of_subset_nil (hvd ▸ clean_vdeps_sub Ev)
  have hA : (e :: zs ++ cs.map (·.1)) = (e :: zs) ++ cs.map (·.1) := rfl
  -- the opened call lends, holds and stores nothing through the captures
  have hres : callRes Γe fn (e :: zs ++ cs.map (·.1)) = callRes Γe fn (e :: zs) := by
    rw [hA]; exact callRes_append (fun jk h => hbl jk (hl h)) (fun jk h => hbr jk (hr h)) hcv
  have hout : ∀ i, outHeld Γe fn (e :: zs ++ cs.map (·.1)) i = outHeld Γe fn (e :: zs) i := fun i => by
    rw [hA]; exact outHeld_append (as := e :: zs) (caps := cs.map (·.1)) (fun o h => hbo o (ho h)) i
  have hheld : heldOfArgs Γe (e :: zs ++ cs.map (·.1)) = heldOfArgs Γe (e :: zs) := by
    rw [hA]; exact heldOfArgs_append_nil hcv
  -- the two contexts after the call, past the receiver
  have hd : callPost Γe fn (e :: zs ++ cs.map (·.1)) =
      killNames (mutNames Γe (e :: zs ++ cs.map (·.1)))
        (callPostAux Γe fn (e :: zs ++ cs.map (·.1)) (cs.map (·.2)) (cs.map (·.1)) (1 + rest.length)
          (callPostAux Γe fn (e :: zs ++ cs.map (·.1)) rest zs 1 Γe)) := by
    unfold callPost; rw [hps]
    congr 1
    show callPostAux Γe fn _ (rest ++ cs.map (·.2)) (zs ++ cs.map (·.1)) 1 Γe = _
    exact callPostAux_append rest _ zs _ 1 Γe hzr.symm
  have hs : callPost Γ sig (c :: zs) =
      killNames (mutNames Γ (c :: zs)) (callPostAux Γ sig (c :: zs) rest zs 1 Γ) := by
    unfold callPost; rw [hsp]; rfl
  have h0 : PostRel e Γe Γ := by
    intro v hve
    simp only [Γe, setE, upd_ne _ _ hve]
    refine ⟨cleanC_none, fun Ed Es hd hs => ?_⟩
    obtain ⟨E0, h0, rfl⟩ := cleanC_some hd
    rw [h0] at hs; cases hs
    exact ⟨clean_weaker _, clean_noE hw hrl hni he h0⟩
  have hR1 := post_rel (Γe := Γe) (Γ := Γ) (fn := fn) (sig := sig)
    (A := e :: zs ++ cs.map (·.1)) (C := c :: zs)
    (fun i _ => by rw [hout]; exact outHeld_open hw hrl hni he hzs ho hnz i)
    (by rw [hheld]; exact heldOfArgs_open hw hrl hni he hzs hc hlc htc) rest zs 1 _ _ (Nat.le_refl _)
    (fun a ha => ⟨hzs' a ha, argE_open (hzs' a ha), by rw [argE_open (hzs' a ha)]; exact argE_noE hw hrl hni he a⟩)
    (fun p a hz hp hf => by
      rcases hf with hrb' | ⟨b, hb, _⟩
      · exact hrb p a hz hp hrb'
      · unfold argE at hb
        cases hca : Γ a with
        | none => rw [hca] at hb; simp [intE] at hb
        | some E0 => rw [hca] at hb; exact hni a E0 b hca hb) hio h0
  -- no binding of the opened call's context is `inout`
  have hniE : ∀ v E b, Γe v = some E → E.mode ≠ .inout b := by
    intro v E b hv
    by_cases hve : v = e
    · subst hve; simp only [Γe, setE, upd_same, Option.some.injEq] at hv; subst hv; simp [envE]
    · simp only [Γe, setE, upd_ne _ _ hve] at hv
      obtain ⟨E0, h0, rfl⟩ := cleanC_some hv
      rw [clean_mode]; exact hni v E0 b h0
  have hR := hR1.caps (M := mutNames Γ (c :: zs)) (Γe := Γe) (fn := fn) (args := e :: zs ++ cs.map (·.1))
    (i := 1 + rest.length) (cs := cs) (fun d hd => Or.inl (hMc d hd))
    (fun ci hci => by
      obtain ⟨Ev, hEv, hvd, _, hvf, hmd⟩ := hcap ci hci
      refine ⟨hcv _ (List.mem_map_of_mem hci), hvf, ?_⟩
      rcases hmd with h | ⟨b, h, _⟩
      · exact Or.inl h
      · exact Or.inr ⟨b, h⟩)
    (fun ci hci hnp => by
      obtain ⟨Ev, hEv, hvd, hmo, _, hmd⟩ := hcap ci hci
      rcases hmd with h | ⟨b, _, hnz', _⟩
      · exact absurd h hnp
      obtain ⟨Ev', hEv', hE, _⟩ := hcE ci hci
      rw [hEv] at hEv'; cases hEv'
      refine ⟨Ev, callPostAux_nil_deps hvd rest zs 1 Γ hnz' hEv, by rw [hE]; exact clean_weaker Ev, ?_⟩
      rw [hE]; simp [Entry.fixed_def, clean_mode, hmo])
    (fun d hd => by
      unfold capKills at hd
      obtain ⟨ci, hci, rfl⟩ := List.mem_map.mp hd
      obtain ⟨_, _, _, _, _, hmd⟩ := hcap ci hci
      rcases hmd with h | ⟨b, h, _, hm⟩
      · right; simp [Kind.bound, h, PMode.bound]
      · left; rw [h]; exact hm)
    (fun v Ed hve hv hf => by
      obtain ⟨hn, hwk⟩ := hR1 v hve
      obtain ⟨Es, hs1⟩ : ∃ Es, callPostAux Γ sig (c :: zs) rest zs 1 Γ v = some Es := by
        cases h : callPostAux Γ sig (c :: zs) rest zs 1 Γ v with
        | none => exact absurd (hn.mpr h) (by rw [hv]; simp)
        | some Es => exact ⟨Es, rfl⟩
      obtain ⟨hw', _⟩ := hwk Ed Es hv hs1
      have hEs := hw'.fixed hf
      have hrbE : Ed.mode = .rootb := by
        rcases hf with h | ⟨b, h, _⟩
        · exact h
        · exact absurd h (callPostAux_noInout hniE rest zs 1 Γe hniE v Ed b hv)
      rw [hEs] at hs1
      obtain ⟨E0, h0, ht0, hm0, hv0⟩ := callPostAux_rootb_src rest zs 1 Γ hrb v Ed hs1 hrbE
      intro d hd
      rw [← hits_congr ht0 hm0 hv0]
      exact hMr v E0 h0 (hm0.trans hrbE) d hd)
  rw [← hd, ← hs] at hR
  refine ⟨fun v => ?_, hwf, hnf⟩
  by_cases hve : v = e
  · subst hve
    have h1 : exitRoot v ((envE c Ec te cs).path ++ (envE c Ec te cs).held)
        (setE (callPost (setE (cleanC Γ) v (envE c Ec te cs)) fn (v :: zs ++ cs.map (·.1))) x
          (callRes (setE (cleanC Γ) v (envE c Ec te cs)) fn (v :: zs ++ cs.map (·.1)))) v = none := by
      simp [exitRoot]
    have h2 : setE (callPost Γ sig (c :: zs)) x (recvRes c Ec (callRes Γ sig (c :: zs))) v = none := by
      simp [setE, upd_ne _ _ (Ne.symm hxe), hse]
    rw [h1, h2]; exact ⟨Iff.rfl, fun _ _ h => by cases h⟩
  · by_cases hvx : v = x
    · subst hvx
      rw [show callRes (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs ++ cs.map (·.1)) =
        callRes (setE (cleanC Γ) e (envE c Ec te cs)) fn (e :: zs) from hres]
      simp only [exitRoot, setE, upd_ne _ _ hve, upd_same, Option.map_some]
      refine ⟨by simp, fun Ed Es h1 h2 => ?_⟩
      cases h1; cases h2
      exact res_open hw hrl hni he hzs hc hlc htc hty hown hl hr hln hrn
    · simp only [exitRoot, setE, upd_ne _ _ hve, upd_ne _ _ hvx]
      obtain ⟨hn, hwk⟩ := hR v hve
      refine ⟨by rw [Option.map_eq_none_iff]; exact hn, fun Ed Es h1 h2 => ?_⟩
      obtain ⟨Ed0, hd0, rfl⟩ := Option.map_eq_some_iff.mp h1
      obtain ⟨hw', hne⟩ := hwk Ed0 Es hd0 h2
      refine rerootE_noE hw' (fun b hb => ?_) hne
      exact callPost_noInout hni sig (c :: zs) v Es b h2 (hw'.mode ▸ hb)

/-! ### The captures of an opened package -/

/-- A capture of a live package: a live owned binding, holding nothing, of the
    recorded type, read, or changed within its bound as recorded. -/
theorem pkg_cap {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c : Var} {Ec : Entry} (hc : Γ c = some Ec)
    (hl : Ec.live = true) {ms : List Nat} (ht : Ec.ty = .fn ms) {o : Bool} {fs : List Nat} {te : Ty}
    {env : Val} {cs : List (Var × PMode × Ty)} (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩)
    {ci : Var × PMode × Ty} (hci : ci ∈ cs) :
    ∃ Ev, Γ ci.1 = some Ev ∧ Ev.live = true ∧ Ev.held = [] ∧ Ev.ty = ci.2.2 ∧ Ev.mode = .own ∧
      Ev.vdeps = [] ∧ ci.2.2.holdsView = false ∧
      (ci.2.1 = .inp ∨ ∃ b, ci.2.1 = .inout b ∧ b ≠ .none ∧ b ≠ .replace ∧ canDo Ev.mode b) := by
  obtain ⟨_, _, hcaps⟩ := pkg_caps hi hc hl ht hslot
  obtain ⟨Ev, hEv, hlv, hhv, htv, hov, hvv, hbd⟩ := hcaps ci hci
  have hmo : Ev.mode = .own := by
    rcases hi.mode_cases hEv with h | h | h
    · exact h
    · rw [h] at hov; cases hov
    · rw [h] at hov; cases hov
  have hmd := (hi.pkgs c _ _ hslot rfl fs te ms env cs (Sub.refl _)).2.1 ci hci
  refine ⟨Ev, hEv, hlv, hhv, htv, hmo, by simp [Entry.vdeps, hmo, Mode.ownSlot, hhv], hvv, ?_⟩
  rcases hmd with h | ⟨b, hb, hbn⟩
  · exact Or.inl h
  · refine Or.inr ⟨b, hb, hbn, ?_⟩
    simp only [hb, PMode.bound] at hbd
    rcases hbd with h | h
    · exact absurd h hbn
    · exact h

/-- What a package captures it names: the capture is a root of what it holds. -/
theorem pkg_cap_root {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c : Var} {Ec : Entry} (hc : Γ c = some Ec)
    (hl : Ec.live = true) {o : Bool} {fs : List Nat} {te : Ty} {ms : List Nat}
    {env : Val} {cs : List (Var × PMode × Ty)} (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩)
    {ci : Var × PMode × Ty} (hci : ci ∈ cs) :
    (⟨ci.1, .name ci.2.1.bound ci.2.2⟩ : Dep) ∈ Ec.held :=
  hi.held c Ec _ _ hc hl hslot rfl ci (by simp only [Val.names, List.mem_append]; exact Or.inl hci)

/-- A capture the package may change is a name the call through it may
    change. -/
theorem pkg_cap_mutName {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {c : Var} {Ec : Entry} (hc : Γ c = some Ec)
    (hl : Ec.live = true) {ms : List Nat} (ht : Ec.ty = .fn ms) {o : Bool} {fs : List Nat} {te : Ty}
    {env : Val} {cs : List (Var × PMode × Ty)} (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩)
    {ci : Var × PMode × Ty} (hci : ci ∈ cs) {b : Eff} (hb : ci.2.1 = .inout b) (hbn : b ≠ .none)
    (zs : List Var) : (⟨ci.1, .name b ci.2.2⟩ : Dep) ∈ mutNames Γ (c :: zs) := by
  have hin := pkg_cap_root hi hc hl hslot hci
  rw [hb] at hin
  unfold mutNames argNames
  refine List.mem_filter.mpr ⟨List.mem_flatMap.mpr ⟨c, List.mem_cons_self, ?_⟩, ?_⟩
  · have hae : argE Γ c = Ec := by unfold argE; rw [hc]; rfl
    rw [hae, ite_eq_right (by rw [ht]; simp)]
    exact List.mem_filter.mpr ⟨by unfold Entry.vdeps; exact List.mem_append_right _ hin, rfl⟩
  · simp [Kind.bound, hbn]

/-- A capture the package may change is among what the call through it
    changes by name: it is not lent out, not an argument of the call, and
    reached from the arguments only by names that may change it. -/
theorem pkg_cap_mut {P : Prog} {m : Mem} {Γ Γ1 : Ctx} (hi : MInv m Γ) {F : List Var} {σ : Nat}
    {c : Var} {zs : List Var} {E Ec : Entry} (hcT : CallT P Γ F σ (c :: zs) E Γ1)
    (hnz : ∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) (hc : Γ c = some Ec)
    (hl : Ec.live = true) {ms : List Nat} (ht : Ec.ty = .fn ms) {o : Bool} {fs : List Nat} {te : Ty}
    {env : Val} {cs : List (Var × PMode × Ty)} (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩)
    {ci : Var × PMode × Ty} (hci : ci ∈ cs) {b : Eff} (hb : ci.2.1 = .inout b) (hbn : b ≠ .none) :
    ci.1 ∉ F ∧ ci.1 ∉ c :: zs ∧
      ∀ a ∈ c :: zs, ((argE Γ a).ty ≠ .int ∨ (argE Γ a).mode = .rootb) →
        ∀ d' ∈ (argE Γ a).vdeps, d'.root = ci.1 → d'.kind.bound = b := by
  obtain ⟨_, _, _, _, hnf, _, _⟩ := hcT
  have hdm := pkg_cap_mutName hi hc hl ht hslot hci hb hbn zs
  obtain ⟨_, _, hF, _, hx⟩ := hnf _ hdm
  have hin := pkg_cap_root hi hc hl hslot hci
  rw [hb] at hin
  refine ⟨hF, fun hm => ?_, hx⟩
  rcases List.mem_cons.mp hm with hm | hm
  · -- the receiver is a closure, the capture a `Vec`
    obtain ⟨Ev, hEv, _, _, htv, _⟩ := (pkg_caps hi hc hl ht hslot).2.2 ci hci
    rw [hm, hc] at hEv; cases hEv
    rw [ht] at htv
    obtain ⟨_, hmd, _⟩ := hi.pkgs c _ _ hslot rfl fs te ms env cs (Sub.refl _)
    rcases hmd ci hci with h' | ⟨b', hb', _⟩
    · rw [h'] at hb; cases hb
    · -- (a closure holds views; what is held by name holds none)
      have := hi.names c Ec hc hl (Or.inl (by rw [ht]; simp)) ⟨ci.1, .name b ci.2.2⟩
        (by unfold Entry.vdeps; exact List.mem_append_right _ hin) b ci.2.2 rfl
      obtain ⟨_, _, _, _, _, _, _, hhv⟩ := this
      rw [← htv] at hhv; cases hhv
  · exact hnz _ hm ⟨ci.1, .name b ci.2.2⟩ (by unfold Entry.vdeps; exact List.mem_append_right _ hin)
      (by simp [Kind.bound, hbn]) rfl

/-- The opened environment never reaches a capture the package may change:
    the package reaches one only by names that may change it. -/
theorem envE_cap_out {P : Prog} {m : Mem} {Γ Γ1 : Ctx} (hi : MInv m Γ) {F : List Var} {σ : Nat}
    {c : Var} {zs : List Var} {E Ec : Entry} (hcT : CallT P Γ F σ (c :: zs) E Γ1)
    (hnz : ∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) (hc : Γ c = some Ec)
    (hl : Ec.live = true) {ms : List Nat} (ht : Ec.ty = .fn ms) {o : Bool} {fs : List Nat} {te : Ty}
    {env : Val} {cs : List (Var × PMode × Ty)} (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩)
    {ci : Var × PMode × Ty} (hci : ci ∈ cs) {b : Eff} (hb : ci.2.1 = .inout b) (hbn : b ≠ .none) :
    ci.1 ∉ roots (envE c Ec te cs).vdeps := by
  obtain ⟨_, hA, hx⟩ := pkg_cap_mut hi hcT hnz hc hl ht hslot hci hb hbn
  have hnint : Ec.ty ≠ .int := by rw [ht]; simp
  have hae : argE Γ c = Ec := by unfold argE; rw [hc]; rfl
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  rw [envE_vdeps] at hd
  obtain ⟨hd, hb0⟩ := mem_envE_deps hd
  have hdv : d ∈ Ec.vdeps := by
    rcases hd with hd | hd
    · by_cases hrt : Ec.mode.isRoot
      · unfold derive at hd; rw [ite_eq_left hrt] at hd
        simp only [List.mem_singleton] at hd; subst hd
        exact absurd (show ci.1 ∈ c :: zs by
          rw [← (show c = ci.1 from hdr)]; exact List.mem_cons_self) hA
      · rw [derive_bor_self (by simpa using hrt)] at hd
        have hos : Ec.mode.ownSlot = false := by
          cases hm : Ec.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
        unfold Entry.vdeps; rw [hos]; exact List.mem_append_left _ hd
    · unfold Entry.vdeps; exact List.mem_append_right _ hd
  -- the package reaches its capture only by its own change of it, which the
  -- environment does not hold
  have hbd := hx c List.mem_cons_self (by rw [hae]; exact Or.inl hnint) d (by rw [hae]; exact hdv) hdr
  simp only [ownWriter, Bool.and_eq_false_iff, bne_eq_false_iff_eq] at hb0
  rcases hb0 with hb0 | hb0
  · rw [hbd] at hb0; exact hbn hb0
  · have hin : d.root ∈ capRootsW cs := by
      rw [hdr]
      simp only [capRootsW, List.mem_map, List.mem_filter]
      exact ⟨ci, ⟨hci, by rw [hb]; simp⟩, rfl⟩
    simp [hin] at hb0

/-! ### The arguments of an opened package call: environment, arguments, captures -/

theorem openArgs_zero (a : Var) (zs caps : List Var) : (a :: zs ++ caps).getD 0 0 = a := rfl

theorem openArgs_z (a : Var) {zs : List Var} (caps : List Var) {i : Nat} (hi : i < zs.length) :
    (a :: zs ++ caps).getD (i + 1) 0 = zs.getD i 0 := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_append_left hi, hi]

theorem openArgs_c (a : Var) (zs : List Var) {cs : List (Var × PMode × Ty)} {k : Nat} (hk : k < cs.length) :
    (a :: zs ++ cs.map (·.1)).getD (zs.length + 1 + k) 0 = (cs[k]'hk).1 := by
  have h1 : (a :: zs ++ cs.map (·.1)) = (a :: zs) ++ cs.map (·.1) := rfl
  rw [h1, List.getD_eq_getElem?_getD, List.getElem?_append_right (by simp <;> omega)]
  simp [hk, show zs.length + 1 + k - (zs.length + 1) = k by omega]

theorem openArgs_cases {zs : List Var} {n j : Nat} (hj : j < 1 + zs.length + n) :
    j = 0 ∨ (∃ i < zs.length, j = i + 1) ∨ (∃ k < n, j = zs.length + 1 + k) := by
  rcases Nat.eq_zero_or_pos j with h | h
  · exact Or.inl h
  · by_cases hz : j ≤ zs.length
    · exact Or.inr (Or.inl ⟨j - 1, by omega, by omega⟩)
    · exact Or.inr (Or.inr ⟨j - zs.length - 1, by omega, by omega⟩)

theorem openParams_z {p0 : PMode × Ty} {rest cps : List (PMode × Ty)} {i : Nat} (hi : i < rest.length) :
    (p0 :: rest ++ cps)[i + 1]? = rest[i]? := by
  have h1 : (p0 :: rest ++ cps) = (p0 :: rest) ++ cps := rfl
  rw [h1, List.getElem?_append_left (by simp; omega)]; simp

theorem openParams_c {p0 : PMode × Ty} {rest : List (PMode × Ty)} {cs : List (Var × PMode × Ty)}
    {k : Nat} (hk : k < cs.length) :
    (p0 :: rest ++ cs.map (·.2))[rest.length + 1 + k]? = some (cs[k]'hk).2 := by
  have h1 : (p0 :: rest ++ cs.map (·.2)) = (p0 :: rest) ++ cs.map (·.2) := rfl
  rw [h1, List.getElem?_append_right (by simp <;> omega)]
  simp [hk, show rest.length + 1 + k - (rest.length + 1) = k by omega]

/-- What the typing lends for the opened call: everything the run-time form
    holds still but what the call's closures may change by name. -/
def heldN (Γe : Ctx) (ps : List (PMode × Ty)) (args : List Var) (base x : Nat) : List Var :=
  (heldFor ps args base x).filter (fun v => !(roots (mutNames Γe args)).contains v)

theorem heldN_sub (Γe : Ctx) (ps : List (PMode × Ty)) (args : List Var) (base x : Nat) :
    heldN Γe ps args base x ⊆ heldFor ps args base x := fun _ h => (List.mem_filter.mp h).1

theorem mem_heldN {Γe : Ctx} {ps : List (PMode × Ty)} {args : List Var} {base x v : Nat} :
    v ∈ heldN Γe ps args base x ↔ v ∈ heldFor ps args base x ∧ v ∉ roots (mutNames Γe args) := by
  simp [heldN, List.mem_filter]

/-- What the environment's names are held through: the package's own
    change of a capture is no part of it (one captured again inside is
    only read). -/
theorem envNames_own {env : Val} {cs : List (Var × PMode × Ty)}
    (hdis : ∀ ci ∈ cs, ∀ ci' ∈ env.names, ci.1 = ci'.1 → ci.2.1 = .inp ∧ ci'.2.1 = .inp) :
    ∀ c' ∈ env.names, ownWriter cs (⟨c'.1, .name c'.2.1.bound c'.2.2⟩ : Dep) = false := by
  intro c' hc'
  simp only [ownWriter, Bool.and_eq_false_iff, bne_eq_false_iff_eq, Kind.bound]
  by_cases hin : c'.1 ∈ capRootsW cs
  · left
    simp only [capRootsW, List.mem_map, List.mem_filter, bne_iff_ne, ne_eq] at hin
    obtain ⟨ci, ⟨hci, _⟩, hcc⟩ := hin
    rw [(hdis ci hci c' hc' hcc).2]; rfl
  · right; simpa [List.contains_iff_mem] using hin

/-- A dependency of the opened environment: the package's own handle, or one
    of the package's. -/
theorem envE_dep_vdeps {c : Var} {Ec : Entry} {te : Ty} {cs : List (Var × PMode × Ty)} {d : Dep}
    (hd : d ∈ (envE c Ec te cs).vdeps) :
    (d = ⟨c, rootKind Ec.ty .self⟩ ∧ Ec.mode.isRoot = true) ∨ d ∈ Ec.vdeps := by
  rw [envE_vdeps] at hd
  rcases (mem_envE_deps hd).1 with hd | hd
  · unfold derive at hd
    cases hrt : Ec.mode.isRoot with
    | true =>
      simp only [hrt, ↓reduceIte, List.mem_singleton] at hd
      exact Or.inl ⟨hd, rfl⟩
    | false =>
      simp only [hrt, Bool.false_eq_true, ↓reduceIte, List.mem_map] at hd
      obtain ⟨d0, hd0, rfl⟩ := hd
      have hos : Ec.mode.ownSlot = false := by cases hm : Ec.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
      have hc : (⟨d0.root, comp d0.kind .self⟩ : Dep) = d0 := by obtain ⟨r0, k0⟩ := d0; cases k0 <;> rfl
      rw [hc]
      refine Or.inr ?_
      simp only [Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte]
      exact List.mem_append_left _ hd0
  · exact Or.inr (by unfold Entry.vdeps; exact List.mem_append_right _ hd)

/-- A root the opened environment depends on in memory: the package, or a
    root the package depends on in memory. -/
theorem envE_memRoots {c : Var} {Ec : Entry} {te : Ty} {cs : List (Var × PMode × Ty)} {r : Var}
    (hr : r ∈ roots (memDeps (envE c Ec te cs).vdeps)) : r = c ∨ r ∈ roots (memDeps Ec.vdeps) := by
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  obtain ⟨hd, hn⟩ := List.mem_filter.mp hd
  rcases envE_dep_vdeps hd with ⟨rfl, _⟩ | hd
  · exact Or.inl rfl
  · exact Or.inr (List.mem_map_of_mem (List.mem_filter.mpr ⟨hd, hn⟩))

/-- What the opened call's closures may change, the call through the package
    may: the environment holds what the package holds, the captures nothing. -/
theorem mutNames_open {Γ : Ctx} {e c : Var} {Ec : Entry} {te : Ty} {zs : List Var}
    {cs : List (Var × PMode × Ty)} (he : Γ e = none) (hc : Γ c = some Ec) (hnint : Ec.ty ≠ .int)
    (hzs : ∀ a ∈ zs, a ≠ e) (hcv : ∀ ci ∈ cs, ci.1 ≠ e ∧ (argE Γ ci.1).vdeps = []) :
    ∀ d ∈ mutNames (setE Γ e (envE c Ec te cs)) (e :: zs ++ cs.map (·.1)), d ∈ mutNames Γ (c :: zs) := by
  intro d hd
  have hae : argE Γ c = Ec := by unfold argE; rw [hc]; rfl
  have hΓe : ∀ a, a ≠ e → argE (setE Γ e (envE c Ec te cs)) a = argE Γ a := fun a ha => by
    unfold argE; simp [setE, upd_ne _ _ ha]
  unfold mutNames at hd ⊢
  obtain ⟨hd, hb⟩ := List.mem_filter.mp hd
  refine List.mem_filter.mpr ⟨?_, hb⟩
  simp only [argNames, List.mem_flatMap] at hd ⊢
  obtain ⟨a, ha, hda⟩ := hd
  simp only [List.cons_append, List.mem_cons, List.mem_append, List.mem_map] at ha
  rcases ha with rfl | ha | ⟨ci, hci, rfl⟩
  · -- the environment: what the package holds by name
    have hE : argE (setE Γ a (envE c Ec te cs)) a = envE c Ec te cs := by simp [argE, setE]
    rw [hE] at hda
    split at hda
    · cases hda
    · obtain ⟨hdv, hdn⟩ := List.mem_filter.mp hda
      refine ⟨c, List.mem_cons_self, ?_⟩
      rw [hae, ite_eq_right hnint]
      refine List.mem_filter.mpr ⟨?_, hdn⟩
      rcases envE_dep_vdeps hdv with ⟨rfl, _⟩ | hdv
      · exfalso; revert hdn; cases Ec.ty <;> simp [rootKind, Kind.isName]
      · exact hdv
  · rw [hΓe a (hzs a ha)] at hda
    exact ⟨a, List.mem_cons_of_mem _ ha, hda⟩
  · rw [hΓe _ (hcv ci hci).1] at hda
    split at hda
    · cases hda
    · rw [(hcv ci hci).2] at hda; cases hda

/-- Opening a package for a call: the environment bound to `e` as a borrowed
    parameter, and the call of the code on it, the arguments and the captures,
    well-typed. -/
theorem open_pkg {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec E : Entry} {ms : List Nat} {σ : Nat} {sig : Fn} {m : Mem}
    (hx : Γ x = none) (hc : Γ c = some Ec) (htc : Ec.ty = .fn ms)
    (hσ : P[σ]? = some sig) (hhd : sig.params.head? = some (.inp, .fn ms))
    (hcT : CallT P Γ F σ (c :: zs) E Γ1)
    (hnz : ∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z)
    (hi : Inv m Γ F (.callc x c j zs k))
    (hcl : ∀ v E, Γ v = some E → E.clean = E)
    {o : Bool} {fs : List Nat} {te : Ty} {env : Val} {cs : List (Var × PMode × Ty)}
    (hslot : m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩)
    {f : Nat} {fn : Fn} (hf : P[f]? = some fn)
    (hps : fn.params = (.inp, te) :: sig.params.tail ++ cs.map (·.2)) :
    MInv (envMem m env) (setE Γ m.nv (envE c Ec te cs)) ∧
    (∀ d ∈ (envE c Ec te cs).vdeps, d.kind.bound = .none →
      d.root ∈ heldN (setE Γ m.nv (envE c Ec te cs)) fn.params (m.nv :: zs ++ cs.map (·.1)) m.nv x) ∧
    CallT P (setE Γ m.nv (envE c Ec te cs))
      (F ++ heldN (setE Γ m.nv (envE c Ec te cs)) fn.params (m.nv :: zs ++ cs.map (·.1)) m.nv x) f
      (m.nv :: zs ++ cs.map (·.1))
      (callRes (setE Γ m.nv (envE c Ec te cs)) fn (m.nv :: zs ++ cs.map (·.1)))
      (callPost (setE Γ m.nv (envE c Ec te cs)) fn (m.nv :: zs ++ cs.map (·.1))) := by
  have hlc : Ec.live = true := callT_recv_live hcT hc
  have hcT0 := hcT
  obtain ⟨sig', hσ', hlen, hargs, hnf, hds, _, _⟩ := hcT
  rw [hσ] at hσ'; cases hσ'
  obtain ⟨rest, hsp⟩ : ∃ rest, sig.params = (.inp, .fn ms) :: rest := by
    cases h : sig.params with
    | nil => rw [h] at hhd; cases hhd
    | cons p0 rest => rw [h] at hhd; simp at hhd; exact ⟨rest, by rw [hhd]⟩
  rw [hsp] at hps; simp only [List.tail_cons] at hps
  have hzr : zs.length = rest.length := by rw [hsp] at hlen; simpa using hlen
  have hplen : fn.params.length = 1 + zs.length + cs.length := by rw [hps]; simp [hzr]; omega
  have hfn : FnOK P fn := hP fn (List.mem_of_getElem? hf)
  -- where things are
  have hlt : ∀ v E, Γ v = some E → v < m.nv := fun v E h => hi.nvSt v (by rw [← hi.dom, h]; rfl)
  have hΓe0 : Γ m.nv = none := by
    cases h : Γ m.nv with
    | none => rfl
    | some E0 => exact absurd (hlt _ _ h) (Nat.lt_irrefl _)
  have hxlt : x < m.nv := hi.nvS x (by simp [Stmt.vars])
  have hxe : x ≠ m.nv := fun e => by have := vlt hxlt; have := veq e; omega
  have hnint : Ec.ty ≠ .int := by rw [htc]; simp
  have hzlt : ∀ a ∈ zs, a < m.nv := fun a ha => hi.nvS a (by simp [Stmt.vars, ha])
  have hze : ∀ a ∈ zs, a ≠ m.nv := fun a ha e => by have := vlt (hzlt a ha); have := veq e; omega
  have hΓe : ∀ a, a ≠ m.nv → setE Γ m.nv (envE c Ec te cs) a = Γ a := fun a ha => by
    simp [setE, upd_ne _ _ ha]
  have hargE : ∀ a, a ≠ m.nv → argE (setE Γ m.nv (envE c Ec te cs)) a = argE Γ a := fun a ha => by
    unfold argE; rw [hΓe a ha]
  have hEe : argE (setE Γ m.nv (envE c Ec te cs)) m.nv = envE c Ec te cs := by simp [argE, setE]
  have hae : argE Γ c = Ec := by unfold argE; rw [hc]; rfl
  have hzs : ∀ i, i < zs.length → zs.getD i 0 ∈ zs := fun i h => by
    simp [List.getD, List.getElem?_eq_getElem h]
  -- the captures
  have hcap := fun ci (hci : ci ∈ cs) => pkg_cap hi.toMInv hc hlc htc hslot hci
  have hcroot : ∀ ci ∈ cs, ci.1 ∈ roots Ec.vdeps := fun ci hci =>
    held_vdeps (List.mem_map_of_mem (f := Dep.root) (pkg_cap_root hi.toMInv hc hlc hslot hci))
  have hkne : ∀ ci ∈ cs, ci.1 ≠ m.nv := fun ci hci e => by
    obtain ⟨Ev, hEv, _⟩ := hcap ci hci; rw [e, hΓe0] at hEv; cases hEv
  have hnd : (cs.map (·.1)).Nodup := (hi.pkgs c _ _ hslot rfl fs te ms env cs (Sub.refl _)).1
  have hck : ∀ k (hk : k < cs.length), (cs[k]'hk) ∈ cs := fun k hk => List.getElem_mem hk
  have hcapv : ∀ ci ∈ cs, (argE Γ ci.1).vdeps = [] := fun ci hci => by
    obtain ⟨Ev, hEv, _, _, _, _, hvd, _⟩ := hcap ci hci
    unfold argE; rw [hEv]; exact hvd
  -- a moving argument past the receiver is no capture of the package: a
  -- `sink` one is reached by nothing, an `inout` one is no binding the
  -- package may change
  have hzcap : ∀ i, i < zs.length → (sig.params[i + 1]?).map (·.1.moves) = some true →
      ∀ ci ∈ cs, zs.getD i 0 ≠ ci.1 := by
    intro i hiz hmv ci hci he
    have hil : i + 1 < sig.params.length := by rw [hsp]; simp; omega
    obtain ⟨_, _, _, _, hmva, _⟩ := hargs (i + 1) hil
    have hmv' : (sig.params[i + 1]).1.moves = true := by
      rw [List.getElem?_eq_getElem hil] at hmv; simpa using hmv
    obtain ⟨_, _, _, _, hdist⟩ := hmva hmv'
    obtain ⟨_, _, hns0, hnb0⟩ := hdist 0 (by rw [hsp]; simp) (by omega)
    simp only [List.getD_cons_zero, List.getD_cons_succ] at hns0 hnb0
    obtain ⟨Ev, _, _, _, _, _, _, _, hmd⟩ := hcap ci hci
    have hin := pkg_cap_root hi.toMInv hc hlc hslot hci
    have hinv : (⟨ci.1, .name ci.2.1.bound ci.2.2⟩ : Dep) ∈ (argE Γ c).vdeps := by
      rw [hae]; unfold Entry.vdeps; exact List.mem_append_right _ hin
    revert hmv' hns0 hnb0
    generalize sig.params[i + 1] = q
    obtain ⟨pm, t⟩ := q
    cases pm with
    | inp => intro h; cases h
    | sink => intro _ hns0 _; exact hns0 rfl (by rw [hae, he]; exact hcroot ci hci)
    | inout b =>
      intro _ _ hnb0
      rcases hmd with h | ⟨b', hb', hbn, _⟩
      · -- a read capture: reached from the receiver by a reader name, yet
        -- the argument, `inout`, is reached only by names of its bound
        have := hnb0 b rfl _ hinv he.symm
        rw [h] at this; simp only [Kind.bound, PMode.bound] at this
        exact this.2 this.1.symm
      · exact hnz _ (hzs i hiz) ⟨ci.1, .name ci.2.1.bound ci.2.2⟩
          (by unfold Entry.vdeps; exact List.mem_append_right _ hin)
          (by simp [Kind.bound, hb', PMode.bound, hbn]) he.symm
  -- the environment, valid through what the package depends on and holds
  -- but its own captures
  have hteok : te.ok = true := by
    obtain ⟨_, _, _, _, _, hpar, _⟩ := hfn
    exact (hpar (.inp, te) (by rw [hps]; simp)).1
  have hEw : ∀ r ∈ roots (envE c Ec te cs).vdeps, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
    intro r hr
    obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
    rw [envE_vdeps] at hd
    rcases (mem_envE_deps hd).1 with hd | hd
    · exact derive_roots hi.wf hc hlc (Or.inl hnint) .self d.root (List.mem_map_of_mem hd)
    · exact hi.wf c Ec hc hlc (Or.inl hnint) d.root (held_vdeps (List.mem_map_of_mem hd))
  have hpkE : PkgsOK env := (hi.pkgs c _ _ hslot rfl).sub (Sub.pkg (Sub.refl _))
  have hdis := (hi.pkgs c _ _ hslot rfl fs te ms env cs (Sub.refl _)).2.2
  have hnmE : NamesIn env (envDeps cs Ec.held) := fun c' hc' =>
    mem_envDeps.mpr ⟨hi.held c Ec _ _ hc hlc hslot rfl c'
      (by simp only [Val.names, List.mem_append]; exact Or.inr hc'), envNames_own hdis c' hc'⟩
  have hval0 : ValOK m te (lendOf env) (envE c Ec te cs).path (envE c Ec te cs).held := by
    rcases hi.mode_cases hc with hm | hm | hm
    · obtain ⟨T, hT, hw, hvs⟩ := hi.own_val hc hlc (by rw [hm]; rfl)
      rw [hslot] at hT; cases hT
      rw [htc] at hw hvs
      cases hw with
      | pkg hwe =>
        have hd : derive c Ec .self = [⟨c, .view⟩] := by simp [derive, hm, Mode.isRoot, htc, rootKind]
        have hvr : ViewsOK m te env (envDeps cs Ec.held) :=
          ViewsOK.mono (readers_sub_envDeps _ _) (ViewsOK.readers (fun s v hin => hvs s v (ViewIn.pkg hin)))
        have hsub : envDeps cs Ec.held ⊆ (envE c Ec te cs).path :=
          envDeps_mono (List.subset_append_right _ _)
        refine lend_valOK' hwe hpkE (fun t c' d es ht => ⟨⟨c, .view⟩, ?_, _,
          Or.inl ⟨_, hslot, Top.pkg ht⟩, Or.inr (Or.inl ⟨rfl, rfl⟩)⟩) hvr hnmE
          (fun s _ => ViewsOK.mono hsub hvr)
        simp [envE, hd, mem_envDeps, ownWriter, Kind.bound]
    · obtain ⟨v, hv, hok⟩ := hi.bor_val hc hlc (by rw [hm]; rfl)
      rw [hslot] at hv; cases hv
      rw [htc] at hok
      cases hok with
      | pkg hokE =>
        have hd : derive c Ec .self = [⟨c, .view⟩] := by simp [derive, hm, Mode.isRoot, htc, rootKind]
        rw [hokE.lend]
        exact valOK_via hslot hokE (Top.pkg (Top.refl _)) (by simp [envE, hd, mem_envDeps, ownWriter, Kind.bound])
    · obtain ⟨v, hv, hok⟩ := hi.bor_val hc hlc (by rw [hm]; rfl)
      rw [hslot] at hv; cases hv
      rw [htc] at hok
      cases hok with
      | pkg hokE =>
        rw [hokE.lend]
        refine hokE.onlyReaders (fun d hd hb => ?_)
        simp only [envE, derive_bor_self (show Ec.mode.isRoot = false by rw [hm]; rfl)]
        refine mem_envDeps_of_mem ?_ hb
        rcases List.mem_append.mp hd with hd | hd
        · exact List.mem_append_left _ hd
        · exact List.mem_append_right _ (envDeps_sub _ _ hd)
  let mn : Mem := { m with nv := m.nv + 1 }
  have hin : MInv mn Γ :=
    hi.toMInv.of_st rfl ⟨hi.heap.nodup, hi.heap.disj, hi.heap.alloc, hi.heap.self⟩ (Nat.le_succ _)
  have hval : ValOK mn te (lendOf env) (envE c Ec te cs).path (envE c Ec te cs).held := by
    have hk : ∀ dep : Dep, VKeep m mn dep ∧ HKeep m mn dep := fun dep => by
      have hr : RootKeep m mn dep.root := fun n hn => rootNode_st rfl hn
      exact ⟨hr.vkeep, hr.hkeep⟩
    exact hval0.keep (fun d _ => hk d) (fun d _ => hk d)
  have hnameE : NameOK (setE Γ m.nv (envE c Ec te cs)) (envE c Ec te cs) := by
    intro d hd b t hk
    have hdn : d ∈ nameDeps Ec.vdeps :=
      envE_names (List.mem_filter.mpr ⟨hd, by simp [hk, Kind.isName]⟩)
    obtain ⟨Er, hEr, hrest⟩ :=
      hi.names c Ec hc hlc (Or.inl hnint) d (List.mem_filter.mp hdn).1 b t hk
    have hne : d.root ≠ m.nv := fun e => by rw [e, hΓe0] at hEr; cases hEr
    exact ⟨Er, by rw [hΓe _ hne]; exact hEr, hrest⟩
  have hie : MInv (envMem m env) (setE Γ m.nv (envE c Ec te cs)) :=
    hin.addRootb hΓe0 (Nat.lt_succ_self _) rfl rfl hteok hval hEw
      (fun r hr => by obtain ⟨Er, hEr, _⟩ := hEw r hr; exact hlt r Er hEr)
      (NamesIn.lendOf hnmE) hpkE.lendOf hnameE
  -- the opened call's closures change what the call through the package may
  have hmo : ∀ d ∈ mutNames (setE Γ m.nv (envE c Ec te cs)) (m.nv :: zs ++ cs.map (·.1)),
      d ∈ mutNames Γ (c :: zs) :=
    mutNames_open hΓe0 hc hnint hze (fun ci hci => ⟨hkne ci hci, hcapv ci hci⟩)
  -- what the environment reads is held still for the call
  have hZ : ∀ d ∈ (envE c Ec te cs).vdeps, d.kind.bound = .none →
      d.root ∈ heldN (setE Γ m.nv (envE c Ec te cs)) fn.params (m.nv :: zs ++ cs.map (·.1)) m.nv x := by
    intro d hd hb
    have hr : d.root ∈ roots (envE c Ec te cs).vdeps := List.mem_map_of_mem hd
    obtain ⟨Er, hEr, _⟩ := hEw _ hr
    refine mem_heldN.mpr ⟨?_, fun hm => ?_⟩
    · simp only [heldFor, List.mem_filter, List.mem_range, Bool.and_eq_true, bne_iff_ne, ne_eq,
        Bool.not_eq_eq_eq_not, Bool.not_true, List.contains_eq_mem, decide_eq_false_iff_not]
      refine ⟨hlt _ Er hEr, ⟨(fun e => by rw [e, hx] at hEr; cases hEr), fun hm => ?_⟩⟩
      obtain ⟨i, p, hp, hpm, ha⟩ := mem_movedArgs hm
      have hil : i < 1 + zs.length + cs.length := by rw [← hplen]; exact (List.getElem?_eq_some_iff.mp hp).1
      rcases openArgs_cases hil with rfl | ⟨i, hiz, rfl⟩ | ⟨k, hk, rfl⟩
      · rw [hps] at hp; simp at hp; subst hp; exact hpm rfl
      · have hp' : sig.params[i + 1]? = some p := by
          rw [hsp]; rw [hps, openParams_z (by omega)] at hp; simpa using hp
        have hil' := (List.getElem?_eq_some_iff.mp hp').1
        obtain ⟨_, _, _, _, hmv, _⟩ := hargs (i + 1) hil'
        have hget : sig.params[i + 1] = p := (List.getElem?_eq_some_iff.mp hp').2
        have hmoves : sig.params[i + 1].1.moves = true := by
          rw [hget]; obtain ⟨pm, t⟩ := p; cases pm <;> simp_all [PMode.moves]
        obtain ⟨_, _, _, _, hdist⟩ := hmv hmoves
        obtain ⟨hne, hnr, hns, hnb⟩ := hdist 0 (by rw [hsp]; simp) (by omega)
        rw [openArgs_z _ _ hiz] at ha
        simp only [List.getD_cons_zero, List.getD_cons_succ] at hne hnr hns hnb
        rcases envE_dep_vdeps hd with ⟨rfl, _⟩ | hdv
        · exact hne ha
        · -- the environment's reader on the argument: the argument, moved,
          -- is reached by nothing (`sink`) or by names of its bound (`inout`)
          revert hmoves hns hnb
          rw [hget]; obtain ⟨pm, t⟩ := p
          cases pm with
          | inp => intro h; cases h
          | sink => intro _ hns _; exact hns rfl (by rw [hae, ← ha]; exact List.mem_map_of_mem hdv)
          | inout b =>
            intro _ _ hnb
            have := hnb b rfl d (by rw [hae]; exact hdv) ha
            exact this.2 (this.1 ▸ hb)
      · rw [openArgs_c _ _ hk] at ha
        rw [hps, show zs.length + 1 + k = rest.length + 1 + k by omega, openParams_c hk] at hp
        cases hp
        obtain ⟨Ev, _, _, _, _, _, _, _, hmd⟩ := hcap _ (hck k hk)
        rcases hmd with h | ⟨b, hb', hbn, _⟩
        · exact hpm h
        · exact envE_cap_out hi.toMInv hcT0 hnz hc hlc htc hslot (hck k hk) hb' hbn (ha ▸ hr)
    · -- a reader of a binding the call's closures change: reached only by
      -- names of the change's bound
      obtain ⟨dm, hdm, hdr⟩ := List.mem_map.mp hm
      have hdm' := hmo dm hdm
      obtain ⟨_, _, _, _, hoth⟩ := hnf dm hdm'
      have hbd : dm.kind.bound ≠ .none := by simpa using (List.mem_filter.mp hdm').2
      rcases envE_dep_vdeps hd with ⟨rfl, _⟩ | hdv
      · -- the package itself: a closure, not a `Vec` a closure changes
        obtain ⟨_, ⟨s, hts, _⟩, _⟩ := hnf dm hdm'
        have hdc : dm.root = c := hdr
        rw [hdc, hae, htc] at hts; cases hts
      · have := hoth c List.mem_cons_self (by rw [hae]; exact Or.inl hnint) d (by rw [hae]; exact hdv) hdr.symm
        exact hbd (this ▸ hb)
  refine ⟨hie, hZ, fn, hf, ?_, fun i hil => ?_, ?_, ?_, rfl, rfl⟩
  · simp [hplen]; omega
  rotate_left
  · -- what the opened call's closures may change is changed by it
    intro d hd
    have hd' := hmo d hd
    obtain ⟨hcan, hvec, hF, hna, hoth⟩ := hnf d hd'
    have hbd : d.kind.bound ≠ .none := by simpa using (List.mem_filter.mp hd').2
    have hdlt : d.root < m.nv := by
      cases hE : Γ d.root with
      | none =>
        exfalso; unfold argE at hcan; rw [hE] at hcan
        rcases hcan with hm | ⟨b, hm, _⟩ <;> simp [intE] at hm
      | some Er => exact hlt _ Er hE
    have hdne : d.root ≠ m.nv := fun e => by rw [e] at hdlt; exact Nat.lt_irrefl _ hdlt
    rw [hargE _ hdne]
    refine ⟨hcan, hvec, fun hm => ?_, ?_, fun a ha hty d' hd'' hdr => ?_⟩
    · rcases List.mem_append.mp hm with hm | hm
      · exact hF hm
      · exact (mem_heldN.mp hm).2 (List.mem_map_of_mem hd)
    · -- the binding changed: no argument, or an `inout` one of its bound
      by_cases hcs : ∃ k, ∃ hk : k < cs.length, (cs[k]'hk).1 = d.root
      · obtain ⟨k, hk, hkd⟩ := hcs
        obtain ⟨Ev, hEv, _, _, _, _, hvd, _, hmd⟩ := hcap _ (hck k hk)
        refine Or.inr ⟨zs.length + 1 + k, (cs[k]'hk).2.2, ?_, ?_⟩
        · have h1 : (m.nv :: zs ++ cs.map (·.1))[zs.length + 1 + k]? =
              some ((m.nv :: zs ++ cs.map (·.1)).getD (zs.length + 1 + k) 0) := by
            rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by simp; omega)]; rfl
          rw [h1, openArgs_c _ _ hk, hkd]
        · rw [hps, show zs.length + 1 + k = rest.length + 1 + k by omega, openParams_c hk]
          -- the change is the capture's own bound: the package holds its
          -- captures by their bound, and names on it agree
          show some ((cs[k]'hk).2.1, (cs[k]'hk).2.2) = _
          rcases hmd with h | ⟨b, hb, hbn, _⟩
          · -- a read capture is reached by no closure that changes it
            have hin := pkg_cap_root hi.toMInv hc hlc hslot (hck k hk)
            rw [h] at hin
            have := hoth c List.mem_cons_self (by rw [hae]; exact Or.inl hnint) ⟨(cs[k]'hk).1, .name .none (cs[k]'hk).2.2⟩
              (by rw [hae]; unfold Entry.vdeps; exact List.mem_append_right _ hin) hkd
            exact absurd this.symm hbd
          · have hin := pkg_cap_root hi.toMInv hc hlc hslot (hck k hk)
            rw [hb] at hin
            have := hoth c List.mem_cons_self (by rw [hae]; exact Or.inl hnint) ⟨(cs[k]'hk).1, .name b (cs[k]'hk).2.2⟩
              (by rw [hae]; unfold Entry.vdeps; exact List.mem_append_right _ hin) hkd
            have hbe : (cs[k]'hk).2.1 = PMode.inout d.kind.bound := by
              rw [hb]; exact congrArg PMode.inout this
            rw [hbe]
      · rcases hna with hna | ⟨i, t, hai, hpi⟩
        · left
          intro hm
          simp only [List.cons_append, List.mem_cons, List.mem_append, List.mem_map] at hm
          rcases hm with hm | hm | ⟨ci, hci, hcd⟩
          · exact hdne hm
          · exact hna (List.mem_cons_of_mem _ hm)
          · obtain ⟨k, hk, rfl⟩ := List.getElem_of_mem hci
            exact hcs ⟨k, hk, hcd⟩
        · -- an `inout` argument of the call through the package: of the
          -- opened call too, by the same parameter
          cases i with
          | zero => simp at hai; rw [← hai, hae, htc] at hvec; obtain ⟨_, h, _⟩ := hvec; cases h
          | succ i =>
            have hil' : i + 1 < sig.params.length := (List.getElem?_eq_some_iff.mp hpi).1
            have hiz : i < zs.length := by rw [hsp] at hil'; simp at hil'; omega
            refine Or.inr ⟨i + 1, t, ?_, ?_⟩
            · simp only [List.cons_append, List.getElem?_cons_succ] at hai ⊢
              rw [List.getElem?_append_left hiz]; exact hai
            · rw [hps, openParams_z (by omega), ← openParams_z (p0 := (.inp, .fn ms)) (cps := []) (by omega),
                List.append_nil, ← hsp]; exact hpi
    · -- every argument reaches it only by names of the change
      simp only [List.cons_append, List.mem_cons, List.mem_append, List.mem_map] at ha
      rcases ha with rfl | ha | ⟨ci, hci, rfl⟩
      · rw [hEe] at hd''
        rcases envE_dep_vdeps hd'' with ⟨rfl, _⟩ | hdv
        · obtain ⟨s, hts, _⟩ := hvec
          rw [← hdr, hae, htc] at hts; cases hts
        · exact hoth c List.mem_cons_self (by rw [hae]; exact Or.inl hnint) d' (by rw [hae]; exact hdv) hdr
      · rw [hargE a (hze a ha)] at hty hd''
        exact hoth a (List.mem_cons_of_mem _ ha) hty d' hd'' hdr
      · rw [hargE _ (hkne ci hci), hcapv ci hci] at hd''; cases hd''
  · -- A2-drop.2: what the opened call moves, changes and kills by name, the
    -- call through the package did; the environment runs no destructor
    have hlift : ∀ {e : Eff} {hv : Bool} {a : Var}, DtorSafe Γ e hv a →
        DtorSafe (setE Γ m.nv (envE c Ec te cs)) e hv a := by
      intro e hv a hs v E hv' hd hos
      by_cases hve : v = m.nv
      · subst hve; simp only [setE, upd_same, Option.some.injEq] at hv'; subst hv'
        simp [envE] at hd
      · rw [hΓe v hve] at hv'; exact hs v E hv' hd hos
    refine ⟨fun i hil => ?_, fun d hd => hlift (hds.2.1 d (hmo d hd)), fun i hil b hb Ea ha => sorry⟩
    have hil' := hil
    rw [hplen] at hil'
    rcases openArgs_cases hil' with rfl | ⟨j, hjz, rfl⟩ | ⟨k, hk, rfl⟩
    · have hp0 : fn.params[0] = (.inp, te) := by simp [hps]
      rw [hp0]; exact ⟨fun h => (by simp at h), fun b h => (by simp at h)⟩
    · have hjl : j + 1 < sig.params.length := by rw [hsp]; simp; omega
      have hpe : fn.params[j + 1]'hil = sig.params[j + 1] := by
        have h1 := openParams_z (p0 := (.inp, te)) (cps := cs.map (·.2)) (show j < rest.length by omega)
        rw [← hps] at h1
        have h2 : sig.params[j + 1]? = rest[j]? := by rw [hsp]; simp
        rw [← h2, List.getElem?_eq_getElem hil, List.getElem?_eq_getElem hjl] at h1
        exact Option.some.inj h1
      rw [hpe, openArgs_z _ _ hjz]
      obtain ⟨h1, h2⟩ := hds.1 (j + 1) hjl
      simp only [List.getD_cons_succ] at h1 h2
      exact ⟨fun hs => hlift (h1 hs), fun b hb => hlift (h2 b hb)⟩
    · have hpc : fn.params[zs.length + 1 + k]'hil = (cs[k]'hk).2 := by
        have h1 := openParams_c (p0 := (.inp, te)) (rest := rest) hk
        rw [← hps, show rest.length = zs.length by omega, List.getElem?_eq_getElem hil] at h1
        exact Option.some.inj h1
      rw [hpc, openArgs_c _ _ hk]
      obtain ⟨_, _, _, _, _, _, _, hhv, hmd⟩ := hcap _ (hck k hk)
      refine ⟨fun hs => ?_, fun b hb => ?_⟩
      · rcases hmd with h | ⟨b', h, _⟩ <;> rw [hs] at h <;> cases h
      · -- the package holds the capture by name, of the parameter's bound
        have hbn : b ≠ .none := by
          rcases hmd with h | ⟨b', h, hbn', _⟩
          · rw [hb] at h; cases h
          · rw [hb] at h; cases h; exact hbn'
        have hin := pkg_cap_root hi.toMInv hc hlc hslot (hck k hk)
        rw [hb] at hin
        have hmn : (⟨(cs[k]'hk).1, .name b (cs[k]'hk).2.2⟩ : Dep) ∈ mutNames Γ (c :: zs) := by
          simp only [mutNames, argNames, List.mem_filter, List.mem_flatMap, List.mem_cons]
          refine ⟨⟨c, Or.inl rfl, ?_⟩, by simp [Kind.bound, hbn]⟩
          rw [hae, ite_eq_right (fun h => hnint h)]
          simp only [nameDeps, List.mem_filter]
          exact ⟨by unfold Entry.vdeps; exact List.mem_append_right _ hin, rfl⟩
        rw [elem_holdsView, hhv]
        exact hlift (hds.2.1 _ hmn)
  -- each argument
  rw [hplen] at hil
  rcases openArgs_cases hil with rfl | ⟨i, hiz, rfl⟩ | ⟨k, hk, rfl⟩
  · -- the receiver: the environment, lent
    have hp0 : fn.params[0] = (.inp, te) := by simp [hps]
    refine ⟨envE c Ec te cs, by simp [setE], rfl, ?_, fun hmv => ?_, fun hs => ?_⟩
    · rw [hp0]; rfl
    · rw [hp0] at hmv; cases hmv
    · rw [hp0] at hs; rcases hs with h | h <;> cases h
  · -- an argument of the call through the package
    have hil' : i + 1 < sig.params.length := by rw [hsp]; simp; omega
    obtain ⟨Ea, hEa, hla, hpa, hmva, hpin⟩ := hargs (i + 1) hil'
    have hpe : fn.params[i + 1]'(by rw [hplen]; omega) = sig.params[i + 1] := by
      have h1 := openParams_z (p0 := (.inp, te)) (cps := cs.map (·.2)) (show i < rest.length by omega)
      rw [← hps] at h1
      have h2 : sig.params[i + 1]? = rest[i]? := by rw [hsp]; simp
      rw [← h2, List.getElem?_eq_getElem (by rw [hplen]; omega),
        List.getElem?_eq_getElem hil'] at h1
      exact Option.some.inj h1
    simp only [List.getD_cons_succ] at hEa hmva hpin
    rw [openArgs_z _ _ hiz]
    have hz := hzs i hiz
    have haez : argE Γ (zs.getD i 0) = Ea := by unfold argE; rw [hEa]; rfl
    refine ⟨Ea, by rw [hΓe _ (hze _ hz)]; exact hEa, hla, by rw [hpe]; exact hpa, fun hmv => ?_,
      fun hs => ?_⟩
    · rw [hpe] at hmv
      obtain ⟨hnF, hnr, hns, hself, hdist⟩ := hmva hmv
      have hnm : (sig.params[i + 1]).1 ≠ .inp := fun h => by rw [h] at hmv; cases hmv
      have hmoved : zs.getD i 0 ∈ movedArgs fn.params (m.nv :: zs ++ cs.map (·.1)) := by
        have := mem_movedArgs_of (args := m.nv :: zs ++ cs.map (·.1)) (i := i + 1)
          (by rw [List.getElem?_eq_getElem (by rw [hplen]; omega), hpe]) hnm
        rwa [openArgs_z _ _ hiz] at this
      have hzc : ∀ ci ∈ cs, zs.getD i 0 ≠ ci.1 :=
        hzcap i hiz (by rw [List.getElem?_eq_getElem hil']; simpa using hmv)
      refine ⟨fun h => ?_, hnr, fun hs => hns (by rw [← hpe]; exact hs), fun b hb => hself b (by rw [← hpe]; exact hb),
        fun j hj hji => ?_⟩
      · rcases List.mem_append.mp h with h | h
        · exact hnF h
        · have := (mem_heldN.mp h).1
          simp only [heldFor, List.mem_filter, List.contains_eq_mem, hmoved, decide_true,
            Bool.not_true, Bool.and_false, Bool.false_eq_true, and_false] at this
      · rw [hplen] at hj
        rcases openArgs_cases hj with rfl | ⟨j, hjz, rfl⟩ | ⟨k, hk, rfl⟩
        · -- the environment: what the package reaches the argument by
          obtain ⟨hne, hnr0, hns0, hnb0⟩ := hdist 0 (by rw [hsp]; simp) (by omega)
          simp only [List.getD_cons_zero] at hne hnr0 hns0 hnb0 ⊢
          rw [openArgs_zero, hEe]
          refine ⟨fun e => hze _ hz e.symm, fun hr => ?_, fun hs hr => ?_, fun b hb d hd hdr => ?_⟩
          · rcases envE_memRoots hr with h | h
            · exact hne h.symm
            · exact hnr0 (by rw [hae]; exact h)
          · rcases envE_roots hr with h | h
            · exact hne h.symm
            · exact hns0 (by rw [← hpe]; exact hs) (by rw [hae]; exact h)
          · rcases envE_dep_vdeps hd with ⟨rfl, _⟩ | hdv
            · exact absurd hdr hne
            · exact hnb0 b (by rw [← hpe]; exact hb) d (by rw [hae]; exact hdv) hdr
        · obtain ⟨hne, hnr0, hns0, hnb0⟩ := hdist (j + 1) (by rw [hsp]; simp; omega) (by omega)
          simp only [List.getD_cons_succ] at hne hnr0 hns0 hnb0
          rw [openArgs_z _ _ hjz, hargE _ (hze _ (hzs j hjz))]
          exact ⟨hne, hnr0, fun hs => hns0 (by rw [← hpe]; exact hs), fun b hb => hnb0 b (by rw [← hpe]; exact hb)⟩
        · -- a capture: no moving argument, and it depends on nothing
          rw [openArgs_c _ _ hk, hargE _ (hkne _ (hck k hk)), hcapv _ (hck k hk)]
          exact ⟨fun e => hzc _ (hck k hk) e.symm, by simp [roots, memDeps], fun _ => by simp [roots],
            fun _ _ d hd => by cases hd⟩
    · rw [hpe] at hs
      intro p Ep hp hm d hd hb
      by_cases hpe' : p = m.nv
      · subst hpe'; simp only [setE, upd_same, Option.some.injEq] at hp; subst hp
        -- the environment names the argument moved by nothing: a `sink` one
        -- is reached by nothing, one replaced by no name (none replaces)
        intro hdr
        have hmoves : sig.params[i + 1].1.moves = true := by
          rcases hs with h' | h' <;> rw [h'] <;> rfl
        obtain ⟨_, _, _, _, hdist⟩ := hmva hmoves
        obtain ⟨hne0, _, hns0, hnb0⟩ := hdist 0 (by rw [hsp]; simp) (by omega)
        simp only [List.getD_cons_zero] at hne0 hns0 hnb0
        rcases envE_dep_vdeps hd with ⟨rfl, _⟩ | hdv
        · exact hne0 hdr
        · rcases hs with hs | hs
          · exact hns0 hs (by rw [hae, ← hdr]; exact List.mem_map_of_mem hdv)
          · have := hnb0 .replace hs d (by rw [hae]; exact hdv) hdr
            obtain ⟨r, kk⟩ := d
            cases kk with
            | name b' t' =>
              obtain ⟨_, _, _, _, _, _, hcb, _⟩ := hi.names c Ec hc hlc (Or.inl hnint) _ hdv b' t' rfl
              simp only [Kind.bound] at this hb
              rcases hcb with h' | ⟨h', _⟩
              · exact hb h'
              · exact h' this.1
            | _ => exact hb rfl
      · rw [hΓe _ hpe'] at hp; exact hpin hs p Ep hp hm d hd hb
  · -- a capture
    have hci := hck k hk
    obtain ⟨Ev, hEv, hlv, hhv, htv, hmo', hvd, hvf, hmd⟩ := hcap _ hci
    have hpk : fn.params[zs.length + 1 + k]? = some (cs[k]'hk).2 := by
      rw [hps, show zs.length + 1 + k = rest.length + 1 + k by omega, openParams_c hk]
    have hpk' : fn.params[zs.length + 1 + k]'(by rw [hplen]; omega) = (cs[k]'hk).2 :=
      Option.some.inj (by rw [← List.getElem?_eq_getElem]; exact hpk)
    rw [openArgs_c _ _ hk, hpk']
    refine ⟨Ev, by rw [hΓe _ (hkne _ hci)]; exact hEv, hlv, ?_, fun hmv => ?_, fun hs => ?_⟩
    · -- of the recorded type; one it may change is a `Vec` it may change within its bound
      rcases hmd with h | ⟨b, hb, _, _, hcan⟩
      · rw [h]; exact htv
      · rw [hb]
        obtain ⟨_, _, _, _, _, hpar, _⟩ := hfn
        obtain ⟨_, _, hvec⟩ := hpar ((cs[k]'hk).2) (List.mem_of_getElem? hpk)
        exact ⟨htv, hcan, hvec b hb⟩
    · rcases hmd with h | ⟨b, hb, hbn, _, _⟩
      · rw [h] at hmv; cases hmv
      obtain ⟨hF, hA, hx⟩ := pkg_cap_mut hi.toMInv hcT0 hnz hc hlc htc hslot hci hb hbn
      have hmoved : (cs[k]'hk).1 ∈ movedArgs fn.params (m.nv :: zs ++ cs.map (·.1)) := by
        have := mem_movedArgs_of (args := m.nv :: zs ++ cs.map (·.1)) hpk (by rw [hb]; simp)
        rwa [openArgs_c _ _ hk] at this
      refine ⟨fun h => ?_, (by rw [hvd]; simp [roots, memDeps]), fun hs => (by rw [hb] at hs; cases hs),
        fun _ _ d hd => (by rw [hvd] at hd; cases hd), fun j hj hji => ?_⟩
      · rcases List.mem_append.mp h with h | h
        · exact hF h
        · have := (mem_heldN.mp h).1
          simp only [heldFor, List.mem_filter, List.contains_eq_mem, hmoved, decide_true,
            Bool.not_true, Bool.and_false, Bool.false_eq_true, and_false] at this
      · rw [hplen] at hj
        rcases openArgs_cases hj with rfl | ⟨j, hjz, rfl⟩ | ⟨k', hk', rfl⟩
        · simp only [openArgs_zero]
          have hout := envE_cap_out hi.toMInv hcT0 hnz hc hlc htc hslot hci hb hbn
          rw [hEe]
          exact ⟨fun e => hkne _ hci e.symm,
            fun hr => hout (List.map_subset _ (fun d hd => (List.mem_filter.mp hd).1) hr),
            fun _ => hout, fun _ _ d hd hdr => absurd (hdr ▸ List.mem_map_of_mem hd) hout⟩
        · rw [openArgs_z _ _ hjz]
          have hz := hzs j hjz
          rw [hargE _ (hze _ hz)]
          have hmem : ∀ d ∈ (argE Γ (zs.getD j 0)).vdeps, d.root = (cs[k]'hk).1 → d.kind.bound = b := by
            intro d hd hdr
            by_cases hti : (argE Γ (zs.getD j 0)).ty ≠ .int ∨ (argE Γ (zs.getD j 0)).mode = .rootb
            · exact hx _ (List.mem_cons_of_mem _ hz) hti d hd hdr
            · simp only [not_or, Classical.not_not] at hti
              -- an integer that is no borrowed parameter depends on nothing, once cleaned
              unfold argE at hd hti
              cases hz' : Γ (zs.getD j 0) with
              | none => rw [hz'] at hd; simp [intE, Entry.vdeps, Mode.ownSlot] at hd
              | some Ez =>
                rw [hz'] at hd hti; simp only [Option.getD_some] at hd hti
                have hcz := hcl _ _ hz'
                unfold Entry.clean at hcz
                rw [ite_eq_left ⟨fun hf => by
                    rcases hf with h | ⟨b', h, _⟩
                    · exact hti.2 h
                    · exact hi.noInout _ _ b' hz' h, Or.inl hti.1⟩] at hcz
                rw [← hcz] at hd; simp [Entry.vdeps, hti.1] at hd
          refine ⟨fun e => hA (List.mem_cons_of_mem _ (e ▸ hz)), fun hr => ?_, fun hs => (by rw [hb] at hs; cases hs),
            fun b' hb' d hd hdr => ?_⟩
          · obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
            obtain ⟨hd, hn⟩ := List.mem_filter.mp hd
            have := hmem d hd hdr
            rw [RSetup.isName_of_bound (by rw [this]; exact hbn)] at hn; cases hn
          · rw [hb] at hb'; cases hb'
            exact ⟨hmem d hd hdr, hbn⟩
        · rw [openArgs_c _ _ hk']
          have hkk : k' ≠ k := fun e => hji (by rw [e])
          rw [hargE _ (hkne _ (hck k' hk')), hcapv _ (hck k' hk')]
          refine ⟨fun e => hkk ?_, by simp [roots, memDeps], fun _ => by simp [roots], fun _ _ d hd => by cases hd⟩
          exact (hnd.getElem_inj (hi := by simpa using hk') (hj := by simpa using hk)).mp (by simpa using e)
    · rcases hmd with h | ⟨b, hb, _, hbr, _⟩
      · rw [h] at hs; rcases hs with h | h <;> cases h
      · rw [hb] at hs; rcases hs with h | h
        · cases h
        · exact absurd (PMode.inout.inj h) hbr

theorem cloProgress {P : Prog} (hP : ProgOK P) {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat}
    {zs : List Var} {k : Stmt} {Ec E : Entry} {ms : List Nat} {σ : Nat} {sig : Fn} {m : Mem}
    (hx : Γ x = none) (hc : Γ c = some Ec) (htc : Ec.ty = .fn ms) (hj : ms[j]? = some σ)
    (hσ : P[σ]? = some sig) (hhd : sig.params.head? = some (.inp, .fn ms))
    (hcT : CallT P Γ F σ (c :: zs) E Γ1)
    (hnz : ∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) (hcd : MemCodes P m)
    (hi : Inv m Γ F (.callc x c j zs k)) :
    ∃ s, Step P m (.callc x c j zs k) s := by
  have hlc := callT_recv_live hcT hc
  obtain ⟨o, fs, te, env, cs, hslot⟩ := pkg_slot hi.toMInv hc hlc htc
  obtain ⟨f, fn, hfs, hf, hps, _⟩ := pkg_code hcd hslot hj hσ
  have hnint : Ec.ty ≠ .int := by rw [htc]; simp
  have hcc : cleanC Γ c = some Ec := by rw [cleanC_of hc, clean_id (Or.inl hnint) hlc]
  obtain ⟨hie, _, hcT'⟩ := open_pkg hP (cleanC_none.mpr hx) hcc htc hσ hhd (hcT.clean hσ) hnz
    hi.clean cleanC_clean hslot hf hps
  have hxlt : x < m.nv := hi.nvS x (by simp [Stmt.vars])
  have hxe : x ≠ m.nv := fun e => by have := vlt hxlt; have := veq e; omega
  have hx' : setE (cleanC Γ) m.nv (envE c Ec te cs) x = none := by
    simp [setE, upd_ne _ _ hxe, cleanC_none.mpr hx]
  obtain ⟨r, hs⟩ := callProgress (k := k) hx' hcT' hie
  cases hs with
  | letcall hf' hmx hb =>
    rw [hf] at hf'; cases hf'
    exact ⟨_, Step.callc hslot hfs hf (by simpa [envMem, Mem.set, upd_ne _ _ hxe] using hmx) hb⟩

theorem cloCase {P : Prog} (hP : ProgOK P) : CloCase P := by
  intro Γ Γ1 F x c j zs k Ec E ms σ sig Δ m m' s' hk hx hxF hc htc hj hσ hhd hnz hcT hnzs hkT hpx hcd hi hst
  cases hst with
  | callc hslot hfs hf hmx hb =>
    rename_i m1 o fs te ms' env cs f fn
    obtain ⟨_, _, _, _, _, hslot'⟩ := pkg_slot hi.toMInv hc (callT_recv_live hcT hc) htc
    rw [hslot] at hslot'; cases hslot'
    -- the code, implementing the method's interface
    obtain ⟨f', fn', hfs', hf', hps0, hty, hown, hl, hr, ho⟩ := pkg_code hcd hslot hj hσ
    rw [hfs] at hfs'; cases hfs'; rw [hf] at hf'; cases hf'
    obtain ⟨rest, hsp⟩ : ∃ rest, sig.params = (.inp, .fn ms) :: rest := by
      cases h : sig.params with
      | nil => rw [h] at hhd; cases hhd
      | cons p0 rest => rw [h] at hhd; simp at hhd; exact ⟨rest, by rw [hhd]⟩
    have hps : fn.params = (.inp, te) :: rest ++ cs.map (·.2) := by rw [hps0, hsp]; rfl
    have hlc := callT_recv_live hcT hc
    have hnint : Ec.ty ≠ .int := by rw [htc]; simp
    obtain ⟨_, _, _, _, _, _, hlends, hrholds, _, _⟩ := hP fn (List.mem_of_getElem? hf)
    obtain ⟨_, _, _, _, _, _, hslends, hsrholds, hsouts, _⟩ := hP sig (List.mem_of_getElem? hσ)
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
    have hcap := fun ci (hci : ci ∈ cs) => pkg_cap hi.toMInv hc hlc htc hslot hci
    have hAlt : ∀ a ∈ zs ++ cs.map (·.1), a < m.nv := by
      intro a ha
      rcases List.mem_append.mp ha with ha | ha
      · exact hzlt a ha
      · obtain ⟨ci, hci, hca⟩ := List.mem_map.mp ha
        obtain ⟨Ev, hEv, _⟩ := hcap ci hci
        rw [← hca]; exact hlt _ _ hEv
    have hgetD : ∀ l : List Var, (∀ a ∈ l, a < m.nv) → ∀ k, l.getD k 0 ≠ m.nv := by
      intro l hl' k' he
      by_cases hk' : k' < l.length
      · have hm : l.getD k' 0 ∈ l := by
          rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk', Option.getD_some]
          exact List.getElem_mem hk'
        have := hl' _ hm
        rw [he] at this; exact Nat.lt_irrefl _ this
      · rw [List.getD_eq_getElem?_getD, List.getElem?_eq_none (by omega)] at he
        simp at he; rw [← he] at hclt; exact Nat.not_lt_zero _ hclt
    have hzs := hgetD zs hzlt
    have hAs := hgetD _ hAlt
    have hFe : m.nv ∉ F := fun h => by have := vlt (hi.nvF _ h); omega
    let H0 := heldFor fn.params (m.nv :: zs ++ cs.map (·.1)) m.nv x
    -- the package opened, in the cleaned context
    have hic := hi.clean
    have hcc : cleanC Γ c = some Ec := by rw [cleanC_of hc, clean_id (Or.inl hnint) hlc]
    have hxc : cleanC Γ x = none := cleanC_none.mpr hx
    obtain ⟨hie, hZ, hcT'⟩ := open_pkg hP hxc hcc htc hσ hhd (hcT.clean hσ) hnzs hic
      cleanC_clean hslot hf hps0
    let Ee := envE c Ec te cs
    let Γe := setE (cleanC Γ) m.nv Ee
    -- what the typing lends: what the run-time form holds still, but what
    -- the call's closures may change
    let H := heldN Γe fn.params (m.nv :: zs ++ cs.map (·.1)) m.nv x
    have hHH : ∀ v ∈ H, v ∈ H0 := fun v hv => heldN_sub _ _ _ _ _ hv
    have hH0lt : ∀ v ∈ H0, v < m.nv := fun v hv => List.mem_range.mp (List.mem_filter.mp hv).1
    have hHlt : ∀ v ∈ H, v < m.nv := fun v hv => hH0lt v (hHH v hv)
    have hHe : m.nv ∉ H := fun h => Nat.lt_irrefl _ (hHlt _ h)
    have hxH : x ∉ H := fun h => by have := hHH _ h; simp [H0, heldFor] at this
    have hxF' : x ∉ F ++ H := fun h => (List.mem_append.mp h).elim hxF hxH
    have hFe' : m.nv ∉ F ++ H := fun h => (List.mem_append.mp h).elim hFe hHe
    have hEe : Γe m.nv = some Ee := by simp [Γe, setE]
    have hxe' : Γe x = none := by simp [Γe, setE, upd_ne _ _ hxe, hxc]
    have hIe : Inv (envMem m env) Γe (F ++ H) (.letcall x f (m.nv :: zs ++ cs.map (·.1)) k) :=
      { toMInv := hie
        nvS := by
          intro v hv
          show v < m.nv + 1
          simp only [Stmt.vars] at hv
          rcases List.mem_cons.mp hv with rfl | hv
          · exact Nat.lt_succ_of_lt hxlt
          rcases List.mem_append.mp hv with hv | hv
          · rcases List.mem_cons.mp hv with rfl | hv
            · exact Nat.lt_succ_self _
            · exact Nat.lt_succ_of_lt (hAlt v hv)
          · exact Nat.lt_succ_of_lt (hi.nvS v (by simp [Stmt.vars, hv]))
        nvF := fun v hv => by
          show v < m.nv + 1
          rcases List.mem_append.mp hv with hv | hv
          · exact Nat.lt_succ_of_lt (hi.nvF v hv)
          · exact Nat.lt_succ_of_lt (hHlt v hv)
        anch := fun p E hp hm _ => by
          by_cases hpe : p = m.nv
          · subst hpe; simp only [Γe, setE, upd_same, Option.some.injEq] at hp; subst hp
            exact fun d hd hb => List.mem_append_right _ (hZ d hd hb)
          · simp only [Γe, setE, upd_ne _ _ hpe] at hp
            exact fun d hd hb' => List.mem_append_left _ (hic.anch p E hp hm (by simp [Stmt.spine]) d hd hb')
        spineNd := by simp [Stmt.spine]
        spineDom := by simp [Stmt.spine]
        catchOK := catchOK_src (by simp [Stmt.src, hk])
        cover := fun i hia => by
          obtain ⟨o', T, hT, hiT⟩ := hi.cover i hia
          have ho : o' ≠ m.nv := fun e => by
            subst e; unfold OwnedAt at hT
            have := hi.dom m.nv; rw [hΓe0, hT] at this; cases this
          exact ⟨o', T, by unfold OwnedAt at hT ⊢; simp [envMem, Mem.set, upd_ne _ _ ho, hT], hiT⟩
        pinOut := pinOut_nil rfl
        pinIn := trivial
        dtorOut := dtorOut_nil rfl
        dtorIn := trivial }
    have h := callH_of hP hf hxe' hxF' hcT' hIe
    have hI := h.inv hIe hb
    -- the environment's binding, where the call leaves it
    have hρ : ∀ v, callRen fn.params (m.nv :: zs ++ cs.map (·.1)) (envMem m env).nv v ≠ m.nv := by
      intro v hv
      obtain ⟨b, t, hvp, hva⟩ := h.ren_dom hv (by show m.nv < m.nv + 1; omega)
      cases v with
      | zero => rw [hps] at hvp; cases hvp
      | succ v => simp only [List.cons_append, List.getD_cons_succ] at hva; exact hAs v hva
    have hΓ'e : (callS Γe (F ++ H) fn (m.nv :: zs ++ cs.map (·.1)) (envMem m env).nv x).canon
        (sigCtx fn) m.nv = some Ee := by
      rw [RSetup.canon_frame _ hρ, h.frame_of hρ hxe.symm, h.post_rootb hEe rfl]
      simp [Ee, envE, Entry.clean]
    -- the static context after the call
    obtain ⟨sig', hσ', hlen, hargs, hnf, hds, rfl, rfl⟩ := hcT
    rw [hσ] at hσ'; cases hσ'
    have hcT0 : CallT P Γ F σ (c :: zs) (callRes Γ sig (c :: zs)) (callPost Γ sig (c :: zs)) :=
      ⟨sig, hσ, hlen, hargs, hnf, hds, rfl, rfl⟩
    obtain ⟨hw1, hdm, hE⟩ := hcT0.wf hP hi.wf
    obtain ⟨hn1, hEn, _⟩ := hcT0.names hP hi.names
    have hx1 : callPost Γ sig (c :: zs) x = none := by
      have := hdm.1 x; rw [hx] at this; cases h' : callPost Γ sig (c :: zs) x <;> simp_all
    have hse : callPost Γ sig (c :: zs) m.nv = none := by
      have := hdm.1 m.nv; rw [hΓe0] at this; cases h' : callPost Γ sig (c :: zs) m.nv <;> simp_all
    have hzr : zs.length = rest.length := by rw [hsp] at hlen; simpa using hlen
    have hsl : sig.params.length = zs.length + 1 := by rw [hsp]; simp [hzr]
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
    -- A2-drop.2: an `inout` argument of the call is no binding `letd` made
    have hio : ∀ p a, (p, a) ∈ rest.zip zs → ∀ b, p.1 = .inout b → (argE Γ a).dbind = false := by
      intro p a hpa b hpb
      obtain ⟨i, hi1, hi2, he⟩ := RSetup.mem_zip_getD hpa
      simp only [Prod.mk.injEq] at he; obtain ⟨rfl, rfl⟩ := he
      have hil : i + 1 < sig.params.length := by rw [hsp]; simp; omega
      have hp : sig.params[i + 1]'hil = rest[i]'hi1 := by simp [hsp]
      unfold argE
      cases hza : Γ (zs.getD i 0) with
      | none => rfl
      | some Ea => exact hds.2.2 (i + 1) hil b (by rw [hp]; exact hpb) Ea (by simpa using hza)
    -- the names the call through the package may change reach no borrowed parameter
    have hae : argE Γ c = Ec := by unfold argE; rw [hc]; rfl
    have hMr : ∀ v E0, Γ v = some E0 → E0.mode = .rootb →
        ∀ d ∈ mutNames Γ (c :: zs), hits d.kind.bound false d.root E0 = false := by
      intro v E0 hv hrbv d hd
      obtain ⟨_, _, hF, _, _⟩ := hnf d hd
      have hanch := hi.anch v E0 hv hrbv (by simp [Stmt.spine])
      obtain ⟨hdn, hbd⟩ := List.mem_filter.mp hd
      have hb' : d.kind.bound ≠ .none := by simpa using hbd
      have hbr : d.kind.bound ≠ .replace := by
        simp only [argNames, List.mem_flatMap] at hdn
        obtain ⟨a, ha, hda⟩ := hdn
        split at hda
        · simp at hda
        · rename_i hnt
          have hdv := (List.mem_filter.mp hda).1
          rcases List.mem_cons.mp ha with rfl | ha
          · rw [hae] at hdv
            obtain ⟨r, kk⟩ := d
            cases kk with
            | name b t =>
              obtain ⟨_, _, _, _, _, _, hcb, _⟩ := hi.names _ Ec hc hlc (Or.inl hnint) _ hdv b t rfl
              rcases hcb with h' | ⟨h', _⟩
              · exact absurd h' hb'
              · exact h'
            | _ => exact absurd rfl hb'
          · obtain ⟨i, hiz, rfl⟩ := mem_args ha
            have hil : i + 1 < sig.params.length := by rw [hsl]; omega
            obtain ⟨Ea, hEa, hla, _⟩ := hargs (i + 1) hil
            simp only [List.getD_cons_succ] at hEa
            have hae' : argE Γ (zs.getD i 0) = Ea := by unfold argE; rw [hEa]; rfl
            rw [hae'] at hdv hnt
            obtain ⟨r, kk⟩ := d
            cases kk with
            | name b t =>
              obtain ⟨_, _, _, _, _, _, hcb, _⟩ := hi.names _ Ea hEa hla (Or.inl hnt) _ hdv b t rfl
              rcases hcb with h' | ⟨h', _⟩
              · exact absurd h' hb'
              · exact h'
            | _ => exact absurd rfl hb'
      exact RSetup.hits_false_of (fun d' hd' hr' => by
        by_cases hb0 : d'.kind.bound = .none
        · exact absurd (hr' ▸ hanch d' hd' hb0) hF
        · exact RSetup.kills_isName hbr _ (RSetup.isName_of_bound hb0))
    have hcapW : ∀ ci ∈ cs, ∃ Ev, Γ ci.1 = some Ev ∧ Ev.vdeps = [] ∧ Ev.mode = .own ∧
        ci.2.2.holdsView = false ∧ (ci.2.1 = .inp ∨ ∃ b, ci.2.1 = .inout b ∧ ci.1 ∉ zs ∧
          (⟨ci.1, .name b ci.2.2⟩ : Dep) ∈ mutNames Γ (c :: zs)) := by
      intro ci hci
      obtain ⟨Ev, hEv, _, _, _, hmo, hvd, hvf, hmd⟩ := hcap ci hci
      refine ⟨Ev, hEv, hvd, hmo, hvf, ?_⟩
      rcases hmd with h' | ⟨b, hb', hbn, _, _⟩
      · exact Or.inl h'
      · obtain ⟨_, hA, _⟩ := pkg_cap_mut hi.toMInv hcT0 hnzs hc hlc htc hslot hci hb' hbn
        exact Or.inr ⟨b, hb', fun h' => hA (List.mem_cons_of_mem _ h'),
          pkg_cap_mutName hi.toMInv hc hlc htc hslot hci hb' hbn zs⟩
    have hbl : ∀ jk ∈ sig.lends, jk.1 < zs.length + 1 := fun jk h' => by
      obtain ⟨⟨hj', _⟩, _⟩ := hslends jk h'; rw [hsl] at hj'; exact hj'
    have hbr : ∀ jk ∈ sig.rholds, jk.1 < zs.length + 1 := fun jk h' => by
      obtain ⟨⟨hj', _⟩, _⟩ := hsrholds jk h'; rw [hsl] at hj'; exact hj'
    have hbo : ∀ o ∈ sig.outHolds, o.2.1 < zs.length + 1 := fun o h' => by
      obtain ⟨⟨hj', _⟩, _⟩ := hsouts o h'; rw [hsl] at hj'; exact hj'
    have hwf := hw1.add hx1 (fun _ _ => recvRes_roots hi.wf hdm hc hlc hnint hE)
    have hnf' := NameWF.setE hn1 (fun Ex h' => by rw [hx1] at h'; cases h')
      (fun Ex h' => by rw [hx1] at h'; cases h') (recvRes_named (c := c) (Ec := Ec) hEn)
    -- what the opened call's closures may change, the call through the
    -- package may
    have hMc : ∀ d ∈ mutNames Γe (m.nv :: zs ++ cs.map (·.1)), d ∈ mutNames Γ (c :: zs) := by
      intro d hd
      refine mutNames_clean Γ (c :: zs) (mutNames_open (cleanC_none.mpr hΓe0) hcc hnint
        (fun a ha e => by have := vlt (hzlt a ha); have := veq e; omega) (fun ci hci => ⟨?_, ?_⟩) d hd)
      · obtain ⟨Ev, hEv, _⟩ := hcap ci hci
        exact fun e => by rw [e, hΓe0] at hEv; cases hEv
      · obtain ⟨Ev, hEv, _, _, _, _, hvd, _⟩ := hcap ci hci
        rw [argE_clean]
        have hae' : argE Γ ci.1 = Ev := by unfold argE; rw [hEv]; rfl
        rw [hae']
        exact List.eq_nil_of_subset_nil (hvd ▸ clean_vdeps_sub Ev)
    have hW := weaker_open (x := x) (te := te) (cs := cs) hi.wf hi.rootbLive hi.noInout hΓe0 hzs hc hlc
      hnint hxe hps hsp hzr hty hown hl hr ho (fun jk h' => (hlends jk h').2) (fun jk h' => (hrholds jk h').2)
      hnz hbl hbr hbo hrb hio hcapW hMr hMc hse hwf hnf'
    -- the residual, typed
    have hIn := h.typedIn
    have hrbT := StmtT.rbind (P := P) hΓ'e rfl rfl
      (fun d hd hb => List.mem_append_right _ (hZ d hd hb)) hFe' hIn
      (fun d hd hb => by
        -- what the environment may change by name is a binding of the
        -- caller's, a root still after the call
        have hr : d.root ∈ roots Ee.vdeps := List.mem_map_of_mem hd
        obtain ⟨Er, hEr, hro⟩ : ∃ Er, Γ d.root = some Er ∧ Er.mode.isRoot = true := by
          obtain ⟨d', hd', hdd⟩ := List.mem_map.mp hr
          rw [← hdd]
          simp only [Ee] at hd'; rw [envE_vdeps] at hd'
          rcases (mem_envE_deps hd').1 with hd' | hd'
          · exact derive_roots hi.wf hc hlc (Or.inl hnint) .self d'.root (List.mem_map_of_mem hd')
          · exact hi.wf c Ec hc hlc (Or.inl hnint) d'.root (held_vdeps (List.mem_map_of_mem hd'))
        have hne : d.root ≠ m.nv := fun e => by rw [e, hΓe0] at hEr; cases hEr
        have hnx : d.root ≠ x := fun e => by rw [e, hx] at hEr; cases hEr
        refine ⟨hne, ?_⟩
        have hΓe' : Γe d.root = some Er.clean := by
          simp only [Γe, setE, upd_ne _ _ hne]; rw [cleanC_of hEr]
        obtain ⟨E', hE', hro'⟩ := h.post_root hΓe' (by rw [clean_mode]; exact hro)
        exact ⟨E', by simp only [setE, upd_ne _ _ hnx]; exact hE', hro'⟩)
    have hT := StmtT.scope (P := P) ⟨callX fn, h.canon_x _, by simp [callX, resMode_ne' fn]⟩ hxF
      (StmtT.seq hk (StmtT.frozen (z := H0) hrbT hHH) (hkT.weakenIn hW)) hpx
    -- where the call's scopes are
    have hbs := h.body_spine (m := envMem m env)
    have hcin : ∀ v ∈ (callIn fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x).spine, m.nv < v := by
      intro v hv
      rw [callIn_spine] at hv
      simp only [envMem] at hbs
      rw [hbs, List.append_nil] at hv
      rcases List.mem_cons.mp hv with rfl | hv
      · omega
      · obtain ⟨k', _, _, _, rfl⟩ := mem_wrapSpine hv; omega
    have hcsp : (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine =
        x :: (callIn fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x).spine := by
      rw [callStmt_spine, callIn_spine]
    have hssp : ∀ v, v ∈ (Stmt.scope x (.seq (.frozen H0 (.rbind m.nv
          (callIn fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x))) k)).spine ↔
        v = m.nv ∨ v ∈ (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine := by
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
    refine ⟨_, hT, ?_, by show m.nv ≤ m.nv + 1 + fn.nvars; omega,
      ⟨fun v E hv _ => ?_, fun v E' hv hvs => ?_, ?_⟩, fun v hv => ?_⟩
    · have hnd : (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine.Nodup := hI.spineNd
      have hdom : ∀ v ∈ (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine, ∃ E,
          (callS Γe (F ++ H) fn (m.nv :: zs ++ cs.map (·.1)) (envMem m env).nv x).canon (sigCtx fn) v = some E :=
        hI.spineDom
      have hnv : ∀ v ∈ (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).vars,
          v < m.nv + 1 + fn.nvars := hI.nvS
      rw [hcsp] at hnd hdom
      exact { toMInv := hI.toMInv
              nvS := fun v hv => by
                simp only [Stmt.vars, List.mem_cons, List.mem_append] at hv
                rcases hv with rfl | ((hv | rfl | hv) | hv)
                · exact hnv _ (by simp [callStmt, Stmt.vars])
                · exact Nat.lt_of_lt_of_le (hH0lt v hv) (Nat.le_trans (Nat.le_succ _) (Nat.le_add_right _ _))
                · show m.nv < m.nv + 1 + fn.nvars; omega
                · simp only [List.cons_append] at hv
                  exact hnv _ (by simp [callStmt, Stmt.vars, hv])
                · exact hnv _ (by simp [callStmt, Stmt.vars, hv])
              nvF := fun v hv => hI.nvF v (List.mem_append_left _ hv)
              anch := fun p Ep hp hm hs => by
                have hs' : p ≠ m.nv ∧ p ∉ (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine := by
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
                  rw [clean_rootb hm]
                  simp only [Γe, setE, upd_ne _ _ hs'.1] at h0
                  exact hic.anch p E1' h0 hm (by simp [Stmt.spine])
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
              cover := hI.cover
              pinOut := fun p Ep hp hm hs r hr hrs => by
                have hs' : p ≠ m.nv ∧ p ∉ (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine :=
                  ⟨fun e => hs ((hssp p).mpr (Or.inl e)), fun h' => hs ((hssp p).mpr (Or.inr h'))⟩
                rcases (hssp r).mp hrs with hre | hrc
                · -- the package's environment is bound after anything a borrowed
                  -- parameter outside the call depends on
                  rcases h.ctx_cases p with ⟨rfl, hc⟩ | ⟨rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ | ⟨k', t, hk', rfl, hc⟩ |
                      ⟨k', b', t, hk', rfl, hc⟩ | ⟨hy', hyx, hc⟩ | ⟨hc, v, hv, rfl⟩ <;> rw [hc] at hp <;>
                      (try cases hp)
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
                    simp only [Γe, setE, upd_ne _ _ hs'.1] at h0
                    obtain ⟨E2, h2, rfl⟩ := cleanC_some h0
                    have hm2 : E2.mode = .rootb := by rw [← clean_mode]; exact hm
                    rw [clean_rootb hm, clean_rootb hm2] at hr
                    have hlt := hi.rootbLt p E2 h2 hm2 r hr
                    have hpl : p < m.nv := hi.nvSt p (by rw [← hi.dom p, h2]; rfl)
                    rw [hre] at hlt
                    exact Nat.lt_irrefl _ (Nat.lt_trans hlt hpl)
                · exact hI.pinOut p Ep hp hm hs'.2 r hr hrc
              pinIn := ⟨fun E hE hm r hr hrs => by
                -- the environment depends on what is older than it, and every
                -- frame the call opens is younger
                have hlt := hI.rootbLt _ E hE hm r hr
                have hbs : (fn.body.rename (callRen fn.params (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1))).spine =
                    [] := h.body_spine
                rw [callIn_spine, hbs, List.append_nil] at hrs
                rcases List.mem_cons.mp hrs with he | he
                · rw [he] at hlt
                  exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le hlt
                    (Nat.le_trans (Nat.le_succ _) (Nat.le_add_right _ _)))
                · obtain ⟨k', _, _, _, he⟩ := mem_wrapSpine he
                  rw [he] at hlt
                  exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le hlt
                    (Nat.le_trans (Nat.le_succ _) (Nat.le_trans (Nat.le_add_right _ 0) (Nat.le_add_right _ _)))),
                hI.pinIn⟩
              dtorOut := fun v E hv hd hos hn hvs d hdd hnm hrs => by
                have hve : v ≠ m.nv := fun e => hvs ((hssp v).mpr (Or.inl e))
                have hns : v ∉ (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine :=
                  fun h' => hvs ((hssp v).mpr (Or.inr h'))
                rcases (hssp d.root).mp hrs with hre | hrc
                · -- the environment is younger than all a caller binding views
                  obtain ⟨_, _, E1, h1, rfl⟩ := h.dbind_frame hv hd
                  rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos
                  have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
                  obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := h.post_dkeep v E1 h1 hd hos hn1 (by simp)
                  simp only [Γe, setE, upd_ne _ _ hve] at h0
                  obtain ⟨E00, h00, rfl⟩ := cleanC_some h0
                  rw [Entry.clean_dbind] at hd0; rw [clean_mode] at hos0; rw [clean_ty, clean_mode] at hn0
                  obtain ⟨Er, hEr, _⟩ := hi.wf.dtor v E00 h00 hd0 hos0 hn0 d
                    (Entry.clean_vdeps_sub (hs0 d (Entry.clean_vdeps_sub hdd) hnm)) hnm
                  rw [hre, hΓe0] at hEr; cases hEr
                · exact hI.dtorOut v E hv hd hos hn hns d hdd hnm hrc
              dtorIn := DtorPinOK.of_spine_dbind fun v hv E hE => by
                rcases (hssp v).mp hv with rfl | hv'
                · cases hd : E.dbind with
                  | false => rfl
                  | true =>
                    obtain ⟨_, _, E1, h1, rfl⟩ := h.dbind_frame hE hd
                    rw [Entry.clean_dbind] at hd
                    obtain ⟨E0, h0, hd0⟩ := h.post_dbind h1 hd
                    rw [hEe] at h0; cases h0
                    exact absurd hd0 (by simp [Ee, envE])
                · exact h.spine_dbind v hv' E hE }
    · have hve : v ≠ m.nv := fun e => by rw [e, hΓe0] at hv; cases hv
      have hv' : Γe v = some E.clean := by simp only [Γe, setE, upd_ne _ _ hve]; exact cleanC_of hv
      obtain ⟨hns, E', h', hm', ht', hrb'⟩ := hkeep.1 v E.clean hv' (by simp [Stmt.spine])
      refine ⟨fun h'' => (((hssp v).mp h'').elim hve hns), E', h', by rw [hm', clean_mode],
        by rw [ht', clean_ty], fun hr => ?_⟩
      rw [hrb' (by rw [clean_mode]; exact hr), clean_rootb hr]
    · have hve : v ≠ m.nv := fun e => hvs ((hssp v).mpr (Or.inl e))
      have hns : v ∉ (callStmt fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x k).spine :=
        fun h' => hvs ((hssp v).mpr (Or.inr h'))
      obtain ⟨_, E0, h0⟩ := hkeep.2.1 v E' hv hns
      simp only [Γe, setE, upd_ne _ _ hve] at h0
      obtain ⟨E1, h1, _⟩ := cleanC_some h0
      exact ⟨by simp [Stmt.spine], E1, h1⟩
    · -- a binding `letd` made is the caller's, viewing no more than before
      intro v E' hv hd hos hn hvs
      have hve : v ≠ m.nv := fun e => hvs ((hssp v).mpr (Or.inl e))
      obtain ⟨_, _, E1, h1, rfl⟩ := h.dbind_frame hv hd
      rw [Entry.clean_dbind] at hd; rw [clean_mode] at hos
      have hn1 : E1.ty ≠ .int ∨ E1.mode = .rootb := by rwa [clean_ty, clean_mode] at hn
      obtain ⟨E0, h0, hd0, hos0, hn0, hs0⟩ := h.post_dkeep v E1 h1 hd hos hn1 (by simp)
      simp only [Γe, setE, upd_ne _ _ hve] at h0
      obtain ⟨E00, h00, rfl⟩ := cleanC_some h0
      rw [Entry.clean_dbind] at hd0; rw [clean_mode] at hos0; rw [clean_ty, clean_mode] at hn0
      exact ⟨E00, h00, hd0, hos0, hn0, fun d hdd hnm => Entry.clean_vdeps_sub (hs0 d (Entry.clean_vdeps_sub hdd) hnm)⟩
    · have hve : v ≠ m.nv := fun e => hFe (e ▸ hv)
      refine Eq.trans (h.frz hIe.toMInv hb v (List.mem_append_left _ hv)) ?_
      simp [envMem, Mem.set, upd_ne _ _ hve]

end A2
