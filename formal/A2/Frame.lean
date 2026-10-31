import A2.Values

/-! A2 — one binding's slot changes; everything that did not depend on it in
an ending way stays valid. -/

namespace A2

/-- A view stored in an owned tree is not valid through that tree's owner:
    no tree views itself. -/
theorem viewAt_not_self {m : Mem} {x : Var} {T : Val} (hT : m.st x = some ⟨true, some T⟩)
    (hsf : SelfFree T) {τ s : Ty} {d o l : Nat} (hin : ViewIn τ T s (.view d o l)) {k : Kind}
    (ha : ViewAt m ⟨x, k⟩ d o l s) : False := by
  obtain ⟨n0, c, es, hr, hk, _, _⟩ := ha
  have ht := rootNode_own hT hr
  have hs : Sub (.node s c d es) n0 := by
    rcases hk with ⟨_, h⟩ | ⟨_, h⟩
    · rw [h]; exact Sub.refl _
    · exact h.sub
  exact hsf d o l hin.sub s c es (hs.trans ht.sub)

/-- The views stored in an owned tree stay valid when only that tree's owner
    changes, if the others they depend on keep their memory. -/
theorem ViewsOK.keep_except {m m' : Mem} {x : Var} {τ : Ty} {T U : Val}
    (hT : m.st x = some ⟨true, some T⟩) (hsf : SelfFree T) {τ' : Ty} {H : List Dep}
    (hsub : ∀ s v, ViewIn τ' U s v → ViewIn τ T s v)
    (hk : ∀ dep ∈ H, dep.root ≠ x → VKeep m m' dep) (hv : ViewsOK m τ T H) :
    ViewsOK m' τ' U H := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv s v (hsub s v hin)
  refine ⟨d, o, l, rfl, dep, hd, hk dep hd ?_ d o l s ha⟩
  intro heq
  obtain ⟨r, k⟩ := dep
  simp only at heq; subst heq
  exact viewAt_not_self hT hsf (hsub s _ hin) ha

/-! ### The general frame lemma -/

theorem killE_ty (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).ty = E.ty := by
  unfold killE; split <;> rfl
theorem killE_mode (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).mode = E.mode := by
  unfold killE; split <;> rfl
theorem killE_path (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).path = E.path := by
  unfold killE; split <;> rfl
theorem killE_held (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).held = E.held := by
  unfold killE; split <;> rfl
theorem killE_dtor (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).dtor = E.dtor := by
  unfold killE; split <;> rfl
theorem killE_dbind (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).dbind = E.dbind := by
  unfold killE; split <;> rfl
theorem killE_vdeps (e : Eff) (hv : Bool) (x : Var) (E : Entry) :
    (killE e hv x E).vdeps = E.vdeps := by
  simp [Entry.vdeps, killE_mode, killE_path, killE_held]
/-- A2-drop.2: a kill and a binding that runs no destructor keep an
    effect safe. -/
theorem DtorSafe.kill {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : DtorSafe Γ e hv x)
    (e' : Eff) (hv' : Bool) (y : Var) : DtorSafe (A2.kill e' hv' y Γ) e hv x := by
  intro v E hE hd hos
  simp only [A2.kill] at hE
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hE
  rw [killE_dtor] at hd; rw [killE_mode] at hos
  have := h v E0 h0 hd hos
  unfold hitsMem at this ⊢
  rw [killE_ty, killE_mode, killE_vdeps]; exact this

theorem DtorSafe.setE_off {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : DtorSafe Γ e hv x)
    {y : Var} {E : Entry} (hE : E.dtor = false) : DtorSafe (A2.setE Γ y E) e hv x := by
  intro v E' hv' hd hos
  by_cases hvy : v = y
  · subst hvy; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'
    rw [hE] at hd; cases hd
  · simp only [A2.setE, upd_ne _ _ hvy] at hv'; exact h v E' hv' hd hos

theorem DbindSafe.setE_off {Γ : Ctx} {x : Var} (h : DbindSafe Γ x) {y : Var} {E : Entry}
    (hE : E.dbind = false) : DbindSafe (A2.setE Γ y E) x := by
  intro v E' hv' hd
  by_cases hvy : v = y
  · subst hvy; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'
    rw [hE] at hd; cases hd
  · simp only [A2.setE, upd_ne _ _ hvy] at hv'; exact h v E' hv' hd

/-- Binding an entry that depends on nothing keeps both checks. -/
theorem DtorSafe.setE_nil {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : DtorSafe Γ e hv x)
    {y : Var} {E : Entry} (hE : E.vdeps = []) : DtorSafe (A2.setE Γ y E) e hv x := by
  intro v E' hv' hd hos
  by_cases hvy : v = y
  · subst hvy; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'
    unfold hitsMem; simp [hE]
  · simp only [A2.setE, upd_ne _ _ hvy] at hv'; exact h v E' hv' hd hos

theorem DbindSafe.setE_nil {Γ : Ctx} {x : Var} (h : DbindSafe Γ x) {y : Var} {E : Entry}
    (hE : E.vdeps = []) : DbindSafe (A2.setE Γ y E) x := by
  intro v E' hv' hd hos hn d hdd
  by_cases hvy : v = y
  · subst hvy; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'
    rw [hE] at hdd; cases hdd
  · simp only [A2.setE, upd_ne _ _ hvy] at hv'; exact h v E' hv' hd hos hn d hdd

theorem DKeep.kill {Γ Γ' : Ctx} {sp : List Var} (h : DKeep Γ Γ' sp) (e : Eff) (hv : Bool) (x : Var) :
    DKeep Γ (A2.kill e hv x Γ') sp := by
  intro v E hE hd hos hn hvs
  simp only [A2.kill] at hE
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hE
  rw [killE_dbind] at hd; rw [killE_mode] at hos; rw [killE_ty, killE_mode] at hn
  obtain ⟨E1, h1, hd1, hos1, hn1, hs1⟩ := h v E0 h0 hd hos hn hvs
  exact ⟨E1, h1, hd1, hos1, hn1, fun d hdd hnm => hs1 d (by rwa [killE_vdeps] at hdd) hnm⟩

theorem DKeep.exitScope {Γ Γ' : Ctx} {sp : List Var} (h : DKeep Γ Γ' sp) (x : Var) :
    DKeep Γ (A2.exitScope x Γ') sp := by
  intro v E hv hd hos hn hvs
  have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv
  simp only [A2.exitScope, upd_ne _ _ hvx] at hv
  exact (h.kill .replace false x) v E hv hd hos hn hvs

/-- Binding an entry that views nothing of `x` keeps both checks on `x`. -/
theorem DtorSafe.setE_noroot {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : DtorSafe Γ e hv x)
    {y : Var} {E : Entry} (hE : ∀ d ∈ E.vdeps, d.root ≠ x) : DtorSafe (A2.setE Γ y E) e hv x := by
  intro v E' hv' hd hos
  by_cases hvy : v = y
  · subst hvy; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'
    unfold hitsMem
    simp only [Bool.and_eq_false_iff, List.any_eq_false]
    right; intro d hdd hk
    simp only [Bool.and_eq_true, beq_iff_eq] at hk
    exact hE d hdd hk.1.1
  · simp only [A2.setE, upd_ne _ _ hvy] at hv'; exact h v E' hv' hd hos

theorem DbindSafe.setE_noroot {Γ : Ctx} {x : Var} (h : DbindSafe Γ x) {y : Var} {E : Entry}
    (hE : ∀ d ∈ E.vdeps, d.root ≠ x) : DbindSafe (A2.setE Γ y E) x := by
  intro v E' hv' hd hos hn d hdd
  by_cases hvy : v = y
  · subst hvy; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'
    exact fun _ => hE d hdd
  · simp only [A2.setE, upd_ne _ _ hvy] at hv'; exact h v E' hv' hd hos hn d hdd

theorem DStay.setE {Γ Γ' : Ctx} {sp : List Var} (h : DStay Γ Γ' sp) {y : Var} {E : Entry}
    (hE : ∀ E0, Γ y = some E0 → E0.dbind = true → E0.mode.ownSlot = true → y ∉ sp →
      E.dbind = true ∧ E.mode.ownSlot = true) :
    DStay Γ (A2.setE Γ' y E) sp := fun v E0 hv hd hos hvs => by
  by_cases hvy : v = y
  · subst hvy
    obtain ⟨h1, h2⟩ := hE E0 hv hd hos hvs
    exact ⟨E, by simp [A2.setE], h1, h2⟩
  · obtain ⟨E', h', hd', hos'⟩ := h v E0 hv hd hos hvs
    exact ⟨E', by simp [A2.setE, upd_ne _ _ hvy, h'], hd', hos'⟩

theorem DStay.kill {Γ Γ' : Ctx} {sp : List Var} (h : DStay Γ Γ' sp) (e : Eff) (hv : Bool) (x : Var) :
    DStay Γ (A2.kill e hv x Γ') sp := fun v E hE hd hos hvs => by
  obtain ⟨E', h', hd', hos'⟩ := h v E hE hd hos hvs
  exact ⟨killE e hv x E', by simp [A2.kill, h'], by rw [killE_dbind]; exact hd', by rw [killE_mode]; exact hos'⟩

/-- A scope's end keeps every other binding `letd` made. -/
theorem DStay.exitScope {Γ Γ' : Ctx} {sp : List Var} {x : Var} (h : DStay Γ Γ' sp) :
    DStay Γ (A2.exitScope x Γ') (x :: sp) := fun v E hv hd hos hvs => by
  have hvx : v ≠ x := fun e => hvs (by simp [e])
  obtain ⟨E', h', hd', hos'⟩ := h v E hv hd hos (fun hm => hvs (List.mem_cons_of_mem _ hm))
  exact ⟨killE .replace false x E', by simp [A2.exitScope, upd_ne _ _ hvx, A2.kill, h'],
    by rw [killE_dbind]; exact hd', by rw [killE_mode]; exact hos'⟩

/-- Setting an entry: one no `letd` made, or one that views no more than
    the old entry of a `letd` binding. -/
theorem DKeep.setE {Γ Γ' : Ctx} {sp : List Var} (h : DKeep Γ Γ' sp) {y : Var} {E : Entry}
    (hE : E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) → y ∉ sp →
      ∃ E0, Γ y = some E0 ∧ E0.dbind = true ∧ E0.mode.ownSlot = true ∧ (E0.ty ≠ .int ∨ E0.mode = .rootb) ∧
        ∀ d ∈ E.vdeps, d.kind.isName = false → d ∈ E0.vdeps := by intro h; simp_all) :
    DKeep Γ (A2.setE Γ' y E) sp := by
  intro v E' hv hd hos hn hvs
  by_cases hvy : v = y
  · subst hvy; simp only [A2.setE, upd_same, Option.some.injEq] at hv; subst hv
    exact hE hd hos hn hvs
  · simp only [A2.setE, upd_ne _ _ hvy] at hv; exact h v E' hv hd hos hn hvs

/-- A2-drop.2: in a well-formed context no `letd` binding views an unbound
    variable, so ending a fresh one is safe. -/
theorem DbindSafe.of_fresh {Γ : Ctx} (hw : CtxWF Γ) {x : Var} (hx : Γ x = none) : DbindSafe Γ x := by
  intro v E hE hd hos hn d hdd hnm hdx
  obtain ⟨Er, hEr, _⟩ := hw.dtor v E hE hd hos hn d hdd hnm
  rw [hdx, hx] at hEr; cases hEr

/-- Only a binding `letd` made may be armed, so when none views `x` no
    effect on `x` reaches a destructor. -/
theorem DtorSafe.of_dbind {Γ : Ctx} (hw : CtxWF Γ) {x : Var} (h : DbindSafe Γ x) (e : Eff) (hv : Bool) :
    DtorSafe Γ e hv x := by
  intro v E hE hd hos
  have hdb := hw.arm v E hE hd
  unfold hitsMem
  cases hg : (E.ty != .int || E.mode == .rootb) with
  | false => rfl
  | true =>
    have hg' : E.ty ≠ .int ∨ E.mode = .rootb := by
      simpa only [Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq] using hg
    simp only [Bool.true_and, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and]
    intro d hdd hr _
    exact h v E hE hdb hos hg' d hdd (by simpa using hr.2) hr.1

theorem DtorSafe.of_fresh {Γ : Ctx} (hw : CtxWF Γ) {x : Var} (hx : Γ x = none) (e : Eff) (hv : Bool) :
    DtorSafe Γ e hv x :=
  DtorSafe.of_dbind hw (DbindSafe.of_fresh hw hx) e hv

theorem killE_live (e : Eff) (hv : Bool) (x : Var) (E : Entry) :
    (killE e hv x E).live = (E.live && !hits e hv x E) := by
  unfold killE; split <;> simp_all

theorem comp_name {a k : Kind} {b : Eff} {t : Ty} (h : comp a k = .name b t) (hk : k.isName = false) :
    a = .name b t := by
  cases a <;> cases k <;> simp_all [comp, Kind.isName]

/-- A binding that owns its slot and holds nothing depends on nothing. -/
theorem root_vdeps {E : Entry} (ho : E.mode.ownSlot = true) (hh : E.held = []) : E.vdeps = [] := by
  simp [Entry.vdeps, ho, hh]

/-- ... and no change ends it. -/
theorem killE_nil {E : Entry} (h : E.vdeps = []) (e : Eff) (hv : Bool) (x : Var) : killE e hv x E = E := by
  unfold killE hits; simp [h]

/-- What entries hold by name stays bound with its type and mode when some
    of them end. -/
theorem NameOK.kill {Γ : Ctx} {E : Entry} (h : NameOK Γ E) (e : Eff) (hv : Bool) (x : Var) :
    NameOK (kill e hv x Γ) (killE e hv x E) := by
  intro d hd b t hk
  rw [NameOK, killE_vdeps] at *
  obtain ⟨Er, hEr, hl, hh, ht, ho, hc⟩ := h d hd b t hk
  exact ⟨Er, by simp only [A2.kill, hEr, Option.map_some, killE_nil (root_vdeps ho hh)], hl, hh, ht, ho, hc⟩

theorem NameWF.kill {Γ : Ctx} (h : NameWF Γ) (e : Eff) (hv : Bool) (x : Var) :
    NameWF (kill e hv x Γ) := by
  intro v E' hv' hl hn
  simp only [A2.kill] at hv'
  cases hE : Γ v with
  | none => rw [hE] at hv'; cases hv'
  | some E =>
    rw [hE] at hv'; cases hv'
    rw [killE_live] at hl; simp only [Bool.and_eq_true] at hl
    rw [killE_ty, killE_mode] at hn
    exact (h v E hE hl.1 hn).kill e hv x

/-- A live entry after `kill` was not hit: each dependency on `x` is of a
    kind the effect does not end. -/
theorem killE_live_dep {e : Eff} {hv : Bool} {x : Var} {E : Entry}
    (hl : (killE e hv x E).live = true) (hnint : E.ty ≠ .int ∨ E.mode = .rootb) :
    E.live = true ∧ ∀ dep ∈ E.vdeps, dep.root = x → e.kills hv dep.kind = false := by
  rw [killE_live] at hl
  simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hl
  refine ⟨hl.1, fun dep hd hr => ?_⟩
  cases hb : e.kills hv dep.kind with
  | false => rfl
  | true =>
    exfalso
    have : hits e hv x E = true := by
      unfold hits
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, List.any_eq_true,
        beq_iff_eq]
      refine ⟨?_, dep, hd, hr, hb⟩
      rcases hnint with h | h
      · exact Or.inl h
      · exact Or.inr (by rw [h])
    rw [this] at hl; exact absurd hl.2 (by simp)

theorem SlotOK.dead {m m' : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl) (hl : E.live = false) :
    SlotOK m' E sl := by
  obtain ⟨ho, hown, hbor⟩ := h
  refine ⟨ho, fun hos => ?_, fun _ hl' => by rw [hl] at hl'; cases hl'⟩
  obtain ⟨h1, h2, _⟩ := hown hos
  exact ⟨h1, h2, fun hl' => by rw [hl] at hl'; cases hl'⟩

/-- A slot reads memory only through a live entry's dependencies. -/
theorem SlotOK.keepLive {m m' : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl)
    (hk : E.live = true → ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep)
    (hb : m'.blk = m.blk := by rfl) : SlotOK m' E sl := by
  obtain ⟨ho, hown, hbor⟩ := h
  refine ⟨ho, fun hos => ?_, fun hos hl => ?_⟩
  · obtain ⟨h1, h2, h3⟩ := hown hos
    refine ⟨h1, h2, fun hl => ?_⟩
    obtain ⟨T, hT, hv⟩ := h3 hl
    refine ⟨T, hT, hv.keep fun dep hd => (hk hl dep ?_).1⟩
    simp [Entry.vdeps, hos, hd]
  · obtain ⟨v, hv, hok⟩ := hbor hos hl
    refine ⟨v, hv, hok.keep (fun dep hd => hk hl dep ?_) (fun dep hd => hk hl dep ?_) hb⟩
    · simp [Entry.vdeps, hos, hd]
    · simp [Entry.vdeps, hos, hd]

theorem SlotOK.keep {m m' : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl)
    (hk : ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep) (hb : m'.blk = m.blk := by rfl) :
    SlotOK m' E sl :=
  h.keepLive (fun _ => hk) hb

/-- What the slot of the changed binding holds afterwards, if anything. -/
def NewSlot (m' : Mem) (Γ0 : Ctx) (x : Var) (Ex : Entry) : Option Entry → Prop
  | none => m'.st x = none
  | some Ex' => ∃ sl, m'.st x = some sl ∧ Ex'.ty.ok = true ∧ SlotOK m' Ex' sl ∧
      Ex'.mode = Ex.mode ∧
      (Ex'.live = true → Ex'.ty ≠ .int → ∀ r ∈ roots Ex'.vdeps,
        (r = x ∧ Ex'.mode.isRoot = true) ∨ (r ≠ x ∧ ∃ Er, Γ0 r = some Er ∧ Er.mode.isRoot = true)) ∧
      Ex'.ty = Ex.ty ∧
      (Ex'.live = true → (Ex'.ty ≠ .int ∨ Ex'.mode = .rootb) → NameOK (upd Γ0 x (some Ex')) Ex') ∧
      (Ex'.live = true → ∀ T, sl.val = some T → NamesIn T Ex'.held) ∧
      (∀ T, sl.val = some T → PkgsOK T) ∧
      -- A2-drop.2: an owner that may run a destructor views only bound roots
      (Ex'.dbind = true → Ex'.mode.ownSlot = true → Ex'.ty ≠ .int → ∀ d ∈ Ex'.vdeps,
        d.kind.isName = false → (d.root = x ∧ Ex'.mode.isRoot = true) ∨
          (d.root ≠ x ∧ ∃ Er, Γ0 d.root = some Er ∧ Er.mode.isRoot = true)) ∧
      (Ex'.dtor = true → Ex'.dbind = true) ∧ (Ex'.dbind = true → Ex'.ty.holdsView = true) ∧
      ArmOK m' Ex' sl

/-- An integer holds no closure, so captures nothing by name. -/
theorem names_nil_of_int {m : Mem} {E : Entry} {sl : Slot} {T : Val} (h : SlotOK m E sl)
    (hint : E.ty = .int) (hl : E.live = true) (hT : sl.val = some T) : T.names = [] := by
  cases ho : E.mode.ownSlot
  · obtain ⟨v, hv, hok⟩ := h.2.2 ho hl
    rw [hint] at hok; obtain ⟨n, rfl⟩ := valOK_int.mp hok
    rw [hT] at hv; cases hv; rfl
  · have := (h.2.1 ho).1; rw [hint] at this; simp [Ty.owning] at this

theorem killE_rootb {Γ : Ctx} {F : List Var}
    (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) (e : Eff) (hv : Bool)
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    {v : Var} {E : Entry} (hE : Γ v = some E)
    (hrb : E.mode = .rootb) : killE e hv x E = E := by
  unfold killE
  have : hits e hv x E = false := by
    unfold hits
    simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
      beq_iff_eq, not_and, Bool.not_eq_true]
    refine Or.inr fun dep hd hr => ?_
    by_cases hb : dep.kind.bound = .none
    · exact absurd (hr ▸ hanch v E hE hrb dep hd hb) hxF
    · cases hk : e.kills hv dep.kind
      · rfl
      · exact absurd hr (hmn v E hE hrb dep hd hb hk)
  rw [this]; rfl

theorem NoPin.kills {Γ : Ctx} {x : Var} (h : NoPin Γ x) (e : Eff) (hv : Bool) :
    ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x :=
  fun p E hp hm d hd hb _ => h p E hp hm d hd hb

/-- An effect other than `replace` ends nothing held by name. -/
theorem hmn_of_ne_replace {Γ : Ctx} {e : Eff} (hv : Bool) (he : e ≠ .replace) (x : Var) :
    ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x := by
  intro _ _ _ _ ⟨r, k⟩ _ hb hk
  cases k <;> cases e <;> simp_all [Kind.bound, Eff.kills]

/-- One binding `x` changes (effect `e`), its slot becomes `ox`: every other
    binding stays valid, or is ended by `kill`. -/
theorem MInv.change {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} {Ex : Entry} (hx : Γ x = some Ex) (hxF : x ∉ F) {e : Eff} {hv : Bool}
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    (hxr : Ex.mode ≠ .rootb)
    (hst : ∀ o, o ≠ x → m'.st o = m.st o) (hheap : HeapOK m') (hnv : m'.nv = m.nv)
    (hkeep : ∀ k, e.kills hv k = false → VKeep m m' ⟨x, k⟩ ∧ HKeep m m' ⟨x, k⟩)
    {ox : Option Entry} (hox : NewSlot m' (kill e hv x Γ) x Ex ox)
    (hds : DtorSafe Γ e hv x)
    (hdb : ox = none → DbindSafe Γ x)
    (hrem : ox = none → e = .replace)
    (hnew : e ≠ .replace → ∀ Ex', ox = some Ex' → Ex.live = true → Ex.held = [] →
      Ex.ty.holdsView = false → Ex'.live = true ∧ Ex'.held = [])
    (hblk : m'.blk = m.blk := by rfl) :
    MInv m' (upd (kill e hv x Γ) x ox) := by
  have depKeep : ∀ v E, Γ v = some E → (killE e hv x E).live = true → E.ty ≠ .int →
      ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep := by
    intro v E hv' hl hnint dep hd
    obtain ⟨hlE, hnot⟩ := killE_live_dep hl (Or.inl hnint)
    by_cases hr : dep.root = x
    · obtain ⟨r, k⟩ := dep
      simp only at hr; subst hr
      exact hkeep k (hnot _ hd rfl)
    · obtain ⟨Er, hEr, hroot⟩ := hi.wf v E hv' hlE (Or.inl hnint) dep.root (List.mem_map_of_mem hd)
      have hk := rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot
        (hst _ hr)
      exact ⟨hk.vkeep, hk.hkeep⟩
  have getE : ∀ v E', upd (kill e hv x Γ) x ox v = some E' → v ≠ x →
      ∃ E, Γ v = some E ∧ E' = killE e hv x E := by
    intro v E' h hvx
    rw [upd_ne _ _ hvx] at h
    unfold kill at h
    cases hE : Γ v with
    | none => rw [hE] at h; cases h
    | some E => rw [hE] at h; cases h; exact ⟨E, rfl, rfl⟩
  have getX : ∀ E', upd (kill e hv x Γ) x ox x = some E' → ox = some E' := by
    intro E' h; simpa using h
  constructor
  · intro v
    by_cases hvx : v = x
    · subst hvx
      cases ox with
      | none => simp only [upd_same, Option.isSome_none]; rw [show m'.st v = none from hox]; rfl
      | some Ex' =>
        obtain ⟨sl, hsl, _⟩ := hox
        simp [hsl]
    · rw [upd_ne _ _ hvx, hst v hvx, ← hi.dom v]
      unfold kill; cases Γ v <;> rfl
  · intro v E' hv'
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl, hsl, hok, hslot, _⟩ := hox
      exact ⟨sl, hsl, hok, hslot⟩
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot v E hE
      refine ⟨sl, by rw [hst v hvx]; exact hsl, by rw [killE_ty]; exact hok, ?_⟩
      by_cases hl : (killE e hv x E).live = true
      · have hEq : killE e hv x E = E := by
          have := (killE_live_dep (e := e) (hv := hv) (x := x) (E := E))
          unfold killE at hl ⊢; split at hl
          · simp at hl
          · rename_i hh; simp [hh]
        rw [hEq] at hl ⊢
        by_cases hint : E.ty = .int
        · obtain ⟨ho, hown, hbor⟩ := hslot
          refine ⟨ho, fun hos => ?_, fun hos hl' => ?_⟩
          · obtain ⟨ht, _⟩ := hown hos
            rw [hint] at ht; cases ht
          · obtain ⟨w, hw, hok'⟩ := hbor hos hl'
            exact ⟨w, hw, by rw [hint] at hok' ⊢; obtain ⟨n, rfl⟩ := valOK_int.mp hok'; exact .int⟩
        · refine hslot.keep (fun dep hd => depKeep v E hE (by rw [hEq]; exact hl) hint dep hd) hblk
      · have hdead : (killE e hv x E).live = false := by simpa using hl
        by_cases hrb : E.mode = .rootb
        · rw [killE_rootb hanch hxF e hv hmn hE hrb] at hdead
          rw [hi.rootbLive v E hE hrb] at hdead; cases hdead
        · exact (hslot.weaker' (killE_ty ..) (killE_mode ..) (fun h => by rw [hdead] at h; cases h)).dead hdead
  · exact hheap
  · intro v hv'
    rw [hnv]
    by_cases hvx : v = x
    · subst hvx; exact hi.nvSt v (by rw [← hi.dom v, hx]; rfl)
    · exact hi.nvSt v (by rw [← hst v hvx]; exact hv')
  · intro v E' b hv'
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨_, _, _, _, hm, _⟩ := hox
      rw [hm]; exact hi.noInout v Ex b hx
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [killE_mode]; exact hi.noInout v E b hE
  · refine ⟨?live, ?dtorc, ?armc, ?viewc⟩
    case armc =>
      intro v E' hv' hd
      by_cases hvx : v = x
      · subst hvx
        have := getX E' hv'; subst this
        obtain ⟨_, _, _, _, _, _, _, _, _, _, _, harm, _, _⟩ := hox
        exact harm hd
      · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
        rw [killE_dtor] at hd; rw [killE_dbind]; exact hi.wf.arm v E hE hd
    case viewc =>
      intro v E' hv' hd
      by_cases hvx : v = x
      · subst hvx
        have := getX E' hv'; subst this
        obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, hview, _⟩ := hox
        exact hview hd
      · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
        rw [killE_dbind] at hd; rw [killE_ty]; exact hi.wf.view v E hE hd
    case dtorc =>
      -- A2-drop.2: a destructor owner's views: the change ended none (`DtorSafe`)
      intro v E' hv' hd hos hnint d hdd hnm
      by_cases hvx : v = x
      · subst hvx
        have := getX E' hv'; subst this
        obtain ⟨_, _, _, _, hm', _, _, _, _, _, hdwf, _⟩ := hox
        have hnint' : E'.ty ≠ .int := by
          rcases hnint with h | h
          · exact h
          · exact absurd (hm' ▸ h) hxr
        rcases hdwf hd hos hnint' d hdd hnm with ⟨hrx, hroot⟩ | ⟨hrx, Er, hEr, hroot⟩
        · exact ⟨E', by rw [hrx]; simp, hroot⟩
        · exact ⟨Er, by rw [upd_ne _ _ hrx]; exact hEr, hroot⟩
      · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
        rw [killE_dbind] at hd; rw [killE_mode] at hos; rw [killE_ty, killE_mode] at hnint
        rw [killE_vdeps] at hdd
        obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor v E hE hd hos hnint d hdd hnm
        by_cases hrx : d.root = x
        · -- a view of `x`: `x` is still bound, or no destructor binding views it
          cases ox with
          | none => exact absurd hrx (hdb rfl v E hE hd hos hnint d hdd hnm)
          | some Ex' =>
            obtain ⟨_, _, _, _, hm, _⟩ := hox
            rw [hrx, hx] at hEr; cases hEr
            exact ⟨Ex', by rw [hrx]; simp, by rw [hm]; exact hroot⟩
        · refine ⟨killE e hv x Er, ?_, by rw [killE_mode]; exact hroot⟩
          rw [upd_ne _ _ hrx]; unfold kill; rw [hEr]; rfl
    intro v E' hv' hl hnint r hr
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨_, _, _, _, hm', hwf, _⟩ := hox
      have hnint' : E'.ty ≠ .int := by
        rcases hnint with h | h
        · exact h
        · exact absurd (hm' ▸ h) hxr
      rcases hwf hl hnint' r hr with ⟨rfl, hroot⟩ | ⟨hrx, Er, hEr, hroot⟩
      · exact ⟨E', by simp, hroot⟩
      · exact ⟨Er, by rw [upd_ne _ _ hrx]; exact hEr, hroot⟩
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [killE_ty, killE_mode] at hnint
      rw [killE_vdeps] at hr
      have hlE : E.live = true := by
        rw [killE_live] at hl; simp only [Bool.and_eq_true] at hl; exact hl.1
      obtain ⟨Er, hEr, hroot⟩ := hi.wf v E hE hlE hnint r hr
      by_cases hrx : r = x
      · subst hrx
        cases ox with
        | none =>
          exfalso
          obtain ⟨dep, hd, rfl⟩ := List.mem_map.mp hr
          rcases hnint with hnint | hrb
          · have := (killE_live_dep hl (Or.inl hnint)).2 dep hd rfl
            rw [hrem rfl] at this
            cases hk : dep.kind <;> rw [hk] at this <;> simp [Eff.kills] at this
          · by_cases hb : dep.kind.bound = .none
            · exact hxF (hanch v E hE hrb dep hd hb)
            · exact hmn v E hE hrb dep hd hb (by rw [hrem rfl]; cases dep.kind <;> rfl) rfl
        | some Ex' =>
          obtain ⟨_, _, _, _, hm, _⟩ := hox
          rw [hx] at hEr; cases hEr
          exact ⟨Ex', by simp, by rw [hm]; exact hroot⟩
      · refine ⟨killE e hv x Er, ?_, by rw [killE_mode]; exact hroot⟩
        rw [upd_ne _ _ hrx]; unfold kill; rw [hEr]; rfl
  · intro p E' hp' hm
    by_cases hpx : p = x
    · subst hpx
      have := getX E' hp'; subst this
      obtain ⟨_, _, _, _, hm', _⟩ := hox
      exact absurd (hm' ▸ hm) hxr
    · obtain ⟨E, hE, rfl⟩ := getE p E' hp' hpx
      rw [killE_mode] at hm
      rw [killE_rootb hanch hxF e hv hmn hE hm]
      exact hi.rootbLive p E hE hm
  · intro p E' hp' hm
    by_cases hpx : p = x
    · subst hpx
      have := getX E' hp'; subst this
      obtain ⟨_, _, _, _, hm', _⟩ := hox
      exact absurd (hm' ▸ hm) hxr
    · obtain ⟨E, hE, rfl⟩ := getE p E' hp' hpx
      rw [killE_mode] at hm
      rw [killE_rootb hanch hxF e hv hmn hE hm]
      exact hi.rootbLt p E hE hm
  · intro v E' hv' hl hn
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨_, _, _, _, _, _, _, hnm, _⟩ := hox
      exact hnm hl hn
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [killE_ty, killE_mode] at hn
      have hl' := killE_live_dep hl hn
      intro d hd b t hk
      rw [killE_vdeps] at hd
      obtain ⟨Er, hEr, hlr, hhr, ht, ho, hc⟩ := hi.names v E hE hl'.1 hn d hd b t hk
      by_cases hdx : d.root = x
      · have hkx := hl'.2 d hd hdx
        rw [hdx, hx] at hEr; cases hEr
        have hre : e ≠ .replace := fun h => by rw [h, hk] at hkx; cases hkx
        cases ox with
        | none => exact absurd (hrem rfl) hre
        | some Ex' =>
          obtain ⟨_, _, _, _, hm', _, hty', _⟩ := hox
          obtain ⟨hl'', hh''⟩ := hnew hre Ex' rfl hlr hhr (by rw [← ht] at hc; exact hc.2)
          exact ⟨Ex', by rw [hdx]; simp, hl'', hh'', by rw [hty']; exact ht, by rw [hm']; exact ho,
            by rw [hm']; exact hc⟩
      · exact ⟨killE e hv x Er, by rw [upd_ne _ _ hdx]; unfold kill; rw [hEr]; rfl,
          by rw [killE_nil (root_vdeps ho hhr)]; exact hlr, by rw [killE_nil (root_vdeps ho hhr)]; exact hhr,
          by rw [killE_ty]; exact ht, by rw [killE_mode]; exact ho, by rw [killE_mode]; exact hc⟩
  · intro v E' sl T hv' hl hsl hT
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, hin, _⟩ := hox
      rw [hsl'] at hsl; cases hsl
      exact hin hl T hT
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      have hlE : E.live = true := by
        rw [killE_live] at hl; simp only [Bool.and_eq_true] at hl; exact hl.1
      rw [hst v hvx] at hsl
      rw [killE_held]; exact hi.held v E sl T hE hlE hsl hT
  · intro v sl T hsl hT
    by_cases hvx : v = x
    · subst hvx
      cases ox with
      | none => rw [show m'.st v = none from hox] at hsl; cases hsl
      | some Ex' =>
        obtain ⟨sl', hsl', _, _, _, _, _, _, _, hpk, _, _⟩ := hox
        rw [hsl'] at hsl; cases hsl
        exact hpk T hT
    · rw [hst v hvx] at hsl; exact hi.pkgs v sl T hsl hT
  · -- A2-drop.2: no view of an armed binding is one the change ends (`DtorSafe`)
    intro v E' sl hv' hsl
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, _, _, _, _, _, harm⟩ := hox
      rw [hsl'] at hsl; cases hsl; exact harm
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [hst v hvx] at hsl
      refine ArmOK.entry (killE_dbind ..) (killE_ty ..) (killE_mode ..) (fun h => by rw [killE_dtor]; exact h)
        (by rw [killE_held]; exact fun d hd => (List.mem_filter.mp hd).1) ?_
      refine (hi.armed v E sl hE hsl).keep fun hdt hd hos dep hdm => ?_
      have hdm' := List.mem_filter.mp hdm
      have hnm : dep.kind.isName = false := by simpa using hdm'.2
      have hdv : dep ∈ E.vdeps := by unfold Entry.vdeps; exact List.mem_append_right _ hdm'.1
      have hnint : E.ty ≠ .int := fun h => by have := hi.wf.view v E hE hd; rw [h] at this; cases this
      by_cases hr : dep.root = x
      · obtain ⟨r, k⟩ := dep
        simp only at hr; subst hr
        exact (hkeep k (hitsMem_kills (hds v E hE hdt hos) (Or.inl hnint) hdv rfl hnm)).1
      · obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor v E hE hd hos (Or.inl hnint) dep hdv hnm
        exact (rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot (hst _ hr)).vkeep

end A2
