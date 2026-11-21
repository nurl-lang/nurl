import A2.Closure
import A2.ThruLiftKinds

/-! A2 — AGORA-937 stage 3a: what a through-changing call that passes views
of real memory ends before its body runs.

A call whose callee changes elements through a borrow (`ThruFn`) may move
buffers inside the memory its arguments hold views of. Where those views are
of the caller's own memory (a real root `r ∈ callR`, not a region), the
frame's bindings that reach `r` must be dead while the body runs: the memory
invariant speaks of every live binding of the combined context. The body
cannot name the frame, so ending them first changes nothing it types. The
arguments themselves stay as they are; the body reads them through its
parameters (`A2/THRU_STAGE3_DESIGN.md`).

This file defines that entry kill, `thruPre`, and proves what it keeps: it
only ends bindings (`LiveLe`), so the context's well-formedness, its domain,
modes and types, fresh borrows' sources and every binding a closure names
are kept. No typing rule uses it yet. -/

namespace A2

/-! ### Ending bindings, and nothing else -/

/-- `Γ'` is `Γ` with some bindings ended: the same bindings, each the same
    entry, live only where it was live. -/
def LiveLe (Γ Γ' : Ctx) : Prop :=
  ∀ v, (Γ' v).isSome = (Γ v).isSome ∧
    ∀ E', Γ' v = some E' → ∃ E l, Γ v = some E ∧ E' = { E with live := l } ∧
      (l = true → E.live = true)

theorem LiveLe.refl (Γ : Ctx) : LiveLe Γ Γ := fun _ =>
  ⟨rfl, fun E' h => ⟨E', E'.live, h, by cases E'; rfl, id⟩⟩

theorem LiveLe.trans {Γ1 Γ2 Γ3 : Ctx} (h1 : LiveLe Γ1 Γ2) (h2 : LiveLe Γ2 Γ3) : LiveLe Γ1 Γ3 := by
  intro v
  refine ⟨(h2 v).1.trans (h1 v).1, fun E3 h3 => ?_⟩
  obtain ⟨E2, l2, h2', rfl, hl2⟩ := (h2 v).2 E3 h3
  obtain ⟨E1, l1, h1', rfl, hl1⟩ := (h1 v).2 E2 h2'
  exact ⟨E1, l2, h1', rfl, fun h => hl1 (hl2 h)⟩

theorem killE_eq_live (e : Eff) (hv : Bool) (x : Var) (E : Entry) :
    killE e hv x E = { E with live := (killE e hv x E).live } := by
  unfold killE; split <;> cases E <;> rfl

theorem LiveLe.kill (Γ : Ctx) (e : Eff) (hv : Bool) (x : Var) : LiveLe Γ (kill e hv x Γ) := by
  intro v
  refine ⟨by simp [A2.kill], fun E' h => ?_⟩
  simp only [A2.kill] at h
  obtain ⟨E, hE, rfl⟩ := Option.map_eq_some_iff.mp h
  exact ⟨E, _, hE, killE_eq_live e hv x E, killE_live_le⟩

theorem LiveLe.killHv (Γ : Ctx) : ∀ ks, LiveLe Γ (A2.killHv ks Γ)
  | [] => LiveLe.refl Γ
  | (e, hv, x) :: ks => (LiveLe.killHv Γ ks).trans (LiveLe.kill _ e hv x)

/-- An ended binding keeps its mode and type. -/
theorem LiveLe.get {Γ Γ' : Ctx} (h : LiveLe Γ Γ') {v : Var} {E' : Entry} (hv : Γ' v = some E') :
    ∃ E, Γ v = some E ∧ E'.mode = E.mode ∧ E'.ty = E.ty ∧ E'.vdeps = E.vdeps ∧
      E'.path = E.path ∧ E'.held = E.held ∧ E'.dtor = E.dtor ∧ E'.dbind = E.dbind ∧
      E'.fresh = E.fresh ∧ (E'.live = true → E.live = true) := by
  obtain ⟨E, l, hE, rfl, hl⟩ := (h v).2 E' hv
  exact ⟨E, hE, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, hl⟩

/-- ... and a binding of `Γ` is a binding of `Γ'`, of the same mode and type. -/
theorem LiveLe.back {Γ Γ' : Ctx} (h : LiveLe Γ Γ') {v : Var} {E : Entry} (hv : Γ v = some E) :
    ∃ E', Γ' v = some E' ∧ E'.mode = E.mode ∧ E'.ty = E.ty := by
  cases hE' : Γ' v with
  | none => have := (h v).1; rw [hE', hv] at this; cases this
  | some E' =>
    obtain ⟨E0, h0, hm, ht, _⟩ := h.get hE'
    rw [hv] at h0; cases h0
    exact ⟨E', rfl, hm, ht⟩

theorem LiveLe.domTy {Γ Γ' : Ctx} (h : LiveLe Γ Γ') : DomTy Γ Γ' := by
  refine ⟨fun x => (h x).1, fun x E' hx => ?_⟩
  obtain ⟨E, hE, hm, ht, _⟩ := h.get hx
  exact ⟨E, hE, hm, ht⟩

theorem LiveLe.domMode {Γ Γ' : Ctx} (h : LiveLe Γ Γ') : DomMode Γ Γ' := by
  refine ⟨fun x => (h x).1, fun x E' hx => ?_⟩
  obtain ⟨E, hE, hm, _⟩ := h.get hx
  exact ⟨E, hE, hm⟩

/-- Ending bindings keeps a context well-formed: a live binding's roots are
    still bound, at the same modes. -/
theorem CtxWF.liveLe {Γ Γ' : Ctx} (hw : CtxWF Γ) (h : LiveLe Γ Γ') : CtxWF Γ' := by
  refine ⟨fun v E' hv hl hn r hr => ?_, fun v E' hv hd hos hn d hdd hnm => ?_,
    fun v E' hv hd => ?_, fun v E' hv hd => ?_⟩
  · obtain ⟨E, hE, hm, ht, hvd, -, -, -, -, -, hll⟩ := h.get hv
    rw [hm, ht] at hn; rw [hvd] at hr
    obtain ⟨Er, hEr, hro⟩ := hw.live v E hE (hll hl) hn r hr
    obtain ⟨Er', hEr', hm', -⟩ := h.back hEr
    exact ⟨Er', hEr', by rw [hm']; exact hro⟩
  · obtain ⟨E, hE, hm, ht, hvd, -, -, -, hdb, -, -⟩ := h.get hv
    rw [hdb] at hd; rw [hm] at hos; rw [hm, ht] at hn; rw [hvd] at hdd
    obtain ⟨Er, hEr, hro⟩ := hw.dtor v E hE hd hos hn d hdd hnm
    obtain ⟨Er', hEr', hm', -⟩ := h.back hEr
    exact ⟨Er', hEr', by rw [hm']; exact hro⟩
  · obtain ⟨E, hE, -, -, -, -, -, hdt, hdb, -, -⟩ := h.get hv
    rw [hdt] at hd; rw [hdb]; exact hw.arm v E hE hd
  · obtain ⟨E, hE, -, ht, -, -, -, -, hdb, -, -⟩ := h.get hv
    rw [hdb] at hd; rw [ht]; exact hw.view v E hE hd

/-- ... keeps every fresh borrow's sources the frame's own. -/
theorem FreshOK.liveLe {Γ Γ' : Ctx} (hf : FreshOK Γ) (h : LiveLe Γ Γ') : FreshOK Γ' := by
  intro v E' hv hl hn hb hfr
  obtain ⟨E, hE, hm, ht, -, hp, -, -, -, hfe, hll⟩ := h.get hv
  rw [ht] at hn; rw [hm] at hb; rw [hfe] at hfr; rw [hp]
  obtain ⟨hne, hd⟩ := hf v E hE (hll hl) hn hb hfr
  refine ⟨hne, fun d hdp => ?_⟩
  obtain ⟨hk, Er, hEr, hfr'⟩ := hd d hdp
  obtain ⟨Er', hEr', hm', -⟩ := h.back hEr
  exact ⟨hk, Er', hEr', by rw [hm']; exact hfr'⟩

/-- ... and every binding a closure names, where those keep their entries. -/
theorem NameWF.liveLe {Γ Γ' : Ctx} (hn : NameWF Γ) (h : LiveLe Γ Γ')
    (hkeep : ∀ r Er, Γ r = some Er → Er.live = true → Er.held = [] → Er.mode.ownSlot = true →
      Γ' r = some Er) : NameWF Γ' := by
  intro v E' hv hl hni d hd b t hk
  obtain ⟨E, hE, hm, ht, hvd, -, -, -, -, -, hll⟩ := h.get hv
  rw [hm, ht] at hni; rw [hvd] at hd
  obtain ⟨Er, hEr, hlr, hhr, hrest⟩ := hn v E hE (hll hl) hni d hd b t hk
  exact ⟨Er, hkeep d.root Er hEr hlr hhr hrest.2.1, hlr, hhr, hrest⟩

/-! ### The entry kill -/

/-- The per-root effects of a through-changing call: a drop on each root the
    arguments hold views of in memory, with whether its elements hold views.
    A2's effects have no depth: the callee changes only elements' insides
    there, but a `.drop` on the root ends views of its own buffer too, so A2
    ends more than nurlc does (`A2/THRU_STAGE3_DESIGN.md`). -/
def thruRootKills (Γ : Ctx) (args : List Var) : List (Eff × Bool × Var) :=
  (callR Γ args).map fun r => (.drop, (argE Γ r).ty.holdsView, r)

/-- What the frame is while the body of a through-changing call runs: every
    binding but the arguments after those drops, the arguments as they are. -/
def thruPre (Γ : Ctx) (args : List Var) : Ctx :=
  fun v => if v ∈ args then Γ v else killHv (thruRootKills Γ args) Γ v

theorem thruPre_arg {Γ : Ctx} {args : List Var} {a : Var} (ha : a ∈ args) : thruPre Γ args a = Γ a := by
  simp [thruPre, ha]

theorem thruPre_frame {Γ : Ctx} {args : List Var} {v : Var} (hv : v ∉ args) :
    thruPre Γ args v = killHv (thruRootKills Γ args) Γ v := by
  simp [thruPre, hv]

/-- The entry kill only ends bindings. -/
theorem LiveLe.thruPre (Γ : Ctx) (args : List Var) : LiveLe Γ (A2.thruPre Γ args) := by
  intro v
  by_cases hv : v ∈ args
  · rw [thruPre_arg hv]; exact LiveLe.refl Γ v
  · rw [thruPre_frame hv]; exact LiveLe.killHv Γ _ v

/-- A binding that depends on nothing is not ended by any kill. -/
theorem killHv_nodeps {Γ : Ctx} {r : Var} {E : Entry} (hr : Γ r = some E) (hd : E.vdeps = []) :
    ∀ ks, A2.killHv ks Γ r = some E
  | [] => hr
  | (e, hv, x) :: ks => by
    show (A2.killHv ks Γ r).map (killE e hv x) = some E
    rw [killHv_nodeps hr hd ks, Option.map_some, killE_nohit (by rw [hd]; intro d hd'; cases hd')]

/-- A binding a closure names - an owner holding nothing - is not ended. -/
theorem thruPre_named {Γ : Ctx} {args : List Var} {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hh : Er.held = []) (hos : Er.mode.ownSlot = true) : thruPre Γ args r = some Er := by
  by_cases hra : r ∈ args
  · rw [thruPre_arg hra]; exact hr
  · rw [thruPre_frame hra]
    exact killHv_nodeps hr (by simp [Entry.vdeps, hos, hh]) _

theorem CtxWF.thruPre {Γ : Ctx} (h : CtxWF Γ) (args : List Var) : CtxWF (A2.thruPre Γ args) :=
  h.liveLe (LiveLe.thruPre Γ args)

theorem FreshOK.thruPre {Γ : Ctx} (h : FreshOK Γ) (args : List Var) : FreshOK (A2.thruPre Γ args) :=
  h.liveLe (LiveLe.thruPre Γ args)

theorem NameWF.thruPre {Γ : Ctx} (h : NameWF Γ) (args : List Var) : NameWF (A2.thruPre Γ args) :=
  h.liveLe (LiveLe.thruPre Γ args) fun _ _ hr _ hh hos => thruPre_named hr hh hos

theorem DomTy.thruPre (Γ : Ctx) (args : List Var) : DomTy Γ (A2.thruPre Γ args) :=
  (LiveLe.thruPre Γ args).domTy

/-! ### What it ends -/

/-- A kill ends a binding it hits, and a later kill leaves it ended. -/
theorem killHv_dead_of_mem {Γ : Ctx} {v : Var} {E : Entry} (hE : Γ v = some E) {e : Eff} {hv : Bool}
    {x : Var} (hh : hits e hv x E = true) :
    ∀ {ks : List (Eff × Bool × Var)}, (e, hv, x) ∈ ks →
      ∃ E', A2.killHv ks Γ v = some E' ∧ E'.live = false
  | (e0, hv0, x0) :: ks, hm => by
    show ∃ E', (A2.killHv ks Γ v).map (killE e0 hv0 x0) = some E' ∧ E'.live = false
    obtain ⟨E1, h1⟩ : ∃ E1, A2.killHv ks Γ v = some E1 := by
      cases hk : A2.killHv ks Γ v with
      | none => have := (LiveLe.killHv Γ ks v).1; rw [hk, hE] at this; cases this
      | some E1 => exact ⟨E1, rfl⟩
    rw [h1, Option.map_some]
    refine ⟨_, rfl, ?_⟩
    rcases List.mem_cons.mp hm with heq | hm'
    · cases heq
      obtain ⟨E0, l0, h0, heq1, -⟩ := (LiveLe.killHv Γ ks v).2 E1 h1
      rw [hE] at h0; cases h0
      have hh1 : hits e hv x E1 = true := by rw [heq1, hits_with_live]; exact hh
      simp [killE, hh1]
    · obtain ⟨E2, h2, hl2⟩ := killHv_dead_of_mem hE hh hm'
      rw [h1] at h2; cases h2
      cases hk : killE e0 hv0 x0 E1 |>.live
      · rfl
      · exact absurd (killE_live_le hk) (by rw [hl2]; simp)

/-- **The entry kill ends a frame binding that reaches, by a kind a drop
    ends, a root an argument holds a view of in memory.** -/
theorem thruPre_dead {Γ : Ctx} {args : List Var} {v r : Var} {E : Entry} (hE : Γ v = some E)
    (hv : v ∉ args) (hr : r ∈ callR Γ args) (hh : hits .drop (argE Γ r).ty.holdsView r E = true) :
    ∃ E', thruPre Γ args v = some E' ∧ E'.live = false := by
  rw [thruPre_frame hv]
  exact killHv_dead_of_mem hE hh (List.mem_map.mpr ⟨r, hr, rfl⟩)

end A2
