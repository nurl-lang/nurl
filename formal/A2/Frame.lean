import A2.Values

/-! A2 — one binding's slot changes; everything that did not depend on it in
an ending way stays valid. -/

namespace A2

/-- A view stored in an owned tree is not valid through that tree's owner
    (but through a share of it, A3.1): no tree views itself. -/
theorem viewAt_not_self {m : Mem} {x : Var} {T : Val} (hT : m.st x = some ⟨true, some T⟩)
    (hsf : SelfFree T) {τ s : Ty} {d o l : Nat} (hin : ViewIn τ T s (.view d o l)) {k : Kind}
    (hks : k ≠ .share) (ha : ViewAt m ⟨x, k⟩ d o l s) : False := by
  obtain ⟨c, es, _, hla, _, _⟩ := ha
  obtain ⟨n0, hr, hk⟩ := hla.root hks
  have ht := rootNode_own hT hr
  exact hsf d o l hin.sub s c es (hk.sub.trans ht.sub)

/-- The views stored in an owned tree stay valid when only that tree's owner
    changes, staying an owner, if the others they depend on keep their
    memory. (One valid through a share of the owner stays valid: the block
    lives, and the owner's slot is there, `RootMem`.) -/
theorem ViewsOK.keep_except {m m' : Mem} {x : Var} {τ : Ty} {T U : Val}
    (hT : m.st x = some ⟨true, some T⟩) (hsf : SelfFree T) {τ' : Ty} {H : List Dep}
    (hsub : ∀ s v, ViewIn τ' U s v → ViewIn τ T s v)
    (hk : ∀ dep ∈ H, dep.root ≠ x → VKeep m m' dep) (hv : ViewsOK m τ T H)
    (hx' : ∃ o, m'.st x = some ⟨true, o⟩)
    (hb : BlkLe m.blk m'.blk := by exact BlkLe.of_le fun _ _ h => h) :
    ViewsOK m' τ' U H := by
  intro s v hin
  obtain ⟨d, o, l, rfl, ⟨dep, hd, ha⟩ | hsv⟩ := hv s v (hsub s v hin)
  · refine ⟨d, o, l, rfl, .inl ⟨dep, hd, ?_⟩⟩
    obtain ⟨r, k⟩ := dep
    by_cases hrx : r = x
    · subst hrx
      by_cases hks : k = .share
      · subst hks
        obtain ⟨o', ho'⟩ := hx'
        exact vkeep_share hb (RootMem.own ho') d o l s ha
      · exact (viewAt_not_self hT hsf (hsub s _ hin) hks ha).elim
    · exact hk ⟨r, k⟩ hd hrx d o l s ha
  · exact ⟨d, o, l, rfl, .inr (hsv.blkLe hb)⟩

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
theorem killE_fresh (e : Eff) (hv : Bool) (x : Var) (E : Entry) : (killE e hv x E).fresh = E.fresh := by
  unfold killE; split <;> rfl

theorem killE_heldFresh (e : Eff) (hv : Bool) (x : Var) (E : Entry) :
    (killE e hv x E).heldFresh = E.heldFresh := by
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
    refine ⟨T, hT, hv.keep (hb := BlkLe.of_eq hb) fun dep hd => (hk hl dep ?_).1⟩
    simp [Entry.vdeps, hos, hd]
  · obtain ⟨v, hv, hok⟩ := hbor hos hl
    refine ⟨v, hv, hok.keep (fun dep hd => hk hl dep ?_) (fun dep hd => hk hl dep ?_) hb⟩
    · simp [Entry.vdeps, hos, hd]
    · simp [Entry.vdeps, hos, hd]

theorem SlotOK.keep {m m' : Mem} {E : Entry} {sl : Slot} (h : SlotOK m E sl)
    (hk : ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep) (hb : m'.blk = m.blk := by rfl) :
    SlotOK m' E sl :=
  h.keepLive (fun _ => hk) hb

/-- AGORA-937 B4: what `MInv.noPkg` asks of a slot: a binding whose type
    holds no closure that captures by name holds only packages capturing
    nothing by name. -/
def NoPkgS (E : Entry) (sl : Slot) : Prop :=
  E.ty.hasFn = false → ∀ T, sl.val = some T → ∀ fs te ms e cs, Sub (.pkg fs te ms e cs) T → cs = []

/-- ... which a well-formed tree of the binding's type has (`WFv.no_pkg`). -/
theorem NoPkgS.of_wfv {E : Entry} {sl : Slot} (h : ∀ T, sl.val = some T → WFv E.ty T) : NoPkgS E sl :=
  fun hf T hT _ _ _ _ _ hs => (h T hT).no_pkg hf hs

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
      ArmOK m' Ex' sl ∧
      -- A3.1: the shares its tree holds name live blocks
      (sl.own = true → ∀ T, sl.val = some T → SharesOK m' Ex'.ty T) ∧
      -- Agora #909: a fresh borrow reaches only the frame's own blocks
      FreshE (upd Γ0 x (some Ex')) Ex' ∧
      -- AGORA-937 B4: it holds no package capturing by name unless its type says so
      NoPkgS Ex' sl

/-- An integer holds no closure, so captures nothing by name. -/
theorem names_nil_of_int {m : Mem} {E : Entry} {sl : Slot} {T : Val} (h : SlotOK m E sl)
    (hint : E.ty = .int) (hl : E.live = true) (hT : sl.val = some T) : T.names = [] := by
  cases ho : E.mode.ownSlot
  · obtain ⟨v, hv, hok⟩ := h.2.2 ho hl
    rw [hint] at hok; obtain ⟨n, rfl⟩ := valOK_int.mp hok
    rw [hT] at hv; cases hv; rfl
  · have := (h.2.1 ho).1; rw [hint] at this; simp [Ty.owning] at this

/-- AGORA-937 (3d, route U): what a kill of `x` asks to spare a borrowed
    `Vec`'s held anchors at `x` (`HeldAnch`: a view of memory it holds, at
    an unfrozen root changed only strictly inside): the effect ends none. -/
def HeldSpared (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : Prop :=
  ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.root = x → HeldAnch E d →
    e.kills hv d.kind = false

/-- An effect that ends no view and no handle spares every held anchor. -/
theorem HeldSpared.of_kills {Γ : Ctx} {e : Eff} {hv : Bool} (x : Var) (hk : e.kills hv .view = false)
    (hks : e.kills hv .self = false) : HeldSpared Γ e hv x := by
  intro p E _ _ d _ _ ⟨_, _, _, hk'⟩
  rcases hk' with h | h <;> rw [h] <;> assumption

/-- A change strictly inside, ending no view (`hv = false`), spares them. -/
theorem HeldSpared.dropIn (Γ : Ctx) (x : Var) : HeldSpared Γ .dropIn false x :=
  HeldSpared.of_kills x rfl rfl

/-- A kill keeps what each binding depends on and holds, so it keeps
    `HeldSpared`. -/
theorem HeldSpared.of_kill {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : HeldSpared Γ e hv x)
    (e' : Eff) (hv' : Bool) (y : Var) : HeldSpared (A2.kill e' hv' y Γ) e hv x := by
  intro p E hp hm d hd hr ha
  simp only [A2.kill] at hp
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hp
  rw [killE_mode] at hm; rw [killE_vdeps] at hd
  exact h p E0 h0 hm d hd hr (HeldAnch.of_eq (killE_path ..).symm (killE_held ..).symm (killE_ty ..).symm ha)

/-- ... and a binding set to an entry that is no borrowed parameter. -/
theorem HeldSpared.of_setE {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : HeldSpared Γ e hv x)
    {y : Var} {E : Entry} (hE : E.mode ≠ .rootb) : HeldSpared (A2.setE Γ y E) e hv x := by
  intro p E' hp hm d hd hr ha
  by_cases hpy : p = y
  · subst hpy; simp only [A2.setE, upd_same, Option.some.injEq] at hp; subst hp; exact absurd hm hE
  · simp only [A2.setE, upd_ne _ _ hpy] at hp; exact h p E' hp hm d hd hr ha

theorem HeldSpared.of_killNames {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : HeldSpared Γ e hv x) :
    ∀ ds, HeldSpared (A2.killNames ds Γ) e hv x
  | [] => h
  | _ :: ds => show HeldSpared (A2.kill _ _ _ (A2.killNames ds Γ)) e hv x from
      (HeldSpared.of_killNames h ds).of_kill _ _ _

/-- AGORA-937 (3d, route U): a change through a borrow spares, at each
    memory root of its path, every held anchor there (its effect there, as
    `ThruOK` reads it). -/
def ThruSpared (Γ1 : Ctx) (op : Edit) (tx : Ty) (P : List Dep) : Prop :=
  ∀ d ∈ memDeps P, HeldSpared Γ1 (op.effAt d.kind (decide ((argE Γ1 d.root).ty = tx)) (argE Γ1 d.root).rvec)
    false d.root

/-- AGORA-937 (3d, route U): no borrowed `Vec` has a held anchor at `x`
    (what the invariant says of every binding the statement names). -/
def NoHeld (Γ : Ctx) (x : Var) : Prop :=
  ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.root = x → ¬ HeldAnch E d

/-- ... kept where the borrowed parameters keep their entries and every
    binding its mode. -/
theorem NoHeld.of_rootb {Γ Γ1 : Ctx} {y : Var} (h : NoHeld Γ y)
    (hcm : ∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty)
    (hrb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ1 p = some Ep) : NoHeld Γ1 y := by
  intro p E hp hm d hd hr ha
  obtain ⟨E0, h0, hm0, _⟩ := hcm p E hp
  rw [hm] at hm0
  have := hrb p E0 h0 hm0.symm
  rw [hp] at this; cases this
  exact h p _ h0 hm0.symm d hd hr ha

/-- No held anchor at `x`: every kill of it spares them. -/
theorem HeldSpared.of_none {Γ : Ctx} {x : Var} (h : NoHeld Γ x) (e : Eff) (hv : Bool) : HeldSpared Γ e hv x :=
  fun p E hp hm d hd hr ha => absurd ha (h p E hp hm d hd hr)


/-- ... kept where the borrowed parameters keep their entries and every
    binding its mode. -/
theorem RootbAnchF.of_rootb {Γ Γ1 : Ctx} {F : List Var} (h : RootbAnchF Γ F)
    (hcm : ∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty)
    (hrb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ1 p = some Ep) : RootbAnchF Γ1 F := by
  intro p E hp hm
  obtain ⟨E0, h0, hm0, _⟩ := hcm p E hp
  rw [hm] at hm0
  have := hrb p E0 h0 hm0.symm
  rw [hp] at this; cases this
  exact h p _ h0 hm0.symm

/-- With every anchor in `F`, a binding not lent out has no held anchor. -/
theorem NoHeld.of_anchF {Γ : Ctx} {F : List Var} (h : RootbAnchF Γ F) {x : Var} (hx : x ∉ F) : NoHeld Γ x :=
  fun p E hp hm d hd hr ha => hx (hr ▸ h p E hp hm d hd (by rcases ha.2.2.2 with h' | h' <;> rw [h'] <;> rfl))

/-- AGORA-937 (3d, route U, PR B2): a binding the running statement names
    (`V`, its variables) and not lent out has no held anchor: one's root is
    none of them (`AnchoredS`). -/
theorem NoHeld.of_anchS {Γ : Ctx} {F V : List Var} (h : RootbAnchS Γ F V) {x : Var} (hxV : x ∈ V)
    (hx : x ∉ F) : NoHeld Γ x :=
  fun p E hp hm d hd hr ha => by
    rcases h p E hp hm d hd (by rcases ha.2.2.2 with h' | h' <;> rw [h'] <;> rfl) with h1 | ⟨_, h2, _⟩
    · exact hx (hr ▸ h1)
    · exact h2 (hr ▸ hxV)

/-- ... read off any context's anchors (`Γ0`) of the borrowed parameters
    `Γ` binds: only where they are anchored counts. -/
theorem NoHeld.of_anchS0 {Γ Γ0 : Ctx} {F V : List Var}
    (h : ∀ p E, Γ p = some E → E.mode = .rootb → AnchoredS Γ0 E F V) {x : Var} (hxV : x ∈ V)
    (hx : x ∉ F) : NoHeld Γ x :=
  fun p E hp hm d hd hr ha => by
    rcases h p E hp hm d hd (by rcases ha.2.2.2 with h' | h' <;> rw [h'] <;> rfl) with h1 | ⟨_, h2, _⟩
    · exact hx (hr ▸ h1)
    · exact h2 (hr ▸ hxV)

/-- ... nor a binding not lent out whose type holds views: a held anchor's
    root's elements hold none (`AnchoredS`). -/
theorem NoHeld.of_anchS_hv {Γ : Ctx} {F V : List Var} (h : RootbAnchS Γ F V) {x : Var} {Ex : Entry}
    (hxe : Γ x = some Ex) (hv : Ex.ty.holdsView = true) (hx : x ∉ F) : NoHeld Γ x :=
  fun p E hp hm d hd hr ha => by
    rcases h p E hp hm d hd (by rcases ha.2.2.2 with h' | h' <;> rw [h'] <;> rfl) with h1 | ⟨_, _, Er, hEr, hnv⟩
    · exact hx (hr ▸ h1)
    · rw [hr, hxe] at hEr; cases hEr; rw [hv] at hnv; cases hnv

/-- What the rule's `HeldOK` says, as a kill's `HeldSpared` (`hv = false`). -/
theorem HeldSpared.of_heldOK {Γ : Ctx} {e : Eff} {r : Var} (h : HeldOK Γ e r) : HeldSpared Γ e false r :=
  fun p E hp hm d _ hr ha => h p E hp hm d ha.2.1 hr ha.2.2.2

/-- AGORA-937 (3d, route U, PR B2): a change through a borrow that stores
    a view (`editBV`) kills each root at `hv` = its type holds views
    (`killThruV`): it needs no held anchor only at those roots. -/
def NoHeldV (Γ1 : Ctx) (P : List Dep) : Prop :=
  ∀ d ∈ memDeps P, (argE Γ1 d.root).ty.holdsView = true → NoHeld Γ1 d.root

/-- ... so a change through a borrow, at roots not lent out (`ThruOK`),
    spares every held anchor. -/
theorem ThruSpared.of_anchF {Γ1 : Ctx} {F : List Var} (h : RootbAnchF Γ1 F) {op : Edit} {tx : Ty}
    {P : List Dep} (hthru : ThruOK Γ1 F op tx P) : ThruSpared Γ1 op tx P :=
  fun d hd => HeldSpared.of_none (NoHeld.of_anchF h (hthru d hd).1) _ _

/-- AGORA-937 (3d, route U): a change through a borrow the typing allows
    spares every held anchor at its roots (`ThruOK`'s `HeldOK`). -/
theorem ThruOK.spared {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {P : List Dep}
    (h : ThruOK Γ1 F op tx P) : ThruSpared Γ1 op tx P := by
  intro d hd p E hp hm d' hd' hr ha
  obtain ⟨_, _, Er, hEr, _, _, _, _, hho⟩ := h d hd
  have hae : argE Γ1 d.root = Er := by unfold argE; rw [hEr]; rfl
  rw [hae]
  exact hho p E hp hm d' ha.2.1 hr ha.2.2.2

/-- ... so the kill of each root spares every held anchor: at a root whose
    type holds no views `hv` is `false` and the rule's `HeldOK` spares them
    (`ThruOK.spared`); at one whose type holds views there is none. -/
theorem HeldSpared.of_thru {Γ1 : Ctx} {F : List Var} {op : Edit} {tx : Ty} {P : List Dep}
    (hthru : ThruOK Γ1 F op tx P) (hnoV : NoHeldV Γ1 P) {d : Dep} (hd : d ∈ memDeps P) :
    HeldSpared Γ1 (op.effAt d.kind (decide ((argE Γ1 d.root).ty = tx)) (argE Γ1 d.root).rvec)
      (argE Γ1 d.root).ty.holdsView d.root := by
  cases h : (argE Γ1 d.root).ty.holdsView
  · exact hthru.spared d hd
  · exact HeldSpared.of_none (hnoV d hd h) _ _

/-- The invariant's anchors give it: a root of a change through a borrow is
    not lent out (`ThruOK`). -/
theorem NoHeldV.of_anchS {Γ1 : Ctx} {F V : List Var} (h : RootbAnchS Γ1 F V) {op : Edit} {tx : Ty}
    {P : List Dep} (hthru : ThruOK Γ1 F op tx P) : NoHeldV Γ1 P := fun d hd hv => by
  obtain ⟨hF, _, Er, hEr, _⟩ := hthru d hd
  have hae : argE Γ1 d.root = Er := by unfold argE; rw [hEr]; rfl
  rw [hae] at hv
  exact NoHeld.of_anchS_hv h hEr hv hF

theorem killE_rootb {Γ : Ctx} {F : List Var}
    (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) (e : Eff) (hv : Bool)
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    (hhs : HeldSpared Γ e hv x)
    {v : Var} {E : Entry} (hE : Γ v = some E)
    (hrb : E.mode = .rootb) : killE e hv x E = E := by
  unfold killE
  have : hits e hv x E = false := by
    unfold hits
    simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
      beq_iff_eq, not_and, Bool.not_eq_true]
    refine Or.inr fun dep hd hr => ?_
    by_cases hb : dep.kind.bound = .none
    · rcases hanch v E hE hrb dep hd hb with h | ha
      · exact absurd (hr ▸ h) hxF
      · exact hhs v E hE hrb dep hd hr ha
    · cases hk : e.kills hv dep.kind
      · rfl
      · exact absurd hr (hmn v E hE hrb dep hd hb hk)
  rw [this]; rfl

/-- AGORA-937: what a kill of `x` asks to spare a borrowed parameter's
    views of a region: `x` is no region, or the effect ends no view. -/
def RegionSpared (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : Prop :=
  (∃ Ex, Γ x = some Ex ∧ Ex.mode = .region) → e.kills hv .view = false

/-- An effect that spares a view spares the handle too (AGORA-937: a lent
    parameter holds its region by its handle, `regionP`). -/
theorem Eff.kills_self_of_view {e : Eff} {hv : Bool} (h : e.kills hv .view = false) :
    e.kills hv .self = false := by
  cases e <;> cases hv <;> simp_all [Eff.kills]

theorem RegionSpared.of_ne {Γ : Ctx} {x : Var} {Ex : Entry} (hx : Γ x = some Ex) (hm : Ex.mode ≠ .region)
    (e : Eff) (hv : Bool) : RegionSpared Γ e hv x := fun ⟨E, h, hr⟩ => by
  rw [hx] at h; cases h; exact absurd hr hm

/-- A kill keeps every binding's mode, so what is a region stays one. -/
theorem RegionSpared.of_kill {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : RegionSpared Γ e hv x)
    (e' : Eff) (hv' : Bool) (y : Var) : RegionSpared (A2.kill e' hv' y Γ) e hv x := fun ⟨Ex, hx, hr⟩ => by
  simp only [A2.kill] at hx
  obtain ⟨E0, h0, rfl⟩ := Option.map_eq_some_iff.mp hx
  exact h ⟨E0, h0, by rwa [killE_mode] at hr⟩

theorem RegionSpared.of_killNames {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} (h : RegionSpared Γ e hv x) :
    ∀ ds, RegionSpared (A2.killNames ds Γ) e hv x
  | [] => h
  | _ :: ds => show RegionSpared (A2.kill _ _ _ (A2.killNames ds Γ)) e hv x from
      (RegionSpared.of_killNames h ds).of_kill _ _ _

/-- `killE_rootb` where a borrowed parameter may view a region
    (`RootbAnchR`): a kill of a region ends no view (`RegionSpared`).
    AGORA-937 (3d, route U, PR B2): ... and a lent `Vec`'s held anchor at
    `x`, which the kill spares (`HeldSpared`). -/
theorem killE_rootbRH {Γ : Ctx} {F : List Var}
    (hanch : RootbAnchRH Γ F)
    {x : Var} (hxF : x ∉ F) (e : Eff) (hv : Bool)
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    (hxr : RegionSpared Γ e hv x) (hxh : HeldSpared Γ e hv x)
    {v : Var} {E : Entry} (hE : Γ v = some E)
    (hrb : E.mode = .rootb) : killE e hv x E = E := by
  unfold killE
  have : hits e hv x E = false := by
    unfold hits
    simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
      beq_iff_eq, not_and, Bool.not_eq_true]
    refine Or.inr fun dep hd hr => ?_
    by_cases hb : dep.kind.bound = .none
    · rcases hanch v E hE hrb dep hd hb with h | ⟨hk, Er, hEr, hreg⟩ | ha
      · exact absurd (hr ▸ h) hxF
      · rw [hk]; exact Eff.kills_self_of_view (hxr ⟨Er, hr ▸ hEr, hreg⟩)
      · exact hxh v E hE hrb dep hd hr ha
    · cases hk : e.kills hv dep.kind
      · rfl
      · exact absurd hr (hmn v E hE hrb dep hd hb hk)
  rw [this]; rfl

/-- With the anchors in `F` or on regions, a binding not lent out has a held
    anchor only as a view of a region, which a kill that spares the region
    spares. -/
theorem HeldSpared.of_anchR {Γ : Ctx} {F : List Var} (hanch : RootbAnchR Γ F) {x : Var} (hxF : x ∉ F)
    {e : Eff} {hv : Bool} (hxr : RegionSpared Γ e hv x) : HeldSpared Γ e hv x := by
  intro p E hp hm d hd hr ha
  have hb : d.kind.bound = .none := by rcases ha.2.2.2 with h' | h' <;> rw [h'] <;> rfl
  rcases hanch p E hp hm d hd hb with h | ⟨hk, Er, hEr, hreg⟩
  · exact absurd (hr ▸ h) hxF
  · rw [hk]; exact Eff.kills_self_of_view (hxr ⟨Er, hr ▸ hEr, hreg⟩)

theorem killE_rootbR {Γ : Ctx} {F : List Var}
    (hanch : RootbAnchR Γ F)
    {x : Var} (hxF : x ∉ F) (e : Eff) (hv : Bool)
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    (hxr : RegionSpared Γ e hv x)
    {v : Var} {E : Entry} (hE : Γ v = some E)
    (hrb : E.mode = .rootb) : killE e hv x E = E :=
  killE_rootbRH hanch.toRH hxF e hv hmn hxr (HeldSpared.of_anchR hanch hxF hxr) hE hrb

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

/-- AGORA-901: what a change of `x` (effect `e`, its slot becoming `ox`)
    must show for `MInv.pkgFree`: no package of `x`'s new tree holds the node
    a borrow the change leaves live names, and, if `x` is itself such a
    borrow, no package of any owned tree holds its node.  (Every other owned
    tree is as it was.) -/
def PkgKeep (m m' : Mem) (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) (ox : Option Entry) : Prop :=
  (∀ y Ey o v, y ≠ x → Γ y = some Ey → Alive (killE e hv x Ey) → m.st y = some ⟨o, some v⟩ →
    ∀ i, PkgNames m' Γ Ey v i → PkgFreeId m' i) ∧
  (∀ Ex' o v, ox = some Ex' → Alive Ex' → m'.st x = some ⟨o, some v⟩ →
    ∀ i, PkgNames m' Γ Ex' v i → PkgFreeId m' i)

theorem Alive.of_killE {e : Eff} {hv : Bool} {x : Var} {E : Entry} (h : Alive (killE e hv x E)) : Alive E := by
  rcases h with h | ⟨hd, ho⟩
  · rw [killE_live] at h; simp only [Bool.and_eq_true] at h; exact Or.inl h.1
  · exact Or.inr ⟨by rw [← killE_dbind e hv x]; exact hd, by rw [← killE_mode e hv x]; exact ho⟩

/-- A borrow a kill ends is no longer alive. -/
theorem Alive.killed {e : Eff} {hv : Bool} {x : Var} {E : Entry} (h : Alive (killE e hv x E))
    (hhit : hits e hv x E = true) (hos : E.mode.ownSlot = false) : False := by
  rcases h with h | ⟨_, ho⟩
  · rw [killE_live, hhit] at h; simp at h
  · rw [killE_mode, hos] at ho; cases ho

/-- What an entry names its kill names. -/
theorem PkgNames.of_killE {m : Mem} {Γ : Ctx} {e : Eff} {hv : Bool} {x : Var} {E : Entry} {v : Val} {i : Nat}
    (h : PkgNames m Γ (killE e hv x E) v i) : PkgNames m Γ E v i :=
  h.weaken (killE_mode ..) (fun _ d hd => by rw [killE_path]; exact hd)
    (fun d hd => by rw [killE_held]; exact (List.mem_filter.mp hd).1)

/-- What no package of an owned tree holds stays so when only `x`'s tree
    changes, to one whose packages its old tree held. -/
theorem PkgFreeId.frame {m m' : Mem} {x : Var} (hst : ∀ o, o ≠ x → m'.st o = m.st o)
    (hpk : ∀ T', m'.st x = some ⟨true, some T'⟩ → ∀ fs te ms ev cs, Sub (.pkg fs te ms ev cs) T' →
      ∃ T, m.st x = some ⟨true, some T⟩ ∧ Sub (.pkg fs te ms ev cs) T)
    {i : Nat} (h : PkgFreeId m i) : PkgFreeId m' i := by
  intro r T' hT' fs te ms ev cs hP
  by_cases hrx : r = x
  · subst hrx
    obtain ⟨T, hT, hP'⟩ := hpk T' hT' fs te ms ev cs hP
    exact h r T hT fs te ms ev cs hP'
  · rw [hst r hrx] at hT'; exact h r T' hT' fs te ms ev cs hP

/-- AGORA-901: a change of `x`, not a borrowed parameter, keeps the clean
    roots: modes are kept, and a borrowed parameter no kill ends. -/
theorem Clean.of_change {Γ : Ctx} {F : List Var} (_hanch : RootbAnch Γ F) {x : Var} {Ex : Entry}
    (hx : Γ x = some Ex) (hxF : x ∉ F) {e : Eff} {hv : Bool}
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    (hxr : Ex.mode ≠ .rootb) {ox : Option Entry} (hox : ∀ E', ox = some E' → E'.mode = Ex.mode)
    : CleanLe (upd (kill e hv x Γ) x ox) Γ :=
  CleanLe.of_entries fun v E' hv' => by
    by_cases hvx : v = x
    · subst hvx
      simp only [upd_same] at hv'
      exact ⟨Ex, hx, hox E' hv', fun h => absurd h hxr⟩
    · rw [upd_ne _ _ hvx] at hv'
      unfold kill at hv'
      cases hE : Γ v with
      | none => rw [hE] at hv'; cases hv'
      | some E =>
        rw [hE] at hv'; cases hv'
        exact ⟨E, rfl, killE_mode .., fun _ => ⟨killE_path .., killE_held ..⟩⟩

/-- AGORA-901: a kill keeps the clean roots: modes are kept, and a borrowed
    parameter it ends none of. -/
theorem Clean.of_kill {Γ : Ctx} {F : List Var} (_hanch : RootbAnch Γ F) {x : Var} (_hxF : x ∉ F)
    {e : Eff} {hv : Bool}
    (_hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    : CleanLe (kill e hv x Γ) Γ :=
  CleanLe.of_entries fun v E' hv' => by
    unfold kill at hv'
    cases hE : Γ v with
    | none => rw [hE] at hv'; cases hv'
    | some E =>
      rw [hE] at hv'; cases hv'
      exact ⟨E, rfl, killE_mode .., fun _ => ⟨killE_path .., killE_held ..⟩⟩

/-- AGORA-901: the clean roots of a context whose entries keep their modes
    and paths (a kill, a weakening of what is held) are the other's. -/
theorem Clean.of_same {Γ Γ' : Ctx}
    (h : ∀ v E', Γ' v = some E' → ∃ E, Γ v = some E ∧ E'.mode = E.mode ∧ E'.path = E.path ∧
      (E.mode = .rootb → E'.held = E.held)) : CleanLe Γ' Γ :=
  CleanLe.of_entries fun v E' hv => by
    obtain ⟨E, hE, hm, hp, hh⟩ := h v E' hv
    exact ⟨E, hE, hm, fun hr => ⟨hp, hh hr⟩⟩

theorem kill_back {Γ : Ctx} {e : Eff} {hv : Bool} {x v : Var} {E' : Entry} (h : kill e hv x Γ v = some E') :
    ∃ E, Γ v = some E ∧ E'.mode = E.mode ∧ E'.path = E.path ∧ E'.held = E.held := by
  unfold kill at h
  cases hE : Γ v with
  | none => rw [hE] at h; cases h
  | some E => rw [hE] at h; cases h; exact ⟨E, rfl, killE_mode .., killE_path .., killE_held ..⟩

theorem killNames_back {Γ : Ctx} : ∀ (ds : List Dep) {v : Var} {E' : Entry}, killNames ds Γ v = some E' →
    ∃ E, Γ v = some E ∧ E'.mode = E.mode ∧ E'.path = E.path ∧ E'.held = E.held
  | [], _, E', h => ⟨E', h, rfl, rfl, rfl⟩
  | d :: ds, v, E', h => by
    obtain ⟨E1, h1, hm1, hp1, hh1⟩ := kill_back (Γ := killNames ds Γ) h
    obtain ⟨E, h0, hm0, hp0, hh0⟩ := killNames_back ds h1
    exact ⟨E, h0, hm1.trans hm0, hp1.trans hp0, hh1.trans hh0⟩

/-- A node whose elements are among another's: what lies strictly below it
    lies below that one. -/
theorem node_sub_sub {t : Ty} {c d d' : Nat} {es es' : List Val} (h : ∀ e ∈ es', e ∈ es) {P : Val}
    (hs : Sub P (.node t c d' es')) : P = .node t c d' es' ∨ Sub P (.node t c d es) := by
  cases hs with
  | refl => exact Or.inl rfl
  | child he h' => exact Or.inr (Sub.child (h _ he) h')

/-- **A change of an owner `x` within its own tree**: its new tree holds
    only packages its old tree held, each of its nodes is at the address of
    one of the old tree's, and every view the new tree stores is one the old
    tree stored at that place, or one of an address no package holds.  It
    keeps what `MInv.pkgFree` asks. -/
theorem PkgKeep.of_pkgs {m m' : Mem} {Γ : Ctx} (hi : MInv m Γ) {e : Eff} {hv : Bool} {x : Var}
    {Ex : Entry} {ox : Option Entry} (hx : Γ x = some Ex) (hos : Ex.mode.ownSlot = true)
    (hox : ∀ Ex', ox = some Ex' → Ex'.mode = Ex.mode ∧ Ex.held ⊆ Ex'.held ∧ (Alive Ex' → Alive Ex))
    {T : Val} (hT : m.st x = some ⟨true, some T⟩) (hst : ∀ o, o ≠ x → m'.st o = m.st o)
    (hpk : ∀ T', m'.st x = some ⟨true, some T'⟩ → ∀ fs te ms ev cs,
      Sub (.pkg fs te ms ev cs) T' → Sub (.pkg fs te ms ev cs) T)
    (hvw : ∀ o T', m'.st x = some ⟨o, some T'⟩ → ∀ i o' l, Sub (.view i o' l) T' →
      Sub (.view i o' l) T ∨ PkgFreeId m i)
    (hnode : ∀ T', m'.st x = some ⟨true, some T'⟩ → ∀ t c d es, Sub (.node t c d es) T' →
      ∃ t0 d0 es0, Sub (.node t0 c d0 es0) T ∧ ∀ i o l, Sub (.view i o l) (.node t c d es) →
        Sub (.view i o l) (.node t0 c d0 es0) ∨ PkgFreeId m i) :
    PkgKeep m m' Γ e hv x ox := by
  have hfr : ∀ i, PkgFreeId m i → PkgFreeId m' i := fun i h =>
    h.frame hst fun T' hT' fs te ms ev cs hP => ⟨T, hT, hpk T' hT' fs te ms ev cs hP⟩
  -- a node of an owned tree of the new store is at the address of one of the
  -- old's, its views the old one's or of addresses no package holds
  have hat : ∀ r T1 t c d es, m'.st r = some ⟨true, some T1⟩ → Sub (.node t c d es) T1 →
      ∃ r0 T0 t0 d0 es0, m.st r0 = some ⟨true, some T0⟩ ∧ Sub (.node t0 c d0 es0) T0 ∧
        ∀ i o l, Sub (.view i o l) (.node t c d es) → Sub (.view i o l) (.node t0 c d0 es0) ∨ PkgFreeId m i := by
    intro r T1 t c d es hT1 hs1
    by_cases hrx : r = x
    · subst hrx
      obtain ⟨t0, d0, es0, hs0, hv0⟩ := hnode T1 hT1 t c d es hs1
      exact ⟨r, T, t0, d0, es0, hT, hs0, hv0⟩
    · rw [hst r hrx] at hT1
      exact ⟨r, T1, t, d, es, hT1, hs1, fun _ _ _ h => Or.inl h⟩
  refine ⟨fun y Ey o v hyx hEy hl hs i hn => ?_, fun Ex' o v hx' hl hs i hn => ?_⟩
  · have hla := hl.of_killE
    rcases hn with h1 | h2 | ⟨hm, hc, c, r, T1, t, d, es, hb, hT1, hs1, o', l, hvn⟩ | ⟨hm, hc, o', l, hvn⟩
    · exact hfr i (hi.pkgFree y Ey o v hEy hla hs i (Or.inl h1))
    · exact hfr i (hi.pkgFree y Ey o v hEy hla hs i (Or.inr (Or.inl h2)))
    · obtain ⟨r0, T0, t0, d0, es0, hT0, hs0, hvw0⟩ := hat r T1 t c d es hT1 hs1
      rcases hvw0 i o' l hvn with hvn0 | hf
      · exact hfr i (hi.pkgFree y Ey o v hEy hla hs i
          (Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r0, T0, t0, d0, es0, hb, hT0, hs0, o', l, hvn0⟩))))
      · exact hfr i hf
    · exact hfr i (hi.pkgFree y Ey o v hEy hla hs i (Or.inr (Or.inr (Or.inr ⟨hm, hc, o', l, hvn⟩))))
  · obtain ⟨hm, hhd, hlv⟩ := hox Ex' hx'
    have hnb : ¬ (Ex'.mode = .bor ∨ Ex'.mode = .rootb) := by
      rw [hm]; rintro (h | h) <;> rw [h] at hos <;> cases hos
    rcases hn with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩ | ⟨_, hc, o', l, hvn⟩
    · exact absurd h hnb
    · exact absurd h hnb
    · exact absurd h hnb
    · rcases hvw o v hs i o' l hvn with hvn0 | hf
      · exact hfr i (hi.pkgFree x Ex true T hx (hlv hl) hT i
          (Or.inr (Or.inr (Or.inr ⟨hos, hc.sub hhd, o', l, hvn0⟩))))
      · exact hfr i hf

/-- A change that leaves `x` holding no value keeps what `MInv.pkgFree` asks. -/
theorem PkgKeep.noval {m m' : Mem} {Γ : Ctx} (hi : MInv m Γ) {e : Eff} {hv : Bool} {x : Var}
    {ox : Option Entry} (hst : ∀ o, o ≠ x → m'.st o = m.st o)
    (h : ∀ o v, m'.st x ≠ some ⟨o, some v⟩) : PkgKeep m m' Γ e hv x ox := by
  have hfr : ∀ i, PkgFreeId m i → PkgFreeId m' i := fun i hf =>
    hf.frame hst fun T' hT' => absurd hT' (h _ _)
  refine ⟨fun y Ey o v hyx hEy hl hs i hn => ?_, fun _ _ _ _ _ hs => absurd hs (h _ _)⟩
  have hla := hl.of_killE
  rcases hn with h1 | h2 | ⟨hm, hc, c, r, T1, t, d, es, hb, hT1, hs1, hvn⟩ | h4
  · exact hfr i (hi.pkgFree y Ey o v hEy hla hs i (Or.inl h1))
  · exact hfr i (hi.pkgFree y Ey o v hEy hla hs i (Or.inr (Or.inl h2)))
  · have hrx : r ≠ x := fun hr => h _ _ (hr ▸ hT1)
    exact hfr i (hi.pkgFree y Ey o v hEy hla hs i
      (Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, T1, t, d, es, hb, by rw [← hst r hrx]; exact hT1, hs1, hvn⟩))))
  · exact hfr i (hi.pkgFree y Ey o v hEy hla hs i (Or.inr (Or.inr (Or.inr h4))))

/-- A kill that ends every dependency inside an element by index leaves
    none in a live entry; and an armed one, which an effect `e'` that ends
    them too spares (`DtorSafe` of the killed context), has none either
    (AGORA-374). -/
theorem NoIdx.of_kill {Γ : Ctx} {e e' : Eff} {hv hv' : Bool} {x : Var}
    (hk : ∀ i, e.kills hv (.innerAt i) = true) (hk' : ∀ i, e'.kills hv' (.innerAt i) = true)
    (hds : DtorSafe (A2.kill e hv x Γ) e' hv' x) :
    NoIdx (A2.kill e hv x Γ) x := by
  rintro k ⟨v, E', hE', hn, hl, hd⟩ i rfl
  rcases hl with hl | ⟨hdt, hos⟩
  · simp only [A2.kill] at hE'
    cases hE : Γ v with
    | none => rw [hE] at hE'; cases hE'
    | some E =>
      rw [hE] at hE'; simp only [Option.map_some, Option.some.injEq] at hE'; subst hE'
      rw [killE_ty, killE_mode] at hn
      rw [killE_vdeps] at hd
      obtain ⟨_, hnot⟩ := killE_live_dep hl hn
      have := hnot _ hd rfl; rw [hk i] at this; cases this
  · have hm := hds v E' hE' hdt hos
    unfold hitsMem at hm
    have : (E'.ty != .int || E'.mode == .rootb) = true := by
      rcases hn with h | h <;> simp [h]
    rw [this, Bool.true_and] at hm
    have hany : E'.vdeps.any (fun d => d.root == x && !d.kind.isName && e'.kills hv' d.kind) = true :=
      List.any_eq_true.mpr ⟨_, hd, by simp [Kind.isName, hk' i]⟩
    rw [hany] at hm; cases hm

/-- AGORA-374: a binding set to an entry that depends on `x` inside no
    element by index keeps a context free of such dependencies. -/
theorem NoIdx.setE {Γ : Ctx} {x y : Var} {E : Entry} (h : NoIdx Γ x)
    (hE : ∀ d ∈ E.vdeps, d.root = x → d.kind.isIdx = false) : NoIdx (setE Γ y E) x := by
  rintro k ⟨v, E', hE', hn, hl, hd⟩ i rfl
  by_cases hv : v = y
  · subst hv
    have hEE : E' = E := by unfold A2.setE at hE'; rw [upd_same] at hE'; exact (Option.some.inj hE').symm
    subst hEE
    have := hE _ hd rfl; simp [Kind.isIdx] at this
  · unfold A2.setE at hE'; rw [upd_ne _ _ hv] at hE'
    exact h _ ⟨v, E', hE', hn, hl, hd⟩ i rfl

/-- One binding `x` changes (effect `e`), its slot becomes `ox`: every other
    binding stays valid, or is ended by `kill`. -/
theorem MInv.change {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} {Ex : Entry} (hx : Γ x = some Ex) (hxF : x ∉ F) {e : Eff} {hv : Bool}
    (hmn : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ d ∈ E.vdeps, d.kind.bound ≠ .none →
      e.kills hv d.kind = true → d.root ≠ x)
    (hhs : HeldSpared Γ e hv x)
    (hxr : Ex.mode ≠ .rootb)
    (hst : ∀ o, o ≠ x → m'.st o = m.st o) (hheap : HeapOK m') (hnv : m'.nv = m.nv)
    (hkeep : ∀ k, e.kills hv k = false → KindUsed Γ x k → VKeep m m' ⟨x, k⟩ ∧ HKeep m m' ⟨x, k⟩)
    {ox : Option Entry} (hox : NewSlot m' (kill e hv x Γ) x Ex ox)
    (hds : DtorSafe Γ e hv x)
    (hdb : ox = none → DbindSafe Γ x)
    (hrem : ox = none → e = .replace)
    (hnew : e ≠ .replace → ∀ Ex', ox = some Ex' → Ex.live = true → Ex.held = [] →
      Ex.ty.holdsView = false → Ex'.live = true ∧ Ex'.held = [])
    (hpk : PkgKeep m m' Γ e hv x ox)
    (hblk : m'.blk = m.blk := by rfl) :
    MInv m' (upd (kill e hv x Γ) x ox) := by
  have depKeep : ∀ v E, Γ v = some E → (killE e hv x E).live = true → E.ty ≠ .int →
      ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep := by
    intro v E hv' hl hnint dep hd
    obtain ⟨hlE, hnot⟩ := killE_live_dep hl (Or.inl hnint)
    by_cases hr : dep.root = x
    · obtain ⟨r, k⟩ := dep
      simp only at hr; subst hr
      exact hkeep k (hnot _ hd rfl) ⟨v, E, hv', Or.inl hnint, Or.inl hlE, hd⟩
    · obtain ⟨Er, hEr, hroot⟩ := hi.wf v E hv' hlE (Or.inl hnint) dep.root (List.mem_map_of_mem hd)
      have hk := rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot
        (hst _ hr) (BlkLe.of_eq hblk)
      exact ⟨hk.vkeep (BlkLe.of_eq hblk), hk.hkeep⟩
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
        · rw [killE_rootb hanch hxF e hv hmn hhs hE hrb] at hdead
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
  · intro v E' hv'
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨_, _, _, _, hm, _⟩ := hox
      rw [hm]; exact hi.noRegion v Ex hx
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [killE_mode]; exact hi.noRegion v E hE
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
            · rcases hanch v E hE hrb dep hd hb with h | ha
              · exact hxF h
              · have := hhs v E hE hrb dep hd rfl ha
                rw [hrem rfl] at this; cases hk : dep.kind <;> rw [hk] at this <;> simp [Eff.kills] at this
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
      rw [killE_rootb hanch hxF e hv hmn hhs hE hm]
      exact hi.rootbLive p E hE hm
  · intro p E' hp' hm
    by_cases hpx : p = x
    · subst hpx
      have := getX E' hp'; subst this
      obtain ⟨_, _, _, _, hm', _⟩ := hox
      exact absurd (hm' ▸ hm) hxr
    · obtain ⟨E, hE, rfl⟩ := getE p E' hp' hpx
      rw [killE_mode] at hm
      rw [killE_rootb hanch hxF e hv hmn hhs hE hm]
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
  · -- Agora #909: the new slot's entry is fresh in the new context; an emptied
    -- slot ended the fresh borrows through it (a replace)
    cases ox with
    | none => rw [hrem rfl]; exact hi.fresh.remove hv x
    | some Ex' =>
      obtain ⟨_, _, _, _, hmx, _, _, _, _, _, _, _, _, _, _, hfx, _⟩ := hox
      exact (hi.fresh.kill e hv x).setE hfx (fun Ek hEk hm => by
        simp [A2.kill, hx] at hEk; rw [← hEk, killE_mode] at hm; rw [hmx]; exact hm)
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
  · -- AGORA-937 B4: a slot holds no package capturing by name unless its type says so
    intro v E' sl T hv' hsl hT hfn
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, _, _, _, _, _, _, _, _, hnp⟩ := hox
      rw [hsl'] at hsl; cases hsl; exact hnp hfn T hT
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [hst v hvx] at hsl
      exact hi.noPkg v E sl T hE hsl hT (by rw [killE_ty] at hfn; exact hfn)
  · -- A2-drop.2: no view of an armed binding is one the change ends (`DtorSafe`)
    intro v E' sl hv' hsl
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, _, _, _, _, _, harm, _⟩ := hox
      rw [hsl'] at hsl; cases hsl; exact harm
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [hst v hvx] at hsl
      refine ArmOK.entry (killE_dbind ..) (killE_ty ..) (killE_mode ..) (fun h => by rw [killE_dtor]; exact h)
        (by rw [killE_held]; exact fun d hd => (List.mem_filter.mp hd).1) ?_
      refine (hi.armed v E sl hE hsl).keep (hb := BlkLe.of_eq hblk) fun hdt hd hos dep hdm => ?_
      have hdm' := List.mem_filter.mp hdm
      have hnm : dep.kind.isName = false := by simpa using hdm'.2
      have hdv : dep ∈ E.vdeps := by unfold Entry.vdeps; exact List.mem_append_right _ hdm'.1
      have hnint : E.ty ≠ .int := fun h => by have := hi.wf.view v E hE hd; rw [h] at this; cases this
      by_cases hr : dep.root = x
      · obtain ⟨r, k⟩ := dep
        simp only at hr; subst hr
        exact (hkeep k (hitsMem_kills (hds v E hE hdt hos) (Or.inl hnint) hdv rfl hnm) ⟨v, E, hE, Or.inl hnint, Or.inr ⟨hdt, hos⟩, hdv⟩).1
      · obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor v E hE hd hos (Or.inl hnint) dep hdv hnm
        exact (rootKeep_frame hi hanch (fun o ho => hst o (fun h => hxF (h ▸ ho))) hEr hroot (hst _ hr)
          (BlkLe.of_eq hblk)).vkeep (BlkLe.of_eq hblk)
  · -- A3.1: an owned tree's shares name live blocks; no change here touches a block
    intro v E' sl T hv' hsl hown hT
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, _, _, _, _, _, _, hsh, _⟩ := hox
      rw [hsl'] at hsl; cases hsl; exact hsh hown T hT
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [hst v hvx] at hsl
      rw [killE_ty]; exact (hi.shares v E sl T hE hsl hown hT).of_blk hblk
  · intro k bl hk
    rw [hblk] at hk
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k bl hk
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.of_blk hblk⟩, h4⟩
  · -- AGORA-901: the borrows the change leaves name nodes no package holds
    have hcl : CleanLe (upd (kill e hv x Γ) x ox) Γ := CleanLe.of_entries fun v E' hv' => by
      by_cases hvx : v = x
      · subst hvx
        have := getX E' hv'; subst this
        obtain ⟨_, _, _, _, hm, _⟩ := hox
        exact ⟨Ex, hx, hm, fun h => absurd h hxr⟩
      · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
        exact ⟨E, hE, killE_mode .., fun _ => ⟨killE_path .., killE_held ..⟩⟩
    intro y Ey' o v hy hl hs i hn
    have hn0 : PkgNames m' Γ Ey' v i := hn.mono hcl
    by_cases hyx : y = x
    · subst hyx
      exact hpk.2 Ey' o v (getX Ey' hy) hl hs i hn0
    · obtain ⟨Ey, hEy, rfl⟩ := getE y Ey' hy hyx
      rw [hst y hyx] at hs
      exact hpk.1 y Ey o v hyx hEy hl hs i hn0.of_killE

/-! ### AGORA-901: a fresh binding -/

/-- AGORA-937 (3d, route F): `MInv.change` where `x` may be frozen: no
    borrowed parameter's memory lies in `x`'s tree (`rootKeep_frame_ne`), and
    the change ends none (`hnr`, what `killE_rootb` got from `x ∉ F`). -/
theorem MInv.change_ne {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    {x : Var} {Ex : Entry} (hx : Γ x = some Ex) {e : Eff} {hv : Bool}
    (hxa : ∀ p E, Γ p = some E → E.mode = .rootb →
      (∀ d ∈ E.path, d.root = x → d.kind.bound ≠ .none) ∧
      ((∀ t, E.ty ≠ .vec t) → ∀ d ∈ E.held, d.root = x → d.kind.bound ≠ .none))
    (hnr : ∀ p E, Γ p = some E → E.mode = .rootb → hits e hv x E = false)
    (hxr : Ex.mode ≠ .rootb)
    (hst : ∀ o, o ≠ x → m'.st o = m.st o) (hheap : HeapOK m') (hnv : m'.nv = m.nv)
    (hkeep : ∀ k, e.kills hv k = false → KindUsed Γ x k → VKeep m m' ⟨x, k⟩ ∧ HKeep m m' ⟨x, k⟩)
    {ox : Option Entry} (hox : NewSlot m' (kill e hv x Γ) x Ex ox)
    (hds : DtorSafe Γ e hv x)
    (hdb : ox = none → DbindSafe Γ x)
    (hrem : ox = none → e = .replace)
    (hnew : e ≠ .replace → ∀ Ex', ox = some Ex' → Ex.live = true → Ex.held = [] →
      Ex.ty.holdsView = false → Ex'.live = true ∧ Ex'.held = [])
    (hpk : PkgKeep m m' Γ e hv x ox)
    (hblk : m'.blk = m.blk := by rfl) :
    MInv m' (upd (kill e hv x Γ) x ox) := by
  have depKeep : ∀ v E, Γ v = some E → (killE e hv x E).live = true → E.ty ≠ .int →
      ∀ dep ∈ E.vdeps, VKeep m m' dep ∧ HKeep m m' dep := by
    intro v E hv' hl hnint dep hd
    obtain ⟨hlE, hnot⟩ := killE_live_dep hl (Or.inl hnint)
    by_cases hr : dep.root = x
    · obtain ⟨r, k⟩ := dep
      simp only at hr; subst hr
      exact hkeep k (hnot _ hd rfl) ⟨v, E, hv', Or.inl hnint, Or.inl hlE, hd⟩
    · obtain ⟨Er, hEr, hroot⟩ := hi.wf v E hv' hlE (Or.inl hnint) dep.root (List.mem_map_of_mem hd)
      have hk := rootKeep_frame_ne hi hanch hxa (fun o _ hox => hst o hox) hEr hroot
        (hst _ hr) (BlkLe.of_eq hblk)
      exact ⟨hk.vkeep (BlkLe.of_eq hblk), hk.hkeep⟩
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
        · rw [show killE e hv x E = E by unfold killE; rw [hnr v E hE hrb]; rfl] at hdead
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
  · intro v E' hv'
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨_, _, _, _, hm, _⟩ := hox
      rw [hm]; exact hi.noRegion v Ex hx
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [killE_mode]; exact hi.noRegion v E hE
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
          · have h0 := hnr v E hE hrb
            rw [hrem rfl] at h0
            unfold hits at h0
            simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, not_and,
              Bool.not_eq_true] at h0
            rcases h0 with h0 | h0
            · rw [hrb] at h0; simp at h0
            · have := h0 dep hd rfl; cases hk : dep.kind <;> rw [hk] at this <;> simp [Eff.kills] at this
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
      rw [show killE e hv x E = E by unfold killE; rw [hnr p E hE hm]; rfl]
      exact hi.rootbLive p E hE hm
  · intro p E' hp' hm
    by_cases hpx : p = x
    · subst hpx
      have := getX E' hp'; subst this
      obtain ⟨_, _, _, _, hm', _⟩ := hox
      exact absurd (hm' ▸ hm) hxr
    · obtain ⟨E, hE, rfl⟩ := getE p E' hp' hpx
      rw [killE_mode] at hm
      rw [show killE e hv x E = E by unfold killE; rw [hnr p E hE hm]; rfl]
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
  · -- Agora #909: the new slot's entry is fresh in the new context; an emptied
    -- slot ended the fresh borrows through it (a replace)
    cases ox with
    | none => rw [hrem rfl]; exact hi.fresh.remove hv x
    | some Ex' =>
      obtain ⟨_, _, _, _, hmx, _, _, _, _, _, _, _, _, _, _, hfx, _⟩ := hox
      exact (hi.fresh.kill e hv x).setE hfx (fun Ek hEk hm => by
        simp [A2.kill, hx] at hEk; rw [← hEk, killE_mode] at hm; rw [hmx]; exact hm)
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
  · -- AGORA-937 B4: a slot holds no package capturing by name unless its type says so
    intro v E' sl T hv' hsl hT hfn
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, _, _, _, _, _, _, _, _, hnp⟩ := hox
      rw [hsl'] at hsl; cases hsl; exact hnp hfn T hT
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [hst v hvx] at hsl
      exact hi.noPkg v E sl T hE hsl hT (by rw [killE_ty] at hfn; exact hfn)
  · -- A2-drop.2: no view of an armed binding is one the change ends (`DtorSafe`)
    intro v E' sl hv' hsl
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, _, _, _, _, _, harm, _⟩ := hox
      rw [hsl'] at hsl; cases hsl; exact harm
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [hst v hvx] at hsl
      refine ArmOK.entry (killE_dbind ..) (killE_ty ..) (killE_mode ..) (fun h => by rw [killE_dtor]; exact h)
        (by rw [killE_held]; exact fun d hd => (List.mem_filter.mp hd).1) ?_
      refine (hi.armed v E sl hE hsl).keep (hb := BlkLe.of_eq hblk) fun hdt hd hos dep hdm => ?_
      have hdm' := List.mem_filter.mp hdm
      have hnm : dep.kind.isName = false := by simpa using hdm'.2
      have hdv : dep ∈ E.vdeps := by unfold Entry.vdeps; exact List.mem_append_right _ hdm'.1
      have hnint : E.ty ≠ .int := fun h => by have := hi.wf.view v E hE hd; rw [h] at this; cases this
      by_cases hr : dep.root = x
      · obtain ⟨r, k⟩ := dep
        simp only at hr; subst hr
        exact (hkeep k (hitsMem_kills (hds v E hE hdt hos) (Or.inl hnint) hdv rfl hnm) ⟨v, E, hE, Or.inl hnint, Or.inr ⟨hdt, hos⟩, hdv⟩).1
      · obtain ⟨Er, hEr, hroot⟩ := hi.wf.dtor v E hE hd hos (Or.inl hnint) dep hdv hnm
        exact (rootKeep_frame_ne hi hanch hxa (fun o _ hox => hst o hox) hEr hroot (hst _ hr)
          (BlkLe.of_eq hblk)).vkeep (BlkLe.of_eq hblk)
  · -- A3.1: an owned tree's shares name live blocks; no change here touches a block
    intro v E' sl T hv' hsl hown hT
    by_cases hvx : v = x
    · subst hvx
      have := getX E' hv'; subst this
      obtain ⟨sl', hsl', _, _, _, _, _, _, _, _, _, _, _, _, hsh, _⟩ := hox
      rw [hsl'] at hsl; cases hsl; exact hsh hown T hT
    · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
      rw [hst v hvx] at hsl
      rw [killE_ty]; exact (hi.shares v E sl T hE hsl hown hT).of_blk hblk
  · intro k bl hk
    rw [hblk] at hk
    obtain ⟨h1, h2, h3, h4⟩ := hi.blocks k bl hk
    exact ⟨h1, h2, fun p hp => ⟨(h3 p hp).1, (h3 p hp).2.of_blk hblk⟩, h4⟩
  · -- AGORA-901: the borrows the change leaves name nodes no package holds
    have hcl : CleanLe (upd (kill e hv x Γ) x ox) Γ := CleanLe.of_entries fun v E' hv' => by
      by_cases hvx : v = x
      · subst hvx
        have := getX E' hv'; subst this
        obtain ⟨_, _, _, _, hm, _⟩ := hox
        exact ⟨Ex, hx, hm, fun h => absurd h hxr⟩
      · obtain ⟨E, hE, rfl⟩ := getE v E' hv' hvx
        exact ⟨E, hE, killE_mode .., fun _ => ⟨killE_path .., killE_held ..⟩⟩
    intro y Ey' o v hy hl hs i hn
    have hn0 : PkgNames m' Γ Ey' v i := hn.mono hcl
    by_cases hyx : y = x
    · subst hyx
      exact hpk.2 Ey' o v (getX Ey' hy) hl hs i hn0
    · obtain ⟨Ey, hEy, rfl⟩ := getE y Ey' hy hyx
      rw [hst y hyx] at hs
      exact hpk.1 y Ey o v hyx hEy hl hs i hn0.of_killE

/-! ### AGORA-901: a fresh binding -/

/-- A clean root of a context with one binding more is that binding, or one
    the context had: what a borrowed parameter depends on is bound. -/
theorem Hollow.of_setE {Γ : Ctx} {x : Var} {E : Entry} (hx : Γ x = none)
    (hwf : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → ∀ d ∈ memDeps (Ep.path ++ Ep.held), (Γ d.root).isSome)
    {r : Var} (h : Hollow (setE Γ x E) r) : r = x ∨ Hollow Γ r := by
  induction h with
  | @rootb p Ep hp hm _ ih =>
    by_cases hpx : p = x
    · exact Or.inl hpx
    · rw [setE, upd_ne _ _ hpx] at hp
      refine Or.inr (.rootb hp hm fun d hd => (ih d hd).resolve_left fun h => ?_)
      have := hwf p Ep hp hm d hd
      rw [h, hx] at this; cases this

theorem Clean.of_setE {Γ : Ctx} {x : Var} {E : Entry} (hx : Γ x = none)
    (hwf : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → ∀ d ∈ memDeps (Ep.path ++ Ep.held), (Γ d.root).isSome)
    {r : Var} (h : Clean (setE Γ x E) r) : r = x ∨ Clean Γ r := by
  have hpb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → ∀ d ∈ memDeps Ep.path, (Γ d.root).isSome :=
    fun p Ep hp hm d hd => hwf p Ep hp hm d (List.mem_filter.mpr
      ⟨List.mem_append_left _ (List.mem_filter.mp hd).1, (List.mem_filter.mp hd).2⟩)
  induction h with
  | @own r' Er hr ho =>
    by_cases hrx : r' = x
    · exact Or.inl hrx
    · rw [setE, upd_ne _ _ hrx] at hr; exact Or.inr (.own hr ho)
  | @rootb p Ep hp hm hns _ ih =>
    by_cases hpx : p = x
    · exact Or.inl hpx
    · rw [setE, upd_ne _ _ hpx] at hp
      have hne : ∀ d ∈ memDeps Ep.path, d.root ≠ x := fun d hd h => by
        have := hpb p Ep hp hm d hd
        rw [h, hx] at this; cases this
      refine Or.inr (.rootb hp hm (fun d hd => (hns d hd).imp id fun hh =>
        (hh.of_setE hx hwf).resolve_left (hne d hd)) fun d hd => (ih d hd).resolve_left (hne d hd))

theorem ShareOK.of_setE {Γ : Ctx} {x : Var} {E : Entry} (hx : Γ x = none)
    (hwf : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → ∀ d ∈ memDeps (Ep.path ++ Ep.held), (Γ d.root).isSome)
    {d : Dep} (hb : (Γ d.root).isSome) (h : ShareOK (setE Γ x E) d) : ShareOK Γ d :=
  h.imp id fun hh => (hh.of_setE hx hwf).resolve_left fun hr => by rw [hr, hx] at hb; cases hb

theorem CleanDeps.of_setE {Γ : Ctx} {x : Var} {E : Entry} (hx : Γ x = none)
    (hwf : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → ∀ d ∈ memDeps (Ep.path ++ Ep.held), (Γ d.root).isSome)
    {D : List Dep} (hb : ∀ d ∈ memDeps D, (Γ d.root).isSome) (h : CleanDeps (setE Γ x E) D) :
    CleanDeps Γ D := fun d hd => by
  refine ⟨(h d hd).1.of_setE hx hwf (hb d hd), ((h d hd).2.of_setE hx hwf).resolve_left fun hr => ?_⟩
  have := hb d hd; rw [hr, hx] at this; cases this

/-- What a borrowed parameter depends on is bound. -/
theorem MInv.rootb_bound {m : Mem} {Γ : Ctx} (hi : MInv m Γ) :
    ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → ∀ d ∈ memDeps (Ep.path ++ Ep.held), (Γ d.root).isSome := by
  intro p Ep hp hm d hd
  have hos : Ep.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨Er, hEr, _⟩ := hi.wf p Ep hp (hi.rootbLive p Ep hp hm) (Or.inr hm) d.root
    (List.mem_map_of_mem (by simp [Entry.vdeps, hos]; exact List.mem_append.mp (List.mem_filter.mp hd).1))
  rw [hEr]; rfl

/-- **A slot set to a fresh value keeps what every other binding names
    free of packages**: what they name lies in memory, where the fresh value's
    addresses, of no owned tree and no payload, are not. -/
theorem MInv.pkgFree_setFresh {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {o : Bool} {v : Val}
    (hfresh : o = true → ∀ i ∈ v.ids, (∀ r U, m.st r = some ⟨true, some U⟩ → i ∉ U.ids) ∧ ¬ PayAddr m i) :
    ∀ y Ey o' vy, y ≠ x → Γ y = some Ey → Alive Ey → m.st y = some ⟨o', some vy⟩ →
      ∀ i, PkgNames (m.set x ⟨o, some v⟩) Γ Ey vy i → PkgFreeId (m.set x ⟨o, some v⟩) i := by
  intro y Ey o' vy hyx hy hl hs i hn
  have hst : ∀ r, r ≠ x → (m.set x ⟨o, some v⟩).st r = m.st r := fun r hr => by simp [upd_ne _ _ hr]
  have hnot : ∀ i, ((∃ r T, m.st r = some ⟨true, some T⟩ ∧ i ∈ T.ids) ∨ PayAddr m i) →
      o = true → i ∉ v.ids := by
    rintro i hh ho hiv
    obtain ⟨h1, h2⟩ := hfresh ho i hiv
    rcases hh with ⟨r, T, hT, hiT⟩ | hp
    · exact h1 r T hT hiT
    · exact h2 hp
  have hfr : ∀ i, ((∃ r T, m.st r = some ⟨true, some T⟩ ∧ i ∈ T.ids) ∨ PayAddr m i) →
      PkgFreeId m i → PkgFreeId (m.set x ⟨o, some v⟩) i := by
    intro i hh h r T hT fs te ms ev cs hP t c d es hN
    by_cases hrx : r = x
    · subst hrx
      simp only [Mem.set_st, upd_same, Option.some.injEq, Slot.mk.injEq] at hT
      obtain ⟨ho, rfl⟩ := hT
      have hsT := hN.trans ((Sub.pkg (Sub.refl _)).trans hP)
      refine ⟨fun h1 => hnot i hh ho (h1 ▸ hsT.ids c (by simp [Val.ids])),
        fun h2 => hnot i hh ho (h2 ▸ hsT.ids d (by simp [Val.ids]))⟩
    · rw [hst r hrx] at hT; exact h r T hT fs te ms ev cs hP t c d es hN
  have hn0 : PkgNames m Γ Ey vy i := by
    rcases hn with h1 | h2 | ⟨hm, hc, c, r, T, t, d, es, hb, hT, hsn, hvn⟩ | h4
    · exact Or.inl h1
    · exact Or.inr (Or.inl h2)
    · refine Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, T, t, d, es, hb, ?_, hsn, hvn⟩))
      by_cases hrx : r = x
      · exfalso
        subst hrx
        simp only [Mem.set_st, upd_same, Option.some.injEq, Slot.mk.injEq] at hT
        obtain ⟨ho, rfl⟩ := hT
        have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
        obtain ⟨w, hw, hok⟩ := hi.bor_val hy (hl.live_of_bor hm) hos
        rw [hs] at hw; cases hw
        obtain ⟨dep, t', H', d', es', hlan, _⟩ := hok.bare_href c hb
        have hh : (∃ r T, m.st r = some ⟨true, some T⟩ ∧ c ∈ T.ids) ∨ PayAddr m c := by
          rcases hlan.home with ⟨x', T', hT', hsT'⟩ | hp
          · exact Or.inl ⟨x', T', hT', hsT'.ids c (by simp [Val.ids])⟩
          · exact Or.inr (hp.payAddr hi.heap c (by simp [Val.ids]))
        exact hnot c hh ho (hsn.ids c (by simp [Val.ids]))
      · rw [hst r hrx] at hT; exact hT
    · exact Or.inr (Or.inr (Or.inr h4))
  exact hfr i (hi.named_home hy hl hs hn0) (hi.pkgFree y Ey o' vy hy hl hs i hn0)

/-- **A fresh binding keeps `MInv.pkgFree`** for every other: what they name
    lies in memory, where the fresh value's addresses are not; and it is clean
    where it was. -/
theorem MInv.pkgFree_add {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry} {o : Bool} {v : Val}
    (hx : Γ x = none)
    (hfresh : o = true → ∀ i ∈ v.ids, (∀ r U, m.st r = some ⟨true, some U⟩ → i ∉ U.ids) ∧ ¬ PayAddr m i)
    (hself : ∀ i, PkgNames (m.set x ⟨o, some v⟩) (setE Γ x E) E v i → PkgFreeId (m.set x ⟨o, some v⟩) i) :
    ∀ y Ey o' vy, setE Γ x E y = some Ey → Alive Ey → (m.set x ⟨o, some v⟩).st y = some ⟨o', some vy⟩ →
      ∀ i, PkgNames (m.set x ⟨o, some v⟩) (setE Γ x E) Ey vy i → PkgFreeId (m.set x ⟨o, some v⟩) i := by
  intro y Ey o' vy hy hl hs i hn
  by_cases hyx : y = x
  · subst hyx
    simp only [setE, upd_same, Option.some.injEq] at hy; subst hy
    simp only [Mem.set_st, upd_same, Option.some.injEq, Slot.mk.injEq] at hs
    obtain ⟨rfl, rfl⟩ := hs
    exact hself i hn
  rw [setE, upd_ne _ _ hyx] at hy
  simp only [Mem.set_st, upd_ne _ _ hyx] at hs
  obtain ⟨sl, hsl, _, hso, hown, hbor⟩ := hi.slot y Ey hy
  rw [hs] at hsl; cases hsl
  -- the value names something only if it holds memory
  have hint : Ey.ty ≠ .int ∨ Ey.mode = .rootb := by
    by_cases ht : Ey.ty = .int
    · by_cases hrb : Ey.mode = .rootb
      · exact Or.inr hrb
      · exfalso
        cases hos : Ey.mode.ownSlot
        · have hm : Ey.mode = .bor ∨ Ey.mode = .rootb := by
            have := hi.noRegion y Ey hy
            cases hme : Ey.mode <;> simp_all [Mode.ownSlot]
          obtain ⟨w, hw, hok⟩ := hbor hos (hl.live_of_bor hm)
          cases hw
          rw [ht] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok
          exact PkgNames.none_int hn
        · have := (hown hos).1; rw [ht] at this; simp [Ty.owning] at this
    · exact Or.inl ht
  -- the deps it names through are bound
  have hbound : ∀ d ∈ Ey.vdeps, d.kind.isName = false → (Γ d.root).isSome := fun d hd hnm => by
    rcases hl with hl | ⟨hdb, hos⟩
    · obtain ⟨Er, hEr, _⟩ := hi.wf y Ey hy hl hint d.root (List.mem_map_of_mem hd)
      rw [hEr]; rfl
    · obtain ⟨Er, hEr, _⟩ := hi.wf.dtor y Ey hy hdb hos hint d hd hnm
      rw [hEr]; rfl
  have hvd : ∀ D, D ⊆ Ey.vdeps → ∀ d ∈ memDeps D, (Γ d.root).isSome := fun D hD d hd =>
    hbound d (hD (List.mem_filter.mp hd).1) (by simpa using (List.mem_filter.mp hd).2)
  have hpv : (Ey.mode = .bor ∨ Ey.mode = .rootb) → Ey.path ⊆ Ey.vdeps := fun hm d hd => by
    have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
    simp [Entry.vdeps, hos, hd]
  have hhv : Ey.held ⊆ Ey.vdeps := fun d hd => by simp [Entry.vdeps, hd]
  have hwf := hi.rootb_bound
  refine hi.pkgFree_setFresh hfresh y Ey o' vy hyx hy hl hs i ?_
  rcases hn with ⟨hm, hc, hv⟩ | ⟨hm, hc, hv⟩ | ⟨hm, hc, hv⟩ | ⟨hm, hc, hv⟩
  · exact Or.inl ⟨hm, hc.of_setE hx hwf (hvd _ (hpv hm)), hv⟩
  · exact Or.inr (Or.inl ⟨hm, hc.of_setE hx hwf (hvd _ fun d hd => by
      rcases List.mem_append.mp hd with h | h
      · exact hpv hm h
      · exact hhv h), hv⟩)
  · exact Or.inr (Or.inr (Or.inl ⟨hm, hc.of_setE hx hwf (hvd _ hhv), hv⟩))
  · exact Or.inr (Or.inr (Or.inr ⟨hm, hc.of_setE hx hwf (hvd _ hhv), hv⟩))

/-! ### AGORA-901: an owner's tree rewritten -/

/-- An address of no owned tree and no payload: a fresh one. -/
def FreshAddr (m : Mem) (i : Nat) : Prop := (∀ r U, m.st r = some ⟨true, some U⟩ → i ∉ U.ids) ∧ ¬ PayAddr m i

/-- **An owner's tree rewritten keeps `MInv.pkgFree`**: each package of the
    new tree is one of the old tree's or of fresh addresses only; each node is
    at a fresh address, or at one of the old tree's whose views it keeps, or
    it is the old tree's top, rewritten by an effect that ends every borrow of
    the owner's handle and view (who alone names it, `MInv.root_namer`); and
    what the owner names, no package holds. -/
theorem PkgKeep.of_edit {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {e : Eff} {hv : Bool} {x : Var} {Ex : Entry} {ox : Option Entry} (hx : Γ x = some Ex) (hxF : x ∉ F)
    {T0 : Val} (hT : m.st x = some ⟨true, some T0⟩)
    (hst : ∀ o, o ≠ x → m'.st o = m.st o)
    (hpk : ∀ T', m'.st x = some ⟨true, some T'⟩ → ∀ fs te ms ev cs, Sub (.pkg fs te ms ev cs) T' →
      Sub (.pkg fs te ms ev cs) T0 ∨ ∀ i ∈ (Val.pkg fs te ms ev cs).ids, FreshAddr m i)
    (hnode : ∀ T', m'.st x = some ⟨true, some T'⟩ → ∀ t c d es, Sub (.node t c d es) T' →
      (∃ t1 d1 es1, Sub (.node t1 c d1 es1) T0 ∧ ∀ i o l, Sub (.view i o l) (.node t c d es) →
        Sub (.view i o l) (.node t1 c d1 es1)) ∨ FreshAddr m c ∨
      (∃ t0 d0 es0, T0 = .node t0 c d0 es0 ∧ e.kills hv .self = true ∧ e.kills hv .view = true) ∨
      (c ∈ T0.ids ∧ e.kills hv .self = true ∧ e.kills hv .view = true ∧ e.kills hv .inner = true ∧
        ∀ j, e.kills hv (.innerAt j) = true))
    (hself : ∀ Ex' o v, ox = some Ex' → Alive Ex' → m'.st x = some ⟨o, some v⟩ →
      ∀ i, PkgNames m' Γ Ex' v i → PkgFreeId m i ∧ ¬ FreshAddr m i) :
    PkgKeep m m' Γ e hv x ox := by
  -- what lies in memory, no fresh package holds
  have hfr : ∀ i, ¬ FreshAddr m i → PkgFreeId m i → PkgFreeId m' i := by
    intro i hnf h r T hT' fs te ms ev cs hP t c d es hN
    by_cases hrx : r = x
    · subst hrx
      rcases hpk T hT' fs te ms ev cs hP with hP0 | hfp
      · exact h r _ hT fs te ms ev cs hP0 t c d es hN
      · have hsN : ∀ j ∈ (Val.node t c d es).ids, FreshAddr m j := fun j hj =>
          hfp j (Child.ids Child.pkg j (hN.ids j hj))
        exact ⟨fun h1 => hnf (h1 ▸ hsN c (by simp [Val.ids])), fun h2 => hnf (h2 ▸ hsN d (by simp [Val.ids]))⟩
    · rw [hst r hrx] at hT'; exact h r T hT' fs te ms ev cs hP t c d es hN
  have hhome : ∀ i, ((∃ r T, m.st r = some ⟨true, some T⟩ ∧ i ∈ T.ids) ∨ PayAddr m i) → ¬ FreshAddr m i := by
    rintro i (⟨r, T, hT', hiT⟩ | hp) ⟨h1, h2⟩
    · exact h1 r T hT' hiT
    · exact h2 hp
  refine ⟨fun y Ey o v hyx hEy hl hs i hn => ?_, fun Ex' o v hx' hl hs i hn => ?_⟩
  · have hla := hl.of_killE
    have hn0 : PkgNames m Γ Ey v i := by
      rcases hn with h1 | h2 | ⟨hm, hc, c, r, T1, t, d, es, hb, hT1, hs1, o', l, hvn⟩ | h4
      · exact Or.inl h1
      · exact Or.inr (Or.inl h2)
      · by_cases hrx : r = x
        · subst hrx
          rcases hnode T1 hT1 t c d es hs1 with ⟨t1, d1, es1, hs0, hvw⟩ | hfc | ⟨t0, d0, es0, rfl, hks, hkv⟩ |
              ⟨hcT, hks, hkv, hki, hkj⟩
          · exact Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, _, t1, d1, es1, hb, hT, hs0, o', l, hvw i o' l hvn⟩))
          · exfalso
            have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
            obtain ⟨w, hw, hok⟩ := hi.bor_val hEy (hla.live_of_bor hm) hos
            rw [hs] at hw; cases hw
            obtain ⟨dep, t', H', d', es', hlan, _⟩ := hok.bare_href c hb
            refine hhome c ?_ hfc
            rcases hlan.home with ⟨x', T', hT', hsT'⟩ | hp
            · exact Or.inl ⟨x', T', hT', hsT'.ids c (by simp [Val.ids])⟩
            · exact Or.inr (hp.payAddr hi.heap c (by simp [Val.ids]))
          · exfalso
            have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
            obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot y Ey hEy
            rw [hs] at hsl; cases hsl
            have ho : o = false := by have := hso; simp only at this; rw [this, hos]
            subst ho
            obtain ⟨dep, hdv, hdr, hdk⟩ := hi.root_namer hanch hxF hT hEy (hla.live_of_bor hm) hs hb
            have hhit : hits e hv r Ey = true := by
              unfold hits
              have hnt : (Ey.ty != .int || Ey.mode == .rootb) = true := by
                cases hty : Ey.ty <;> simp_all
                obtain ⟨w, hw, hok⟩ := hi.bor_val hEy (hla.live_of_bor hm) hos
                rw [hs] at hw; cases hw
                rw [hty] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok; cases hb
              rw [hnt, Bool.true_and, List.any_eq_true]
              exact ⟨dep, hdv, by rcases hdk with h | h <;> simp [hdr, h, hks, hkv]⟩
            exact hl.killed hhit hos
          · exfalso
            have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
            obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot y Ey hEy
            rw [hs] at hsl; cases hsl
            have ho : o = false := by have := hso; simp only at this; rw [this, hos]
            subst ho
            obtain ⟨dep, hdv, hdr, hdk⟩ := hi.namer hanch hxF hT hcT hEy (hla.live_of_bor hm) hs hb
            have hhit : hits e hv r Ey = true := by
              unfold hits
              have hnt : (Ey.ty != .int || Ey.mode == .rootb) = true := by
                cases hty : Ey.ty <;> simp_all
                obtain ⟨w, hw, hok⟩ := hi.bor_val hEy (hla.live_of_bor hm) hos
                rw [hs] at hw; cases hw
                rw [hty] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok; cases hb
              rw [hnt, Bool.true_and, List.any_eq_true]
              exact ⟨dep, hdv, by rcases hdk with h | h | h | ⟨j, h⟩ <;> simp [hdr, h, hks, hkv, hki, hkj]⟩
            exact hl.killed hhit hos
        · rw [hst r hrx] at hT1
          exact Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, T1, t, d, es, hb, hT1, hs1, o', l, hvn⟩))
      · exact Or.inr (Or.inr (Or.inr h4))
    have hs' : m.st y = some ⟨o, some v⟩ := hs
    exact hfr i (hhome i (hi.named_home hEy hla hs' hn0)) (hi.pkgFree y Ey o v hEy hla hs' i hn0)
  · obtain ⟨h1, h2⟩ := hself Ex' o v hx' hl hs i hn
    exact hfr i h2 h1


/-- AGORA-937 (3d, route F): `PkgKeep.of_edit` where `x` may be frozen. -/
theorem PkgKeep.of_edit_ne {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {e : Eff} {hv : Bool} {x : Var} {Ex : Entry} {ox : Option Entry} (hx : Γ x = some Ex)
    (hxa : ∀ p E, Γ p = some E → E.mode = .rootb →
      (∀ d ∈ E.path, d.root = x → d.kind.bound ≠ .none) ∧
      ((∀ t, E.ty ≠ .vec t) → ∀ d ∈ E.held, d.root = x → d.kind.bound ≠ .none))
    {T0 : Val} (hT : m.st x = some ⟨true, some T0⟩)
    (hst : ∀ o, o ≠ x → m'.st o = m.st o)
    (hpk : ∀ T', m'.st x = some ⟨true, some T'⟩ → ∀ fs te ms ev cs, Sub (.pkg fs te ms ev cs) T' →
      Sub (.pkg fs te ms ev cs) T0 ∨ ∀ i ∈ (Val.pkg fs te ms ev cs).ids, FreshAddr m i)
    (hnode : ∀ T', m'.st x = some ⟨true, some T'⟩ → ∀ t c d es, Sub (.node t c d es) T' →
      (∃ t1 d1 es1, Sub (.node t1 c d1 es1) T0 ∧ ∀ i o l, Sub (.view i o l) (.node t c d es) →
        Sub (.view i o l) (.node t1 c d1 es1)) ∨ FreshAddr m c ∨
      (∃ t0 d0 es0, T0 = .node t0 c d0 es0 ∧ e.kills hv .self = true ∧ e.kills hv .view = true) ∨
      (c ∈ T0.ids ∧ e.kills hv .self = true ∧ e.kills hv .view = true ∧ e.kills hv .inner = true ∧
        ∀ j, e.kills hv (.innerAt j) = true))
    (hself : ∀ Ex' o v, ox = some Ex' → Alive Ex' → m'.st x = some ⟨o, some v⟩ →
      ∀ i, PkgNames m' Γ Ex' v i → PkgFreeId m i ∧ ¬ FreshAddr m i) :
    PkgKeep m m' Γ e hv x ox := by
  -- what lies in memory, no fresh package holds
  have hfr : ∀ i, ¬ FreshAddr m i → PkgFreeId m i → PkgFreeId m' i := by
    intro i hnf h r T hT' fs te ms ev cs hP t c d es hN
    by_cases hrx : r = x
    · subst hrx
      rcases hpk T hT' fs te ms ev cs hP with hP0 | hfp
      · exact h r _ hT fs te ms ev cs hP0 t c d es hN
      · have hsN : ∀ j ∈ (Val.node t c d es).ids, FreshAddr m j := fun j hj =>
          hfp j (Child.ids Child.pkg j (hN.ids j hj))
        exact ⟨fun h1 => hnf (h1 ▸ hsN c (by simp [Val.ids])), fun h2 => hnf (h2 ▸ hsN d (by simp [Val.ids]))⟩
    · rw [hst r hrx] at hT'; exact h r T hT' fs te ms ev cs hP t c d es hN
  have hhome : ∀ i, ((∃ r T, m.st r = some ⟨true, some T⟩ ∧ i ∈ T.ids) ∨ PayAddr m i) → ¬ FreshAddr m i := by
    rintro i (⟨r, T, hT', hiT⟩ | hp) ⟨h1, h2⟩
    · exact h1 r T hT' hiT
    · exact h2 hp
  refine ⟨fun y Ey o v hyx hEy hl hs i hn => ?_, fun Ex' o v hx' hl hs i hn => ?_⟩
  · have hla := hl.of_killE
    have hn0 : PkgNames m Γ Ey v i := by
      rcases hn with h1 | h2 | ⟨hm, hc, c, r, T1, t, d, es, hb, hT1, hs1, o', l, hvn⟩ | h4
      · exact Or.inl h1
      · exact Or.inr (Or.inl h2)
      · by_cases hrx : r = x
        · subst hrx
          rcases hnode T1 hT1 t c d es hs1 with ⟨t1, d1, es1, hs0, hvw⟩ | hfc | ⟨t0, d0, es0, rfl, hks, hkv⟩ |
              ⟨hcT, hks, hkv, hki, hkj⟩
          · exact Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, _, t1, d1, es1, hb, hT, hs0, o', l, hvw i o' l hvn⟩))
          · exfalso
            have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
            obtain ⟨w, hw, hok⟩ := hi.bor_val hEy (hla.live_of_bor hm) hos
            rw [hs] at hw; cases hw
            obtain ⟨dep, t', H', d', es', hlan, _⟩ := hok.bare_href c hb
            refine hhome c ?_ hfc
            rcases hlan.home with ⟨x', T', hT', hsT'⟩ | hp
            · exact Or.inl ⟨x', T', hT', hsT'.ids c (by simp [Val.ids])⟩
            · exact Or.inr (hp.payAddr hi.heap c (by simp [Val.ids]))
          · exfalso
            have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
            obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot y Ey hEy
            rw [hs] at hsl; cases hsl
            have ho : o = false := by have := hso; simp only at this; rw [this, hos]
            subst ho
            obtain ⟨dep, hdv, hdr, hdk⟩ := hi.root_namer_ne hanch hxa hT hEy (hla.live_of_bor hm) hs hb
            have hhit : hits e hv r Ey = true := by
              unfold hits
              have hnt : (Ey.ty != .int || Ey.mode == .rootb) = true := by
                clear hxa; cases hty : Ey.ty <;> simp_all
                obtain ⟨w, hw, hok⟩ := hi.bor_val hEy (hla.live_of_bor hm) hos
                rw [hs] at hw; cases hw
                rw [hty] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok; cases hb
              rw [hnt, Bool.true_and, List.any_eq_true]
              exact ⟨dep, hdv, by rcases hdk with h | h <;> simp [hdr, h, hks, hkv]⟩
            exact hl.killed hhit hos
          · exfalso
            have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
            obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot y Ey hEy
            rw [hs] at hsl; cases hsl
            have ho : o = false := by have := hso; simp only at this; rw [this, hos]
            subst ho
            obtain ⟨dep, hdv, hdr, hdk⟩ := hi.namer_ne hanch hxa hT hcT hEy (hla.live_of_bor hm) hs hb
            have hhit : hits e hv r Ey = true := by
              unfold hits
              have hnt : (Ey.ty != .int || Ey.mode == .rootb) = true := by
                clear hxa; cases hty : Ey.ty <;> simp_all
                obtain ⟨w, hw, hok⟩ := hi.bor_val hEy (hla.live_of_bor hm) hos
                rw [hs] at hw; cases hw
                rw [hty] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok; cases hb
              rw [hnt, Bool.true_and, List.any_eq_true]
              exact ⟨dep, hdv, by rcases hdk with h | h | h | ⟨j, h⟩ <;> simp [hdr, h, hks, hkv, hki, hkj]⟩
            exact hl.killed hhit hos
        · rw [hst r hrx] at hT1
          exact Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, T1, t, d, es, hb, hT1, hs1, o', l, hvn⟩))
      · exact Or.inr (Or.inr (Or.inr h4))
    have hs' : m.st y = some ⟨o, some v⟩ := hs
    exact hfr i (hhome i (hi.named_home hEy hla hs' hn0)) (hi.pkgFree y Ey o v hEy hla hs' i hn0)
  · obtain ⟨h1, h2⟩ := hself Ex' o v hx' hl hs i hn
    exact hfr i h2 h1

/-- AGORA-901: what an entry depending on bound roots names in a context with
    a fresh binding more, it names in the context. -/
theorem PkgNames.of_setE {m : Mem} {Γ : Ctx}
    (hwf : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → ∀ d ∈ memDeps (Ep.path ++ Ep.held), (Γ d.root).isSome)
    {x : Var} {E1 E : Entry} {v : Val} {i : Nat}
    (hx : Γ x = Option.none)
    (hbp : (E.mode = .bor ∨ E.mode = .rootb) → ∀ d ∈ memDeps E.path, (Γ d.root).isSome)
    (hbh : ∀ d ∈ memDeps E.held, (Γ d.root).isSome)
    (hn : PkgNames m (setE Γ x E1) E v i) : PkgNames m Γ E v i := by
  have hb : (E.mode = .bor ∨ E.mode = .rootb) → ∀ d ∈ memDeps (E.path ++ E.held), (Γ d.root).isSome :=
    fun hm d hd => by
      obtain ⟨hd, hnm⟩ := List.mem_filter.mp hd
      rcases List.mem_append.mp hd with h | h
      · exact hbp hm d (List.mem_filter.mpr ⟨h, hnm⟩)
      · exact hbh d (List.mem_filter.mpr ⟨h, hnm⟩)
  rcases hn with ⟨hm, hc, hv⟩ | ⟨hm, hc, hv⟩ | ⟨hm, hc, hv⟩ | ⟨hm, hc, hv⟩
  · exact Or.inl ⟨hm, hc.of_setE hx hwf (hbp hm), hv⟩
  · exact Or.inr (Or.inl ⟨hm, hc.of_setE hx hwf (hb hm), hv⟩)
  · exact Or.inr (Or.inr (Or.inl ⟨hm, hc.of_setE hx hwf hbh, hv⟩))
  · exact Or.inr (Or.inr (Or.inr ⟨hm, hc.of_setE hx hwf hbh, hv⟩))

/-- AGORA-901: a store whose owned trees are some of another's: what no
    package of the other's holds, none of its holds, and what it names, the
    other names. -/
theorem PkgFreeId.of_fewer {m m1 : Mem}
    (hsub : ∀ r T, m1.st r = some ⟨true, some T⟩ → m.st r = some ⟨true, some T⟩) {i : Nat}
    (h : PkgFreeId m i) : PkgFreeId m1 i := fun r T hT => h r T (hsub r T hT)

/-- No package of a store whose owned trees are, somewhere, another's holds
    what none of that other's holds. -/
theorem PkgFreeId.of_moved {m m1 : Mem}
    (hsub : ∀ r T, m1.st r = some ⟨true, some T⟩ → ∃ r', m.st r' = some ⟨true, some T⟩) {i : Nat}
    (h : PkgFreeId m i) : PkgFreeId m1 i := fun r T hT => by
  obtain ⟨r', hT'⟩ := hsub r T hT; exact h r' T hT'

theorem PkgNames.of_moved {m m1 : Mem} {Γ : Ctx}
    (hsub : ∀ r T, m1.st r = some ⟨true, some T⟩ → ∃ r', m.st r' = some ⟨true, some T⟩)
    {E : Entry} {v : Val} {i : Nat} (hn : PkgNames m1 Γ E v i) : PkgNames m Γ E v i := by
  rcases hn with h1 | h2 | ⟨hm, hc, c, r, T, t, d, es, hb, hT, hsn, hvn⟩ | h4
  · exact Or.inl h1
  · exact Or.inr (Or.inl h2)
  · obtain ⟨r', hT'⟩ := hsub r T hT
    exact Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r', T, t, d, es, hb, hT', hsn, hvn⟩))
  · exact Or.inr (Or.inr (Or.inr h4))

theorem PkgNames.of_fewer {m m1 : Mem} {Γ : Ctx}
    (hsub : ∀ r T, m1.st r = some ⟨true, some T⟩ → m.st r = some ⟨true, some T⟩)
    {E : Entry} {v : Val} {i : Nat} (hn : PkgNames m1 Γ E v i) : PkgNames m Γ E v i := by
  rcases hn with h1 | h2 | ⟨hm, hc, c, r, T, t, d, es, hb, hT, hsn, hvn⟩ | h4
  · exact Or.inl h1
  · exact Or.inr (Or.inl h2)
  · exact Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, T, t, d, es, hb, hsub r T hT, hsn, hvn⟩))
  · exact Or.inr (Or.inr (Or.inr h4))

/-- **Binding a fresh variable over an empty slot keeps `MInv.pkgFree`**:
    the slot owns nothing and holds no value, and no other binding's clean
    roots reach the new one. -/
theorem MInv.pkgFree_addNone {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry} {o : Bool}
    (hx : Γ x = none) :
    ∀ y Ey o' vy, setE Γ x E y = some Ey → Alive Ey → (m.set x ⟨o, none⟩).st y = some ⟨o', some vy⟩ →
      ∀ i, PkgNames (m.set x ⟨o, none⟩) (setE Γ x E) Ey vy i → PkgFreeId (m.set x ⟨o, none⟩) i := by
  intro y Ey o' vy hy hl hs i hn
  have hsub : ∀ r T, (m.set x ⟨o, none⟩).st r = some ⟨true, some T⟩ → m.st r = some ⟨true, some T⟩ := by
    intro r T hT
    by_cases hrx : r = x
    · subst hrx; simp at hT
    · simpa [upd_ne _ _ hrx] using hT
  by_cases hyx : y = x
  · subst hyx; simp at hs
  rw [setE, upd_ne _ _ hyx] at hy
  simp only [Mem.set_st, upd_ne _ _ hyx] at hs
  replace hn := PkgNames.of_fewer hsub hn
  refine PkgFreeId.of_fewer hsub (hi.pkgFree y Ey o' vy hy hl hs i ?_)
  obtain ⟨sl, hsl, _, hso, hown, hbor⟩ := hi.slot y Ey hy
  rw [hs] at hsl; cases hsl
  have hint : Ey.ty ≠ .int ∨ Ey.mode = .rootb := by
    by_cases ht : Ey.ty = .int
    · by_cases hrb : Ey.mode = .rootb
      · exact Or.inr hrb
      · exfalso
        cases hos : Ey.mode.ownSlot
        · have hm : Ey.mode = .bor ∨ Ey.mode = .rootb := by
            have := hi.noRegion y Ey hy
            cases hme : Ey.mode <;> simp_all [Mode.ownSlot]
          obtain ⟨w, hw, hok⟩ := hbor hos (hl.live_of_bor hm)
          cases hw
          rw [ht] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok
          exact PkgNames.none_int hn
        · have := (hown hos).1; rw [ht] at this; simp [Ty.owning] at this
    · exact Or.inl ht
  have hbound : ∀ d ∈ Ey.vdeps, d.kind.isName = false → (Γ d.root).isSome := fun d hd hnm => by
    rcases hl with hl | ⟨hdb, hos⟩
    · obtain ⟨Er, hEr, _⟩ := hi.wf y Ey hy hl hint d.root (List.mem_map_of_mem hd)
      rw [hEr]; rfl
    · obtain ⟨Er, hEr, _⟩ := hi.wf.dtor y Ey hy hdb hos hint d hd hnm
      rw [hEr]; rfl
  have hvd : ∀ D, D ⊆ Ey.vdeps → ∀ d ∈ memDeps D, (Γ d.root).isSome := fun D hD d hd =>
    hbound d (hD (List.mem_filter.mp hd).1) (by simpa using (List.mem_filter.mp hd).2)
  have hpv : (Ey.mode = .bor ∨ Ey.mode = .rootb) → Ey.path ⊆ Ey.vdeps := fun hm d hd => by
    have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
    simp [Entry.vdeps, hos, hd]
  have hhv : Ey.held ⊆ Ey.vdeps := fun d hd => by simp [Entry.vdeps, hd]
  exact PkgNames.of_setE hi.rootb_bound hx (fun hm => hvd _ (hpv hm)) (hvd _ hhv) hn

end A2
