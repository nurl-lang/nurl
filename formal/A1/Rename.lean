import A1.Wf

/-! A1 — a callee's body, checked once against its own view of its
parameters, is well-typed where a call places it.

The call renames the callee's variables apart from the caller's (`ρ`).  The
caller's context, as the renamed body sees it, is `canon Γa`: each callee
binding lifted (`liftE`), and every other binding — the frame — as the
caller has it.  A lifted entry may additionally depend on anything the
arguments held (`allKinds R`): those roots are frozen for the call, so
nothing in the body can end them. -/

namespace A1

def Dep.ren (ρ : Var → Var) (d : Dep) : Dep := ⟨ρ d.root, d.kind⟩

def rds (ρ : Var → Var) (ds : List Dep) : List Dep := ds.map (Dep.ren ρ)

def liftMode : Mode → Mode
  | .inout _ => .own
  | m => m

/-- The setting of one call. -/
structure RSetup where
  ρ   : Var → Var
  R   : List Var
  pe  : Var → Entry
  Φ   : Ctx
  Fc  : List Var
  bnd : Var → Option (Eff × Bool)   -- an `inout` parameter's bound and whether it holds views

namespace RSetup
variable (S : RSetup)

open Classical in
noncomputable def inv (y : Var) : Option Var :=
  if h : ∃ v, S.ρ v = y then some (Classical.choose h) else none

def liftE (v : Var) (E : Entry) : Entry :=
  if E.mode = .rootb then { S.pe v with live := E.live } else
    ⟨E.ty, liftMode E.mode, E.live,
     rds S.ρ E.path ++ (if E.mode.ownSlot then [] else allKinds S.R),
     rds S.ρ E.held ++ allKinds S.R⟩

noncomputable def canon (Γa : Ctx) : Ctx := fun y =>
  match S.inv y with
  | some v => (Γa v).map (S.liftE v)
  | none => S.Φ y

end RSetup

/-- What a call setting must satisfy. -/
structure RSetup.OK (S : RSetup) : Prop where
  inj    : ∀ v w, S.ρ v = S.ρ w → v = w
  Rout   : ∀ r ∈ S.R, ∀ v, S.ρ v ≠ r
  Rroot  : ∀ r ∈ S.R, ∃ E, S.Φ r = some E ∧ E.mode.isRoot = true
  Fcout  : ∀ v, S.ρ v ∉ S.Fc
  pe_rb  : ∀ v, (S.pe v).mode = .rootb
  pe_out : ∀ v, ∀ r ∈ roots (S.pe v).vdeps,
             (∀ w, S.ρ w ≠ r) ∧ ∃ E, S.Φ r = some E ∧ E.mode.isRoot = true
  -- the frame: nothing in it depends on the callee's own bindings, and what
  -- depends on an `inout` argument is already ended for everything the
  -- callee may do to it
  Φsat   : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ d ∈ E.vdeps, ∀ v, S.ρ v = d.root →
               ∃ b hv, S.bnd v = some (b, hv) ∧ b.kills hv d.kind = false
  Φwf    : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ r ∈ roots E.vdeps, (∀ v, S.ρ v ≠ r) → ∃ Er, S.Φ r = some Er ∧ Er.mode.isRoot = true
  Φρ     : ∀ v, S.Φ (S.ρ v) = none

/-- The callee's own contexts, as the call sets them up: a borrowed
    parameter depends on nothing it can see, and an `inout` parameter carries
    its bound. -/
def RSetup.AbsOK (S : RSetup) (Γa : Ctx) : Prop :=
  (∀ v E, Γa v = some E → E.mode = .rootb → E.ty = (S.pe v).ty ∧ E.path = [] ∧ E.held = []) ∧
  (∀ v E b, Γa v = some E → E.mode = .inout b →
     ∃ t, E.ty = .vec t ∧ S.bnd v = some (b, t.holdsView)) ∧
  (∀ v bh, S.bnd v = some bh → ∃ E, Γa v = some E ∧ E.mode = .inout bh.1)

namespace RSetup
variable {S : RSetup} {Γa : Ctx}

theorem inv_ρ (h : S.OK) (v : Var) : S.inv (S.ρ v) = some v := by
  unfold inv
  have hex : ∃ w, S.ρ w = S.ρ v := ⟨v, rfl⟩
  rw [dif_pos hex]
  congr
  exact h.inj _ _ (Classical.choose_spec hex)

theorem inv_none {y : Var} (hy : ∀ v, S.ρ v ≠ y) : S.inv y = none := by
  unfold inv
  rw [dif_neg]
  exact fun ⟨v, hv⟩ => hy v hv

theorem canon_ρ (h : S.OK) (Γa : Ctx) (v : Var) : S.canon Γa (S.ρ v) = (Γa v).map (S.liftE v) := by
  simp [canon, inv_ρ h]

theorem canon_frame (Γa : Ctx) {y : Var} (hy : ∀ v, S.ρ v ≠ y) : S.canon Γa y = S.Φ y := by
  simp [canon, inv_none hy]

theorem canon_cases (h : S.OK) (Γa : Ctx) (y : Var) :
    (∃ v, S.ρ v = y ∧ S.canon Γa y = (Γa v).map (S.liftE v)) ∨
    ((∀ v, S.ρ v ≠ y) ∧ S.canon Γa y = S.Φ y) := by
  by_cases hy : ∃ v, S.ρ v = y
  · obtain ⟨v, rfl⟩ := hy; exact Or.inl ⟨v, rfl, canon_ρ h Γa v⟩
  · have hy' : ∀ v, S.ρ v ≠ y := fun v hv => hy ⟨v, hv⟩
    exact Or.inr ⟨hy', canon_frame Γa hy'⟩

theorem mem_rds {ρ : Var → Var} {ds : List Dep} {d : Dep} : d ∈ rds ρ ds ↔ ∃ d0 ∈ ds, d = d0.ren ρ := by
  simp [rds, eq_comm]

theorem mem_allKinds {rs : List Var} {d : Dep} (h : d ∈ allKinds rs) : d.root ∈ rs := by
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.mem_singleton, List.not_mem_nil,
    or_false] at h
  obtain ⟨r, hr, hd⟩ := h
  rcases hd with rfl | rfl | rfl <;> exact hr

theorem liftMode_ownSlot (m : Mode) : (liftMode m).ownSlot = m.ownSlot := by cases m <;> rfl
theorem liftMode_isRoot (m : Mode) : (liftMode m).isRoot = m.isRoot := by cases m <;> rfl
theorem liftMode_rootb {m : Mode} : liftMode m = .rootb ↔ m = .rootb := by cases m <;> simp [liftMode]

theorem mem_liftE_vdeps {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) {d : Dep} :
    d ∈ (S.liftE v E).vdeps ↔ (∃ d0 ∈ E.vdeps, d = d0.ren S.ρ) ∨ d ∈ allKinds S.R := by
  have hv : (S.liftE v E).vdeps = (if E.mode.ownSlot then [] else rds S.ρ E.path ++ allKinds S.R) ++
      (rds S.ρ E.held ++ allKinds S.R) := by
    simp only [liftE, hrb, ↓reduceIte, Entry.vdeps, liftMode_ownSlot]
    cases E.mode.ownSlot <;> simp
  rw [hv]
  unfold Entry.vdeps
  cases ho : E.mode.ownSlot <;> simp [mem_rds] <;> grind

theorem liftE_ty (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) : (S.liftE v E).ty = E.ty := by
  simp [liftE, hrb]

theorem liftE_mode (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) : (S.liftE v E).mode = liftMode E.mode := by
  simp [liftE, hrb]

theorem beq_rootb_liftMode (m : Mode) : (liftMode m == .rootb) = (m == .rootb) := by
  cases m <;> rfl

/-- Hitting a lifted entry is hitting the entry it lifts. -/
theorem hits_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    (e : Eff) (hv : Bool) (x : Var) : hits e hv (S.ρ x) (S.liftE v E) = hits e hv x E := by
  by_cases hrb : E.mode = .rootb
  · obtain ⟨_, hp, hh⟩ := hab.1 v E hE hrb
    have h1 : hits e hv x E = false := by
      unfold hits; simp [Entry.vdeps, hp, hh]
    rw [h1]
    unfold hits
    simp only [liftE, hrb, ↓reduceIte, Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
      beq_iff_eq, not_and, Bool.not_eq_true]
    refine Or.inr fun d hd hr => ?_
    have hvd : ({ S.pe v with live := E.live } : Entry).vdeps = (S.pe v).vdeps := rfl
    rw [hvd] at hd
    exact absurd ((h.pe_out v d.root (List.mem_map_of_mem hd)).1 x hr.symm) id
  · unfold hits
    rw [liftE_ty v hrb, liftE_mode v hrb, beq_rootb_liftMode]
    congr 1
    rw [Bool.eq_iff_iff]
    simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
    constructor
    · rintro ⟨d, hd, hr, hk⟩
      rcases (mem_liftE_vdeps hrb).mp hd with ⟨d0, hd0, rfl⟩ | ha
      · exact ⟨d0, hd0, h.inj _ _ hr, hk⟩
      · exact absurd hr.symm (h.Rout d.root (mem_allKinds ha) x)
    · rintro ⟨d0, hd0, hr, hk⟩
      exact ⟨d0.ren S.ρ, (mem_liftE_vdeps hrb).mpr (Or.inl ⟨d0, hd0, rfl⟩), by simp [Dep.ren, hr], hk⟩

theorem liftE_live (v : Var) (E : Entry) : (S.liftE v E).live = E.live := by
  unfold liftE; split <;> rfl

theorem liftE_dead (v : Var) (E : Entry) :
    S.liftE v { E with live := false } = { S.liftE v E with live := false } := by
  unfold liftE; split <;> simp_all

theorem killE_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    (e : Eff) (hv : Bool) (x : Var) :
    killE e hv (S.ρ x) (S.liftE v E) = S.liftE v (killE e hv x E) := by
  unfold killE
  rw [hits_lift h hab hE]
  split
  · exact (liftE_dead v E).symm
  · rfl

theorem Eff.kills_mono {e b : Eff} (hle : e.le b) (hv : Bool) (k : Kind) (hk : e.kills hv k = true) :
    b.kills hv k = true := by
  unfold Eff.le Eff.rank at hle
  cases e <;> cases b <;> cases k <;> simp_all [Eff.kills]

/-- An effect the callee may have does not touch the frame. -/
def Allowed (S : RSetup) (e : Eff) (hv : Bool) (x : Var) : Prop :=
  S.bnd x = none ∨ ∃ b, S.bnd x = some (b, hv) ∧ e.le b

theorem killE_frame (h : S.OK) {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x)
    {y : Var} {E : Entry} (hy : S.Φ y = some E) : killE e hv (S.ρ x) E = E := by
  by_cases hl : E.live = true
  · unfold killE
    cases hh : hits e hv (S.ρ x) E with
    | false => rfl
    | true =>
      exfalso
      unfold hits at hh
      simp only [Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq,
        List.any_eq_true] at hh
      obtain ⟨hn, d, hd, hr, hk⟩ := hh
      obtain ⟨b, hv', hb, hkb⟩ := h.Φsat y E hy hl hn d hd x hr.symm
      rcases ha with hn' | ⟨b', hb', hle⟩
      · rw [hn'] at hb; cases hb
      · rw [hb] at hb'; cases hb'
        rw [Eff.kills_mono hle _ _ hk] at hkb; cases hkb
  · unfold killE
    split
    · cases E; simp_all
    · rfl

theorem canon_kill (h : S.OK) (hab : S.AbsOK Γa) {e : Eff} {hv : Bool} {x : Var}
    (ha : Allowed S e hv x) : S.canon (kill e hv x Γa) = kill e hv (S.ρ x) (S.canon Γa) := by
  funext y
  rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨hy, hc⟩
  · rw [canon_ρ h, A1.kill, A1.kill, hc]
    cases hE : Γa v with
    | none => rfl
    | some E => simp only [Option.map_some]; rw [killE_lift h hab hE]
  · rw [canon_frame _ hy, A1.kill, hc]
    cases hE : S.Φ y with
    | none => rfl
    | some E => simp only [Option.map_some]; rw [killE_frame h ha hE]

theorem canon_upd (h : S.OK) (Γa : Ctx) (x : Var) (oE : Option Entry) :
    S.canon (upd Γa x oE) = upd (S.canon Γa) (S.ρ x) (oE.map (S.liftE x)) := by
  funext y
  rcases canon_cases h (upd Γa x oE) y with ⟨v, rfl, hc⟩ | ⟨hy, hc⟩
  · rw [hc]
    by_cases hvx : v = x
    · subst hvx; simp
    · rw [upd_ne _ _ hvx, upd_ne _ _ (fun e => hvx (h.inj _ _ e)), canon_ρ h]
  · rw [hc, upd_ne _ _ (fun e => hy x e.symm), canon_frame _ hy]

theorem canon_setE (h : S.OK) (Γa : Ctx) (x : Var) (E : Entry) :
    S.canon (setE Γa x E) = setE (S.canon Γa) (S.ρ x) (S.liftE x E) := by
  unfold setE; rw [canon_upd h]; rfl

theorem canon_exitScope (h : S.OK) (hab : S.AbsOK Γa) {x : Var} (ha : Allowed S .replace false x) :
    S.canon (exitScope x Γa) = exitScope (S.ρ x) (S.canon Γa) := by
  unfold exitScope
  rw [canon_upd h, canon_kill h hab ha]
  rfl

theorem append_sub {a b c d : List Dep} (h1 : a ⊆ b) (h2 : c ⊆ d) : a ++ c ⊆ b ++ d := by
  intro x hx
  rcases List.mem_append.mp hx with h | h
  · exact List.mem_append_left _ (h1 h)
  · exact List.mem_append_right _ (h2 h)

theorem rds_subset {ρ : Var → Var} {a b : List Dep} (hs : a ⊆ b) : rds ρ a ⊆ rds ρ b := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  exact mem_rds.mpr ⟨d0, hs hd0, rfl⟩

theorem liftE_weaker {v : Var} {E E' : Entry} (hw : EntryWeaker E E') :
    EntryWeaker (S.liftE v E) (S.liftE v E') := by
  obtain ⟨ht, hm, hr, hl⟩ := hw
  by_cases hrb : E.mode = .rootb
  · rw [hr hrb]; exact EntryWeaker.refl _
  · have hrb' : E'.mode ≠ .rootb := by rw [hm]; exact hrb
    refine ⟨by rw [liftE_ty v hrb', liftE_ty v hrb, ht], by rw [liftE_mode v hrb', liftE_mode v hrb, hm],
      fun h' => by rw [liftE_mode v hrb, liftMode_rootb] at h'; exact absurd h' hrb, fun hl' => ?_⟩
    rw [liftE_live] at hl'
    obtain ⟨hl0, hp, hh⟩ := hl hl'
    refine ⟨by rw [liftE_live]; exact hl0, fun ho => ?_, ?_⟩
    · rw [liftE_mode v hrb, liftMode_ownSlot] at ho
      simp only [liftE, hrb, hrb', ↓reduceIte, hm, ho, Bool.false_eq_true]
      exact append_sub (rds_subset (hp ho)) (List.Subset.refl _)
    · simp only [liftE, hrb, hrb', ↓reduceIte]
      exact append_sub (rds_subset hh) (List.Subset.refl _)

theorem liftE_root (h : S.OK) {v : Var} {E : Entry} :
    (S.liftE v E).mode.isRoot = E.mode.isRoot := by
  by_cases hrb : E.mode = .rootb
  · simp only [liftE, hrb, ↓reduceIte]; rw [h.pe_rb]
  · rw [liftE_mode v hrb, liftMode_isRoot]

theorem liftE_rootb (h : S.OK) {v : Var} {E : Entry} : (S.liftE v E).mode = .rootb ↔ E.mode = .rootb := by
  by_cases hrb : E.mode = .rootb
  · simp only [liftE, hrb, ↓reduceIte]; rw [h.pe_rb]; simp
  · rw [liftE_mode v hrb, liftMode_rootb]

theorem liftE_ty' (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E) :
    (S.liftE v E).ty = E.ty := by
  by_cases hrb : E.mode = .rootb
  · simp [liftE, hrb, (hab.1 v E hE hrb).1]
  · exact liftE_ty v hrb

theorem canon_root (h : S.OK) {r : Var} {Er : Entry} (hEr : Γa r = some Er) (hro : Er.mode.isRoot = true) :
    ∃ E', S.canon Γa (S.ρ r) = some E' ∧ E'.mode.isRoot = true :=
  ⟨S.liftE r Er, by rw [canon_ρ h, hEr]; rfl, by rw [liftE_root h]; exact hro⟩

theorem canon_frameRoot (h : S.OK) {r : Var} (hr : ∀ v, S.ρ v ≠ r)
    (hex : ∃ Er, S.Φ r = some Er ∧ Er.mode.isRoot = true) :
    ∃ E', S.canon Γa r = some E' ∧ E'.mode.isRoot = true := by
  rw [canon_frame _ hr]; exact hex

/-- The caller's view of a well-formed callee context is well-formed. -/
theorem canon_wf (h : S.OK) (hab : S.AbsOK Γa) (hw : CtxWF Γa) : CtxWF (S.canon Γa) := by
  intro y E' hy hl hn r hr
  rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨hyf, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq] at hy; subst hy
      by_cases hrb : E.mode = .rootb
      · have hvd : (S.liftE v E).vdeps = (S.pe v).vdeps := by simp [liftE, hrb, Entry.vdeps]
        rw [hvd] at hr
        obtain ⟨hout, hex⟩ := h.pe_out v r hr
        exact canon_frameRoot h hout hex
      · rw [liftE_live] at hl
        have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
          rcases hn with h' | h'
          · rw [liftE_ty v hrb] at h'; exact Or.inl h'
          · rw [liftE_rootb h] at h'; exact absurd h' hrb
        obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
        rcases (mem_liftE_vdeps hrb).mp hd with ⟨d0, hd0, rfl⟩ | ha
        · obtain ⟨Er, hEr, hro⟩ := hw v E hE hl hn' d0.root (List.mem_map_of_mem hd0)
          exact canon_root h hEr hro
        · exact canon_frameRoot h (h.Rout _ (mem_allKinds ha)) (h.Rroot _ (mem_allKinds ha))
  · rw [hc] at hy
    by_cases hrr : ∃ v, S.ρ v = r
    · obtain ⟨v, rfl⟩ := hrr
      obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
      obtain ⟨b, hv, hb, _⟩ := h.Φsat y E' hy hl hn d hd v hdr.symm
      obtain ⟨Ev, hEv, hm⟩ := hab.2.2 v (b, hv) hb
      exact canon_root h hEv (by rw [hm]; rfl)
    · have hout : ∀ v, S.ρ v ≠ r := fun v hv => hrr ⟨v, hv⟩
      exact canon_frameRoot h hout (h.Φwf y E' hy hl hn r hr hout)

theorem canon_weaker (h : S.OK) {Γa Γa' : Ctx} (hab' : S.AbsOK Γa') (hw' : CtxWF Γa')
    (hw : Weaker Γa Γa') : Weaker (S.canon Γa) (S.canon Γa') := by
  refine ⟨fun y => ⟨?_, fun E E' h1 h2 => ?_⟩, canon_wf h hab' hw'⟩
  · rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨hy, hc⟩
    · rw [hc, canon_ρ h]; simp only [Option.map_eq_none_iff]; exact (hw.1 v).1
    · rw [hc, canon_frame _ hy]
  · rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨hy, hc⟩
    · rw [hc] at h1; rw [canon_ρ h] at h2
      cases hE : Γa v with
      | none => rw [hE] at h1; cases h1
      | some E0 =>
        cases hE' : Γa' v with
        | none => rw [hE'] at h2; cases h2
        | some E0' =>
          rw [hE] at h1; rw [hE'] at h2
          simp only [Option.map_some, Option.some.injEq] at h1 h2
          subst h1 h2
          exact liftE_weaker ((hw.1 v).2 E0 E0' hE hE')
    · rw [hc] at h1; rw [canon_frame _ hy] at h2
      rw [h1] at h2; cases h2; exact EntryWeaker.refl _

theorem AbsOK.weaker {Γa Γa' : Ctx} (hab : S.AbsOK Γa) (hw : Weaker Γa Γa') : S.AbsOK Γa' := by
  refine ⟨fun v E' hv hm => ?_, fun v E' b hv hm => ?_, fun v bh hb => ?_⟩
  · obtain ⟨E, hE, hwe⟩ := hw.get' hv
    have hm' : E.mode = .rootb := by rw [← hwe.2.1]; exact hm
    rw [hwe.2.2.1 hm']; exact hab.1 v E hE hm'
  · obtain ⟨E, hE, hwe⟩ := hw.get' hv
    rw [hwe.1]; exact hab.2.1 v E b hE (by rw [← hwe.2.1]; exact hm)
  · obtain ⟨E, hE, hm⟩ := hab.2.2 v bh hb
    obtain ⟨E', hE', hwe⟩ := hw.get hE
    exact ⟨E', hE', by rw [hwe.2.1]; exact hm⟩

theorem AbsOK.kill {Γa : Ctx} (hab : S.AbsOK Γa) (e : Eff) (hv : Bool) (x : Var) :
    S.AbsOK (A1.kill e hv x Γa) := by
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_⟩
  · obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A1.kill, hE, Option.map_some, Option.some.injEq] at hv'; subst hv'
    rw [killE_mode] at hm
    rw [killE_ty, killE_path, killE_held]; exact hab.1 v E hE hm
  · obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A1.kill, hE, Option.map_some, Option.some.injEq] at hv'; subst hv'
    rw [killE_mode] at hm; rw [killE_ty]; exact hab.2.1 v E b hE hm
  · obtain ⟨E, hE, hm⟩ := hab.2.2 v bh hb
    exact ⟨killE e hv x E, by simp [A1.kill, hE], by rw [killE_mode, hm]⟩

theorem AbsOK.setE {Γa : Ctx} (hab : S.AbsOK Γa) {x : Var} {E : Entry} (hrb : E.mode ≠ .rootb)
    (hio : ∀ b, E.mode = .inout b → ∃ t, E.ty = .vec t ∧ S.bnd x = some (b, t.holdsView))
    (hbx : ∀ bh, S.bnd x = some bh → E.mode = .inout bh.1) : S.AbsOK (A1.setE Γa x E) := by
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_⟩
  · by_cases hvx : v = x
    · subst hvx; simp only [A1.setE, upd_same, Option.some.injEq] at hv'; subst hv'; exact absurd hm hrb
    · simp only [A1.setE, upd_ne _ _ hvx] at hv'; exact hab.1 v E' hv' hm
  · by_cases hvx : v = x
    · subst hvx; simp only [A1.setE, upd_same, Option.some.injEq] at hv'; subst hv'; exact hio b hm
    · simp only [A1.setE, upd_ne _ _ hvx] at hv'; exact hab.2.1 v E' b hv' hm
  · by_cases hvx : v = x
    · subst hvx; exact ⟨E, by simp [A1.setE], hbx bh hb⟩
    · obtain ⟨E0, h0, hm0⟩ := hab.2.2 v bh hb
      exact ⟨E0, by simp [A1.setE, upd_ne _ _ hvx, h0], hm0⟩

theorem AbsOK.exitScope {Γa : Ctx} (hab : S.AbsOK Γa) {x : Var} (hbx : S.bnd x = none) :
    S.AbsOK (A1.exitScope x Γa) := by
  have hk := hab.kill .replace false x
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_⟩
  · have hvx : v ≠ x := fun e => by subst e; simp [A1.exitScope] at hv'
    simp only [A1.exitScope, upd_ne _ _ hvx] at hv'; exact hk.1 v E' hv' hm
  · have hvx : v ≠ x := fun e => by subst e; simp [A1.exitScope] at hv'
    simp only [A1.exitScope, upd_ne _ _ hvx] at hv'; exact hk.2.1 v E' b hv' hm
  · have hvx : v ≠ x := fun e => by subst e; rw [hbx] at hb; cases hb
    obtain ⟨E0, h0, hm0⟩ := hk.2.2 v bh hb
    exact ⟨E0, by simp [A1.exitScope, upd_ne _ _ hvx, h0], hm0⟩

end RSetup

end A1
