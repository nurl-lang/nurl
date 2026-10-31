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
  pe_held : ∀ v, (S.pe v).held ⊆ allKinds S.R

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
  rw [dite_eq_left hex]
  congr
  exact h.inj _ _ (Classical.choose_spec hex)

theorem inv_none {y : Var} (hy : ∀ v, S.ρ v ≠ y) : S.inv y = none := by
  unfold inv
  rw [dite_eq_right]
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
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
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
  S.bnd x = none ∨ ∃ b hb, S.bnd x = some (b, hb) ∧ ∀ k, e.kills hv k = true → b.kills hb k = true

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
      rcases ha with hn' | ⟨b', hb'⟩
      · rw [hn'] at hb; cases hb
      · obtain ⟨hbb, hb', hle⟩ := hb'
        rw [hb] at hb'; cases hb'
        rw [hle _ hk] at hkb; cases hkb
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
      simp only [liftE, hrb, ↓reduceIte, hm, ho, Bool.false_eq_true]
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

theorem liftE_ty' (_h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E) :
    (S.liftE v E).ty = E.ty := by
  by_cases hrb : E.mode = .rootb
  · simp [liftE, hrb, (hab.1 v E hE hrb).1]
  · exact liftE_ty v hrb

theorem canon_root (h : S.OK) {r : Var} {Er : Entry} (hEr : Γa r = some Er) (hro : Er.mode.isRoot = true) :
    ∃ E', S.canon Γa (S.ρ r) = some E' ∧ E'.mode.isRoot = true :=
  ⟨S.liftE r Er, by rw [canon_ρ h, hEr]; rfl, by rw [liftE_root h]; exact hro⟩

theorem canon_frameRoot (_h : S.OK) {r : Var} (hr : ∀ v, S.ρ v ≠ r)
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

theorem EntryWeaker.mk' {E E' : Entry} (ht : E'.ty = E.ty) (hm : E'.mode = E.mode)
    (hrb : E.mode ≠ .rootb) (hl : E'.live = E.live) (hp : E.mode.ownSlot = false → E.path ⊆ E'.path)
    (hh : E.held ⊆ E'.held) : EntryWeaker E E' :=
  ⟨ht, hm, fun h' => absurd h' hrb, fun h' => ⟨by rw [← hl]; exact h', hp, hh⟩⟩

theorem allKinds_comp {R : List Var} (k : Kind) :
    (allKinds R).map (fun d => (⟨d.root, comp d.kind k⟩ : Dep)) ⊆ allKinds R := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
  have hr := mem_allKinds hd0
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
    or_false]
  exact ⟨d0.root, hr, by cases comp d0.kind k <;> simp⟩

/-- What a lifted binding lends is what the binding it lifts lends, renamed,
    or something the arguments held. -/
theorem derive_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (k : Kind) :
    derive (S.ρ y) (S.liftE y Ey) k ⊆ rds S.ρ (derive y Ey k) ++ allKinds S.R := by
  intro d hd
  unfold derive at hd ⊢
  rw [liftE_root h] at hd
  cases hrt : Ey.mode.isRoot with
  | true =>
    simp only [hrt, ↓reduceIte, List.mem_singleton] at hd ⊢
    subst hd
    refine List.mem_append_left _ (mem_rds.mpr ⟨_, List.mem_singleton_self _, ?_⟩)
    simp [Dep.ren, liftE_ty' h hab hy]
  | false =>
    simp only [hrt, Bool.false_eq_true, ↓reduceIte] at hd ⊢
    have hrb : Ey.mode ≠ .rootb := fun e => by rw [e] at hrt; cases hrt
    have hos : Ey.mode.ownSlot = false := by cases hm : Ey.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    have hpath : (S.liftE y Ey).path = rds S.ρ Ey.path ++ allKinds S.R := by simp [liftE, hrb, hos]
    rw [hpath, List.map_append] at hd
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨d1, hd1, rfl⟩ := List.mem_map.mp hd
      obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd1
      exact List.mem_append_left _ (mem_rds.mpr ⟨_, List.mem_map_of_mem hd0, rfl⟩)
    · exact List.mem_append_right _ (allKinds_comp k hd)

theorem held_lift (h : S.OK) (_hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (_hy : Γa y = some Ey) :
    (S.liftE y Ey).held ⊆ rds S.ρ Ey.held ++ allKinds S.R := by
  by_cases hrb : Ey.mode = .rootb
  · simp only [liftE, hrb, ↓reduceIte]
    exact fun d hd => List.mem_append_right _ (h.pe_held y hd)
  · simp [liftE, hrb]

theorem exprT_ren (h : S.OK) (hab : S.AbsOK Γa) {e : Expr} (he : ExprT Γa e) :
    ExprT (S.canon Γa) (e.rename S.ρ) := by
  induction he with
  | lit => exact ExprT.lit
  | var hx hl ht =>
    exact ExprT.var (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl)
      (by rw [liftE_ty' h hab hx]; exact ht)
  | add _ _ iha ihb => exact ExprT.add iha ihb
  | lt _ _ iha ihb => exact ExprT.lt iha ihb
  | len hx hl ht =>
    exact ExprT.len (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl)
      (by rw [liftE_ty' h hab hx]; exact ht)
  | slen hx hl ht =>
    exact ExprT.slen (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl)
      (by rw [liftE_ty' h hab hx]; exact ht)

theorem liftE_indep {E : Entry} (hrb : E.mode ≠ .rootb) (x v : Var) : S.liftE x E = S.liftE v E := by
  simp [liftE, hrb]

theorem allowed_own (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (hm : Ey.mode = .own)
    (e : Eff) (hv : Bool) : Allowed S e hv y := by
  left
  cases hb : S.bnd y with
  | none => rfl
  | some bh =>
    obtain ⟨E, hE, hmE⟩ := hab.2.2 y bh hb
    rw [hy] at hE; cases hE; rw [hm] at hmE; cases hmE

theorem allowed_canDo (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} {t : Ty} (hy : Γa y = some Ey)
    (ht : Ey.ty = .vec t) {e : Eff} (hcan : canDo Ey.mode e) : Allowed S e t.holdsView y := by
  rcases hcan with hm | ⟨b, hm, hle⟩
  · exact allowed_own hab hy hm e _
  · obtain ⟨t', ht', hb⟩ := hab.2.1 y Ey b hy hm
    rw [ht] at ht'; cases ht'
    exact Or.inr ⟨b, _, hb, fun k hk => Eff.kills_mono hle _ k hk⟩

theorem canDo_lift {m : Mode} {e : Eff} (h : canDo m e) : canDo (liftMode m) e := by
  rcases h with rfl | ⟨b, rfl, _⟩ <;> exact Or.inl rfl

theorem intE_lift (x : Var) : EntryWeaker intE (S.liftE x intE) := by
  have he : S.liftE x intE = ⟨.int, .bor, true, allKinds S.R, allKinds S.R⟩ := by
    simp [liftE, intE, liftMode, rds, Mode.ownSlot]
  rw [he]
  exact EntryWeaker.mk' rfl rfl (by simp [intE]) rfl (fun _ => by simp [intE]) (by simp [intE])

theorem elemE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) : EntryWeaker (elemE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (elemE y Ey t)) := by
  have hl := held_lift h hab hy
  cases t with
  | int =>
    show EntryWeaker intE (S.liftE x intE)
    exact intE_lift x
  | slice s =>
    refine EntryWeaker.mk' (by simp [elemE, liftE]) (by simp [elemE, liftE, liftMode])
      (by simp [elemE]) (by simp [elemE, liftE]) (fun _ => ?_) ?_
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact hl
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte]; exact hl
  | vec s =>
    refine EntryWeaker.mk' (by simp [elemE, liftE]) (by simp [elemE, liftE, liftMode])
      (by simp [elemE]) (by simp [elemE, liftE]) (fun _ => ?_) ?_
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .inner
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte]; exact hl

theorem popE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) : EntryWeaker (popE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (popE y Ey t)) := by
  cases t with
  | vec s =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    simp only [popE, liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
  | int => exact elemE_lift h hab hy .int x
  | slice s => exact elemE_lift h hab hy (.slice s) x

/-- A right-hand side of the callee, where the call places it. -/
theorem RhsT.ren (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {r : Rhs} {E : Entry} {Γa1 : Ctx}
    (hr : RhsT Γa Fa r E Γa1) :
    ∃ E', RhsT (S.canon Γa) S.Fc (r.rename S.ρ) E' (S.canon Γa1) ∧ ∀ x, EntryWeaker E' (S.liftE x E) := by
  cases hr with
  | expr he =>
    exact ⟨intE, RhsT.expr (exprT_ren h hab he), fun x => intE_lift x⟩
  | new ht =>
    refine ⟨_, RhsT.new ht, fun x => ?_⟩
    exact EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode]) (by simp) (by simp [liftE])
      (fun h' => by simp [Mode.ownSlot] at h') (by simp)
  | @moveOwn y Ey hy hl hm hyF =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y) { S.liftE y Ey with live := false } := by
      rw [canon_setE h, canon_kill h hab (allowed_own hab hy hm _ _), liftE_dead]
    rw [hctx]
    refine ⟨_, RhsT.moveOwn hc (by rw [liftE_live]; exact hl) (by rw [liftE_mode y hrb, hm]; rfl)
      (h.Fcout y), fun x => ?_⟩
    have he : S.liftE x ⟨Ey.ty, .own, true, [], Ey.held⟩ =
        ⟨(S.liftE y Ey).ty, .own, true, [], (S.liftE y Ey).held⟩ := by
      simp [liftE, hrb, liftMode, rds, Mode.ownSlot]
    rw [he]; exact EntryWeaker.refl _
  | @copyRoot y Ey hy hl hm =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    refine ⟨_, RhsT.copyRoot hc (by rw [liftE_live]; exact hl) (by rw [liftE_rootb h]; exact hm),
      fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; exact (liftE_ty' h hab hy).symm)
      (by simp [liftE, liftMode]) (by simp) (by simp [liftE]) (fun _ => ?_) ?_
    · simp only [liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .self
    · simp only [liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
  | @copyBor y _ hy hl hm =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y E) := by rw [canon_ρ h, hy]; rfl
    have hrb : E.mode ≠ .rootb := by rw [hm]; simp
    refine ⟨_, RhsT.copyBor hc (by rw [liftE_live]; exact hl) (by rw [liftE_mode y hrb, hm]; rfl),
      fun x => ?_⟩
    rw [liftE_indep hrb x y]; exact EntryWeaker.refl _
  | @borrow y Ey t hy hl ht =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    refine ⟨_, RhsT.borrow hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht),
      fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; exact (liftE_ty' h hab hy).symm)
      (by simp [liftE, liftMode]) (by simp) (by simp [liftE]) (fun _ => ?_) ?_
    · simp only [liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .self
    · simp only [liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
  | @«at» y i Ey t hy hl ht hi =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    exact ⟨_, RhsT.at hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht)
      (exprT_ren h hab hi), fun x => elemE_lift h hab hy t x⟩
  | @view y Ey t hy hl ht hhv =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    refine ⟨_, RhsT.view hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht) hhv,
      fun x => ?_⟩
    refine EntryWeaker.mk' (by simp [liftE]) (by simp [liftE, liftMode])
      (by simp) (by simp [liftE]) (fun _ => ?_) ?_
    · simp only [liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .view
    · simp only [liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
  | @sat y i Ey t hy hl ht hi =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    exact ⟨_, RhsT.sat hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht)
      (exprT_ren h hab hi), fun x => elemE_lift h hab hy t x⟩
  | @pop y Ey t hy hl ht hcan hyF =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    have hrb : Ey.mode ≠ .rootb := by
      rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp
    rw [canon_kill h hab (allowed_canDo hab hy ht hcan)]
    exact ⟨_, RhsT.pop hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht)
      (by rw [liftE_mode y hrb]; exact canDo_lift hcan) (h.Fcout y), fun x => popE_lift h hab hy t x⟩

theorem pushArg_ren (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {y : Var} {Ey : Entry} {t : Ty}
    {D : List Dep} {Γa1 : Ctx} (hy : Γa y = some Ey) (hp : PushArg Γa Fa y Ey t D Γa1) :
    ∃ D', PushArg (S.canon Γa) S.Fc (S.ρ y) (S.liftE y Ey) t D' (S.canon Γa1) ∧
      D' ⊆ rds S.ρ D ++ allKinds S.R := by
  cases hp with
  | move hm hyF =>
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y) { S.liftE y Ey with live := false } := by
      rw [canon_setE h, canon_kill h hab (allowed_own hab hy hm _ _), liftE_dead]
    rw [hctx]
    exact ⟨_, PushArg.move (by rw [liftE_mode y hrb, hm]; rfl) (h.Fcout y), held_lift h hab hy⟩
  | int => exact ⟨[], PushArg.int, by simp⟩
  | slice hm =>
    refine ⟨_, PushArg.slice ?_, ?_⟩
    · rcases hm with hm | hm
      · left; rw [liftE_mode y (by rw [hm]; simp), hm]; rfl
      · right; rw [liftE_rootb h]; exact hm
    · intro d hd
      rcases List.mem_append.mp hd with hd | hd
      · rcases List.mem_append.mp (derive_lift h hab hy .self hd) with h1 | h1
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
          exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_left _ hd0, rfl⟩)
        · exact List.mem_append_right _ h1
      · rcases List.mem_append.mp (held_lift h hab hy hd) with h1 | h1
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
          exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_right _ hd0, rfl⟩)
        · exact List.mem_append_right _ h1

theorem mem_allKinds_iff {L : List Var} {d : Dep} : d ∈ allKinds L ↔ d.root ∈ L := by
  constructor
  · exact mem_allKinds
  · intro hd
    simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false]
    exact ⟨d.root, hd, by obtain ⟨r, k⟩ := d; cases k <;> simp⟩

/-- Pointwise: each entry of `Γ` is at least as strong as `Γ'`'s. -/
def PW (Γ Γ' : Ctx) : Prop :=
  ∀ v, (Γ v = none ↔ Γ' v = none) ∧ ∀ E E', Γ v = some E → Γ' v = some E' → EntryWeaker E E'

theorem PW.weaker {Γ Γ' : Ctx} (h : PW Γ Γ') (hw : CtxWF Γ') : Weaker Γ Γ' := ⟨h, hw⟩

theorem PW.refl (Γ : Ctx) : PW Γ Γ := fun v => ⟨Iff.rfl, fun E E' h1 h2 => by
  rw [h1] at h2; cases h2; exact EntryWeaker.refl _⟩

theorem PW.kill {Γ Γ' : Ctx} (h : PW Γ Γ') (e : Eff) (hv : Bool) (x : Var) :
    PW (A1.kill e hv x Γ) (A1.kill e hv x Γ') := by
  intro v
  refine ⟨?_, fun E E' h1 h2 => ?_⟩
  · simp only [A1.kill, Option.map_eq_none_iff]; exact (h v).1
  · simp only [A1.kill] at h1 h2
    cases hE : Γ v with
    | none => rw [hE] at h1; cases h1
    | some E0 =>
      cases hE' : Γ' v with
      | none => rw [hE'] at h2; cases h2
      | some E0' =>
        rw [hE] at h1; rw [hE'] at h2; cases h1; cases h2
        exact killE_weaker ((h v).2 E0 E0' hE hE')

theorem PW.setE {Γ Γ' : Ctx} (h : PW Γ Γ') {x : Var} {E E' : Entry} (he : EntryWeaker E E') :
    PW (A1.setE Γ x E) (A1.setE Γ' x E') := by
  intro v
  by_cases hvx : v = x
  · subst hvx; simp only [A1.setE, upd_same, reduceCtorEq, iff_self, Option.some.injEq, true_and]
    intro a b ha hb; subst ha hb; exact he
  · simp only [A1.setE, upd_ne _ _ hvx]; exact h v

theorem getD_map {args : List Var} {i : Nat} (hi : i < args.length) (ρ : Var → Var) :
    (args.map ρ).getD i 0 = ρ (args.getD i 0) := by
  simp [List.getD, hi]

theorem argE_canon (h : S.OK) {a : Var} {Ea : Entry} (ha : Γa a = some Ea) :
    argE (S.canon Γa) (S.ρ a) = S.liftE a Ea := by
  unfold argE; rw [canon_ρ h, ha]; rfl

theorem sub_rds_append {a b : List Dep} {L : List Dep} (ha : a ⊆ rds S.ρ L ++ allKinds S.R)
    (hb : b ⊆ rds S.ρ L ++ allKinds S.R) : a ++ b ⊆ rds S.ρ L ++ allKinds S.R := by
  intro d hd; rcases List.mem_append.mp hd with h | h
  · exact ha h
  · exact hb h

theorem sub_mono {a L L' : List Dep} (ha : a ⊆ rds S.ρ L ++ allKinds S.R) (hL : L ⊆ L') :
    a ⊆ rds S.ρ L' ++ allKinds S.R :=
  fun _ hd => append_sub (rds_subset hL) (List.Subset.refl _) (ha hd)

theorem argDeps_lift (h : S.OK) (hab : S.AbsOK Γa) {args : List Var} {j : Nat} (hj : j < args.length)
    {Ea : Entry} (hEa : Γa (args.getD j 0) = some Ea) (k : Kind) :
    argDeps (S.canon Γa) (args.map S.ρ) (j, k) ⊆ rds S.ρ (argDeps Γa args (j, k)) ++ allKinds S.R := by
  unfold argDeps
  simp only [getD_map hj, argE_canon h hEa, liftE_ty' h hab hEa]
  have hae : argE Γa (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
  rw [hae]
  split
  · simp
  · exact derive_lift h hab hEa k

theorem heldOfArgs_lift (h : S.OK) (hab : S.AbsOK Γa) {args : List Var}
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) :
    heldOfArgs (S.canon Γa) (args.map S.ρ) ⊆ rds S.ρ (heldOfArgs Γa args) ++ allKinds S.R := by
  intro d hd
  unfold heldOfArgs at hd ⊢
  rw [mem_allKinds_iff] at hd
  simp only [List.flatMap_map, List.mem_flatMap] at hd
  obtain ⟨a, ha, hda⟩ := hd
  obtain ⟨Ea, hEa⟩ := hargs a ha
  rw [argE_canon h hEa, liftE_ty' h hab hEa] at hda
  have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
  split at hda
  · simp at hda
  · rename_i hn
    obtain ⟨d1, hd1, hdr⟩ := List.mem_map.mp hda
    rcases List.mem_append.mp (held_lift h hab hEa hd1) with h1 | h1
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
      refine List.mem_append_left _ (mem_rds.mpr ⟨⟨d0.root, d.kind⟩, ?_, ?_⟩)
      · rw [mem_allKinds_iff]
        simp only [List.mem_flatMap]
        exact ⟨a, ha, by rw [hae, ite_eq_right hn]; exact List.mem_map_of_mem hd0⟩
      · obtain ⟨r, k⟩ := d; simp only [Dep.ren] at hdr ⊢; rw [← hdr]
    · exact List.mem_append_right _ (mem_allKinds_iff.mpr (hdr ▸ mem_allKinds h1))

theorem flatMap_lift {l : List (Nat × Kind)} {fc fa : Nat × Kind → List Dep}
    (hf : ∀ jk ∈ l, fc jk ⊆ rds S.ρ (fa jk) ++ allKinds S.R) :
    l.flatMap fc ⊆ rds S.ρ (l.flatMap fa) ++ allKinds S.R := by
  intro d hd
  obtain ⟨jk, hjk, hd'⟩ := List.mem_flatMap.mp hd
  rcases List.mem_append.mp (hf jk hjk hd') with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_flatMap.mpr ⟨jk, hjk, hd0⟩, rfl⟩)
  · exact List.mem_append_right _ h1

theorem outHeld_lift (h : S.OK) (hab : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (houts : ∀ o ∈ fn.outHolds, o.2.1 < args.length)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (i : Nat) :
    outHeld (S.canon Γa) fn (args.map S.ρ) i ⊆ rds S.ρ (outHeld Γa fn args i) ++ allKinds S.R := by
  intro d hd
  unfold outHeld at hd ⊢
  obtain ⟨o, ho, hd'⟩ := List.mem_flatMap.mp hd
  have hom := (List.mem_filter.mp ho).1
  obtain ⟨Ea, hEa⟩ := hargs o.2.1 (houts o hom)
  rcases List.mem_append.mp (argDeps_lift h hab (houts o hom) hEa o.2.2 hd') with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_flatMap.mpr ⟨o, ho, hd0⟩, rfl⟩)
  · exact List.mem_append_right _ h1

theorem resMode_ne (fn : Fn) : resMode fn ≠ .rootb := by unfold resMode; split <;> simp
theorem liftMode_resMode (fn : Fn) : liftMode (resMode fn) = resMode fn := by unfold resMode; split <;> rfl

theorem app_lift {a b a0 b0 : List Dep} (ha : a ⊆ rds S.ρ a0 ++ allKinds S.R)
    (hb : b ⊆ rds S.ρ b0 ++ allKinds S.R) : a ++ b ⊆ rds S.ρ (a0 ++ b0) ++ allKinds S.R := by
  intro d hd
  simp only [rds, List.map_append, List.mem_append] at hd ha hb ⊢
  rcases hd with hd | hd
  · rcases List.mem_append.mp (ha hd) with h1 | h1
    · exact Or.inl (Or.inl h1)
    · exact Or.inr h1
  · rcases List.mem_append.mp (hb hd) with h1 | h1
    · exact Or.inl (Or.inr h1)
    · exact Or.inr h1

theorem liftE_callRes (Γ : Ctx) (fn : Fn) (args : List Var) (x : Var) :
    S.liftE x (callRes Γ fn args) =
      ⟨fn.resTy, resMode fn, true,
       rds S.ρ (fn.lends.flatMap (argDeps Γ args) ++ heldOfArgs Γ args) ++
         (if (resMode fn).ownSlot then [] else allKinds S.R),
       rds S.ρ (fn.rholds.flatMap (argDeps Γ args) ++ heldOfArgs Γ args) ++ allKinds S.R⟩ := by
  simp only [liftE, callRes, resMode_ne fn, ↓reduceIte, liftMode_resMode]
  rfl

theorem callRes_lift (h : S.OK) (hab : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (hl : ∀ jk ∈ fn.lends ++ fn.rholds, jk.1 < args.length)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (x : Var) :
    EntryWeaker (callRes (S.canon Γa) fn (args.map S.ρ)) (S.liftE x (callRes Γa fn args)) := by
  have hall : ∀ a ∈ args, ∃ Ea, Γa a = some Ea := by
    intro a ha; obtain ⟨i, hi, rfl⟩ := mem_args ha; exact hargs i hi
  have hA : ∀ jk ∈ fn.lends ++ fn.rholds, argDeps (S.canon Γa) (args.map S.ρ) jk ⊆
      rds S.ρ (argDeps Γa args jk) ++ allKinds S.R := by
    intro jk hjk
    obtain ⟨Ea, hEa⟩ := hargs jk.1 (hl jk hjk)
    exact argDeps_lift h hab (hl jk hjk) hEa jk.2
  have hH := heldOfArgs_lift h hab hall
  rw [liftE_callRes]
  refine EntryWeaker.mk' rfl rfl (resMode_ne fn) rfl (fun _ => ?_) ?_
  · rename_i ho
    simp only [callRes] at ho
    simp only [ho, Bool.false_eq_true, ↓reduceIte]
    exact app_lift (S := S) (flatMap_lift (S := S) (fun jk hjk => hA jk (List.mem_append_left _ hjk))) hH
  · exact app_lift (S := S) (flatMap_lift (S := S) (fun jk hjk => hA jk (List.mem_append_right _ hjk))) hH

theorem callPostAux_lift (h : S.OK) (hab0 : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (houts : ∀ o ∈ fn.outHolds, o.2.1 < args.length)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx) (Γc : Ctx),
      (∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea) →
      S.AbsOK Γ → PW Γc (S.canon Γ) →
      PW (callPostAux (S.canon Γa) fn (args.map S.ρ) ps (as.map S.ρ) i Γc)
        (S.canon (callPostAux Γa fn args ps as i Γ))
  | [], _, _, _, _, _, _, hpw => by simpa [callPostAux] using hpw
  | _ :: _, [], _, _, _, _, _, hpw => by simpa [callPostAux] using hpw
  | (pm, t) :: ps, a :: as, i, Γ, Γc, hz, hab, hpw => by
    obtain ⟨Ea, hEa, hpo⟩ := hz ((pm, t), a) (by simp)
    have hz' : ∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea :=
      fun pa hpa => hz pa (by simp [hpa])
    have hae : argE (S.canon Γa) (S.ρ a) = S.liftE a Ea := argE_canon h hEa
    have hae0 : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    cases pm with
    | inp => exact callPostAux_lift h hab0 houts hargs ps as (i + 1) Γ Γc hz' hab hpw
    | sink =>
      obtain ⟨_, hm, _⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by rw [hm]; simp
      simp only [callPostAux, List.map_cons]
      apply callPostAux_lift h hab0 houts hargs ps as (i + 1) _ _ hz'
      · refine (hab.kill _ _ _).setE (by simp [hae0, hrb]) (fun b hb => ?_) (fun bh hb => ?_)
        · simp [hae0, hm] at hb
        · obtain ⟨E, hE, hmE⟩ := hab0.2.2 a bh hb
          rw [hEa] at hE; cases hE; rw [hm] at hmE; cases hmE
      · rw [canon_setE h, canon_kill h hab (allowed_own hab0 hEa hm _ _), hae, hae0, liftE_dead]
        exact PW.setE (hpw.kill _ _ _) (EntryWeaker.refl _)
    | inout b =>
      obtain ⟨ht, hcan, s, rfl⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
      simp only [callPostAux, List.map_cons]
      apply callPostAux_lift h hab0 houts hargs ps as (i + 1) _ _ hz'
      · refine (hab.kill _ _ _).setE (by simp [hae0, hrb]) (fun b' hb => ?_) (fun bh hb => ?_)
        · simp only [hae0] at hb ⊢
          obtain ⟨t', ht', hbd⟩ := hab0.2.1 a Ea b' hEa hb
          exact ⟨t', ht', hbd⟩
        · obtain ⟨E, hE, hmE⟩ := hab0.2.2 a bh hb
          rw [hEa] at hE; cases hE; simp only [hae0]; exact hmE
      · simp only [Ty.elem]
        rw [canon_setE h, canon_kill h hab (allowed_canDo hab0 hEa ht hcan), hae, hae0]
        refine PW.setE (hpw.kill _ _ _) ?_
        refine EntryWeaker.mk' ?_ ?_ ?_ ?_ ?_ ?_
        · simp [liftE, hrb]
        · simp [liftE, hrb]
        · show (S.liftE a Ea).mode ≠ .rootb
          exact fun e => hrb ((liftE_rootb h).mp e)
        · simp [liftE, hrb]
        · intro ho; simp [liftE, hrb]
        · simp only [liftE, hrb, ↓reduceIte]
          have h1 := outHeld_lift h hab0 houts hargs i
          have h2 := heldOfArgs_lift h hab0 (fun a ha => by
            obtain ⟨j, hj, rfl⟩ := mem_args ha; exact hargs j hj)
          exact app_lift (S := S) (app_lift (S := S) (List.Subset.refl _) h1) h2

theorem mem_zip_getD {ps : List (PMode × Ty)} {as : List Var} {pa : (PMode × Ty) × Var}
    (h : pa ∈ ps.zip as) : ∃ k, ∃ hk : k < ps.length, k < as.length ∧ pa = (ps[k], as.getD k 0) := by
  obtain ⟨k, hk, he⟩ := List.getElem_of_mem h
  have hk1 : k < ps.length := by simp at hk; omega
  have hk2 : k < as.length := by simp at hk; omega
  refine ⟨k, hk1, hk2, ?_⟩
  rw [← he]; simp [List.getD, hk2]

theorem roots_liftE_ρ (h : S.OK) (_hab : S.AbsOK Γa) {v a : Var} {E : Entry} (_hE : Γa v = some E)
    (hn : a ∉ roots E.vdeps) : S.ρ a ∉ roots (S.liftE v E).vdeps := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  by_cases hrb : E.mode = .rootb
  · have hvd : (S.liftE v E).vdeps = (S.pe v).vdeps := by simp [liftE, hrb, Entry.vdeps]
    rw [hvd] at hd
    exact (h.pe_out v _ (List.mem_map_of_mem hd)).1 a hdr.symm
  · rcases (mem_liftE_vdeps hrb).mp hd with ⟨d0, hd0, rfl⟩ | ha
    · apply hn
      have : d0.root = a := h.inj _ _ hdr
      exact this ▸ List.mem_map_of_mem hd0
    · exact h.Rout _ (mem_allKinds ha) a hdr.symm

theorem paramOK_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {pm : PMode} {t : Ty} (hp : paramOK pm t E) : paramOK pm t (S.liftE v E) := by
  cases pm with
  | inp => show (S.liftE v E).ty = t; rw [liftE_ty' h hab hE]; exact hp
  | sink =>
    obtain ⟨ht, hm, hs⟩ := hp
    have hrb : E.mode ≠ .rootb := by rw [hm]; simp
    exact ⟨by rw [liftE_ty v hrb]; exact ht, by rw [liftE_mode v hrb, hm]; rfl, hs⟩
  | inout b =>
    obtain ⟨ht, hcan, hs⟩ := hp
    have hrb : E.mode ≠ .rootb := by rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
    exact ⟨by rw [liftE_ty v hrb]; exact ht, by rw [liftE_mode v hrb]; exact canDo_lift hcan, hs⟩

/-- A call in the callee's body, where the call places it. -/
theorem callT_ren (h : S.OK) (hab : S.AbsOK Γa) {P : Prog} (hP : ProgOK P) {Fa : List Var} {f : Nat}
    {args : List Var} {E : Entry} {Γa1 : Ctx} (hc : CallT P Γa Fa f args E Γa1) :
    ∃ E' Γ', CallT P (S.canon Γa) S.Fc f (args.map S.ρ) E' Γ' ∧ PW Γ' (S.canon Γa1) ∧
      ∀ x, EntryWeaker E' (S.liftE x E) := by
  obtain ⟨fn, hf, hlen, hargs, rfl, rfl⟩ := hc
  have hfn : FnOK P fn := hP fn (List.mem_of_getElem? hf)
  obtain ⟨_, _, _, _, _, _, hlends, hrholds, houts, _⟩ := hfn
  have hex : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea := by
    intro j hj; obtain ⟨Ea, h1, _⟩ := hargs j (hlen ▸ hj); exact ⟨Ea, h1⟩
  have hlr : ∀ jk ∈ fn.lends ++ fn.rholds, jk.1 < args.length := by
    intro jk hjk
    rcases List.mem_append.mp hjk with hj | hj
    · obtain ⟨hl, _⟩ := hlends jk hj; omega
    · obtain ⟨hl, _⟩ := hrholds jk hj; omega
  have hou : ∀ o ∈ fn.outHolds, o.2.1 < args.length := by
    intro o ho; obtain ⟨hl, _⟩ := houts o ho; omega
  refine ⟨_, _, ⟨fn, hf, by simp [hlen], fun i hi => ?_, rfl, rfl⟩, ?_, callRes_lift h hab hlr hex⟩
  · obtain ⟨Ea, hEa, hl, hok, hmv⟩ := hargs i hi
    have hia : i < args.length := hlen ▸ hi
    rw [getD_map hia]
    refine ⟨_, by rw [canon_ρ h, hEa]; rfl, by rw [liftE_live]; exact hl, paramOK_lift h hab hEa hok,
      fun hm => ?_⟩
    obtain ⟨hF, hroot, hoth⟩ := hmv hm
    refine ⟨h.Fcout _, roots_liftE_ρ h hab hEa hroot, fun j hj hji => ?_⟩
    have hja : j < args.length := hlen ▸ hj
    obtain ⟨hne, hnr⟩ := hoth j hj hji
    obtain ⟨Ej, hEj⟩ := hex j hja
    rw [getD_map hja, argE_canon h hEj]
    have hae : argE Γa (args.getD j 0) = Ej := by unfold argE; rw [hEj]; rfl
    rw [hae] at hnr
    exact ⟨fun e => hne (h.inj _ _ e), roots_liftE_ρ h hab hEj hnr⟩
  · unfold callPost
    apply callPostAux_lift h hab hou hex fn.params args 0 Γa _ _ hab (PW.refl _)
    intro pa hpa
    obtain ⟨k, hk, _, rfl⟩ := mem_zip_getD hpa
    obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
    exact ⟨Ea, hEa, hok⟩

/-! ### The callee's contexts stay as the call set them up -/

theorem AbsOK.setE' {Γ0 Γ1 : Ctx} (hab : S.AbsOK Γ1) (hab0 : S.AbsOK Γ0) {x : Var} {E0 E : Entry}
    (hx : Γ0 x = some E0) (hm : E.mode = E0.mode) (ht : E.ty = E0.ty) (hrb : E.mode ≠ .rootb) :
    S.AbsOK (A1.setE Γ1 x E) := by
  refine hab.setE hrb (fun b hb => ?_) (fun bh hb => ?_)
  · rw [ht]; exact hab0.2.1 x E0 b hx (hm ▸ hb)
  · obtain ⟨E', hE', hm'⟩ := hab0.2.2 x bh hb
    rw [hx] at hE'; cases hE'; rw [hm]; exact hm'

theorem AbsOK.fresh {Γ : Ctx} (hab : S.AbsOK Γ) {x : Var} (hx : Γ x = none) : S.bnd x = none := by
  cases hb : S.bnd x with
  | none => rfl
  | some bh => obtain ⟨E, hE, _⟩ := hab.2.2 x bh hb; rw [hx] at hE; cases hE

theorem AbsOK.add {Γ Γ1 : Ctx} (hab0 : S.AbsOK Γ) (hab : S.AbsOK Γ1) {x : Var} (hx : Γ x = none)
    {E : Entry} (hm : E.mode = .own ∨ E.mode = .bor) : S.AbsOK (A1.setE Γ1 x E) := by
  have hbx := hab0.fresh hx
  refine hab.setE (by rcases hm with hm | hm <;> rw [hm] <;> simp) (fun b hb => ?_) (fun bh hb => ?_)
  · rcases hm with hm | hm <;> rw [hm] at hb <;> cases hb
  · rw [hbx] at hb; cases hb

theorem RhsT.absOK {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1)
    (hab : S.AbsOK Γ) : S.AbsOK Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ hm _ =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp)
  | pop => exact hab.kill _ _ _
  | _ => exact hab

theorem RhsT.out {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1) :
    (E.mode = .own ∨ E.mode = .bor) ∧ E.live = true := by
  cases hr with
  | expr => exact ⟨Or.inr rfl, rfl⟩
  | new => exact ⟨Or.inl rfl, rfl⟩
  | moveOwn => exact ⟨Or.inl rfl, rfl⟩
  | copyRoot => exact ⟨Or.inr rfl, rfl⟩
  | copyBor _ hl hm => exact ⟨Or.inr hm, hl⟩
  | borrow => exact ⟨Or.inr rfl, rfl⟩
  | @«at» _ _ _ t => cases t <;> exact ⟨Or.inr rfl, rfl⟩
  | view => exact ⟨Or.inr rfl, rfl⟩
  | @sat _ _ _ t => cases t <;> exact ⟨Or.inr rfl, rfl⟩
  | @pop _ _ t => cases t <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩

theorem PushArg.absOK {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) (hab : S.AbsOK Γ) : S.AbsOK Γ1 := by
  cases hp with
  | move hm _ => exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp)
  | int => exact hab
  | slice => exact hab

theorem AbsOK.callPostAux {Γa : Ctx} (hab0 : S.AbsOK Γa) {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea) →
      S.AbsOK Γ → S.AbsOK (A1.callPostAux Γa fn args ps as i Γ)
  | [], _, _, _, _, hab => by simpa [A1.callPostAux] using hab
  | _ :: _, [], _, _, _, hab => by simpa [A1.callPostAux] using hab
  | (pm, t) :: ps, a :: as, i, Γ, hz, hab => by
    obtain ⟨Ea, hEa, hpo⟩ := hz ((pm, t), a) (by simp)
    have hz' : ∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea :=
      fun pa hpa => hz pa (by simp [hpa])
    have hae0 : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    cases pm with
    | inp => exact AbsOK.callPostAux hab0 ps as (i + 1) Γ hz' hab
    | sink =>
      obtain ⟨_, hm, _⟩ := hpo
      simp only [A1.callPostAux]
      exact AbsOK.callPostAux hab0 ps as (i + 1) _ hz'
        ((hab.kill _ _ _).setE' hab0 hEa (by simp [hae0]) (by simp [hae0]) (by simp [hae0, hm]))
    | inout b =>
      obtain ⟨_, hcan, _⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
      simp only [A1.callPostAux]
      exact AbsOK.callPostAux hab0 ps as (i + 1) _ hz'
        ((hab.kill _ _ _).setE' hab0 hEa (by simp [hae0]) (by simp [hae0]) (by simp [hae0, hrb]))

theorem CallT.absOK {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) (hab : S.AbsOK Γ) : S.AbsOK Γ1 ∧ (E.mode = .own ∨ E.mode = .bor) ∧
      E.live = true := by
  obtain ⟨fn, _, _, hargs, rfl, rfl⟩ := hc
  refine ⟨AbsOK.callPostAux hab fn.params args 0 Γ (fun pa hpa => ?_) hab, ?_, rfl⟩
  · obtain ⟨k, hk, _, rfl⟩ := mem_zip_getD hpa
    obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
    exact ⟨Ea, hEa, hok⟩
  · simp only [callRes, resMode]; split <;> simp

theorem vdeps_sub {E E' : Entry} (hw : EntryWeaker E E') (hl : E'.live = true) : E.vdeps ⊆ E'.vdeps := by
  obtain ⟨_, hm, _, hlv⟩ := hw
  obtain ⟨_, hp, hh⟩ := hlv hl
  unfold Entry.vdeps; rw [hm]
  cases ho : E.mode.ownSlot with
  | true => exact append_sub (List.Subset.refl _) hh
  | false => exact append_sub (hp ho) hh

theorem roots_sub {a b : List Dep} (h : a ⊆ b) : roots a ⊆ roots b := by
  intro r hr
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  exact List.mem_map_of_mem (h hd)

theorem roots_lift_ρ (h : S.OK) {a : Var} {D : List Dep} {L : List Dep} (hD : D ⊆ rds S.ρ L ++ allKinds S.R)
    (hn : a ∉ roots L) : S.ρ a ∉ roots D := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  rcases List.mem_append.mp (hD hd) with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact hn (h.inj _ _ hdr ▸ List.mem_map_of_mem hd0)
  · exact h.Rout _ (mem_allKinds h1) a hdr.symm

theorem liftE_vdeps_sub {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) :
    (S.liftE v E).vdeps ⊆ rds S.ρ E.vdeps ++ allKinds S.R := by
  intro d hd
  rcases (mem_liftE_vdeps hrb).mp hd with ⟨d0, hd0, rfl⟩ | ha
  · exact List.mem_append_left _ (mem_rds.mpr ⟨d0, hd0, rfl⟩)
  · exact List.mem_append_right _ ha

theorem allowed_replace (hab : S.AbsOK Γa) {x : Var} {Ex : Entry} (hx : Γa x = some Ex)
    (hm : Ex.mode = .own ∨ Ex.mode = .bor ∨ Ex.mode = .inout .replace) (hv : Bool) :
    Allowed S .replace hv x := by
  cases hb : S.bnd x with
  | none => exact Or.inl hb
  | some bh =>
    obtain ⟨E, hE, hmE⟩ := hab.2.2 x bh hb
    rw [hx] at hE; cases hE
    obtain ⟨b, hb'⟩ := bh
    refine Or.inr ⟨b, hb', hb, fun k _ => ?_⟩
    rcases hm with hm | hm | hm <;> rw [hm] at hmE <;> cases hmE
    cases k <;> rfl

theorem src_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).src = s.src := by
  induction s <;> simp_all [Stmt.rename, Stmt.src]

/-- The renaming lemma: a callee's source statement, typed in its own
    contexts, is typed where the call places it, in the caller's view of
    those contexts. -/
theorem StmtT.ren (h : S.OK) {P : Prog} (hP : ProgOK P) {Γa : Ctx} {Fa : List Var} {s : Stmt}
    {Δa : Ctx} (hd : StmtT P Γa Fa s Δa) : s.src = true → S.AbsOK Γa → CtxWF Γa →
    StmtT P (S.canon Γa) S.Fc (s.rename S.ρ) (S.canon Δa) ∧ S.AbsOK Δa := by
  induction hd with
  | skip => exact fun _ hab _ => ⟨StmtT.skip, hab⟩
  | @seq Γ Γ1 Δ F a b hb ta tb iha ihb =>
    intro hs hab hw
    simp only [Stmt.src, Bool.and_eq_true] at hs
    obtain ⟨t1, ab1⟩ := iha hs.1 hab hw
    obtain ⟨t2, ab2⟩ := ihb hs.2 ab1 (ta.wf hP hw)
    exact ⟨StmtT.seq (by rw [src_rename]; exact hb) t1 t2, ab2⟩
  | @letv Γ Γ1 Δ F x r k E hks hx hxF hr hk ih =>
    intro _ hab hw
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h hab hr
    have hab1 := RhsT.absOK (S := S) hr hab
    obtain ⟨hmo, _⟩ := RhsT.out hr
    obtain ⟨hw1, hdom, _, hEr⟩ := hr.wf hw
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 hEr
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx⟩
    rw [canon_exitScope h abk (Or.inl hbx)]
    have hwc := canon_wf h habx hwx
    rw [canon_setE h] at hwc tk
    exact StmtT.letv (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) hr'
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) (hE' x), hwc⟩ tk)
  | @letcall Γ Γ1 Δ F x f args k E hks hx hxF hc hk ih =>
    intro _ hab hw
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h hab hP hc
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hc hab
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP hw
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 (fun _ _ => hE)
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx⟩
    rw [canon_exitScope h abk (Or.inl hbx)]
    have hwc := canon_wf h habx hwx
    rw [canon_setE h] at hwc tk
    exact StmtT.letcall (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) hc'
      (StmtT.weakenIn ⟨PW.setE hpw (hE' x), hwc⟩ tk)
  | scope => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs
  | @assign Γ Γ1 F x r Ex E hx hxF hmodes hr hty hxd hsome =>
    intro _ hab hw
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h hab hr
    have hab1 := RhsT.absOK (S := S) hr hab
    obtain ⟨hmo, hlive⟩ := RhsT.out hr
    have hrbE : E.mode ≠ .rootb := by rcases hmo with hm | hm <;> rw [hm] <;> simp
    have hrbx : Ex.mode ≠ .rootb := by
      rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] <;> simp
    have hos : Ex.mode.ownSlot = E.mode.ownSlot := by
      rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2] <;> rfl
    have hw' := hE' x
    have hm' : E'.mode = liftMode E.mode := by rw [← hw'.2.1, liftE_mode x hrbE]
    have hty' : E'.ty = E.ty := by rw [← hw'.1, liftE_ty x hrbE]
    have hmx' : (S.liftE x Ex).mode = liftMode Ex.mode := liftE_mode x hrbx
    have hal : Allowed S .replace false x := allowed_replace hab hx (by
      rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩
      · exact Or.inl h1
      · exact Or.inr (Or.inr h1)
      · exact Or.inr (Or.inl h1)) false
    have hT := StmtT.assign (P := P) hx hxF hmodes hr hty hxd hsome
    have hwo := hT.wf hP hw
    have habo : S.AbsOK (setE (A1.kill .replace false x Γ1) x { E with mode := Ex.mode }) :=
      (hab1.kill _ _ _).setE' hab hx rfl hty hrbx
    refine ⟨?_, habo⟩
    have hwc := canon_wf h habo hwo
    rw [canon_setE h, canon_kill h hab1 hal] at hwc ⊢
    have hT' := StmtT.assign (P := P) (x := S.ρ x) (Ex := S.liftE x Ex) (E := E') (F := S.Fc)
      (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) (by
        rw [hmx', hm']
        rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2]
        · exact Or.inl ⟨rfl, rfl⟩
        · exact Or.inl ⟨rfl, rfl⟩
        · exact Or.inr (Or.inr ⟨rfl, rfl⟩))
      hr' (by rw [hty', liftE_ty x hrbx, hty]) (by
        have hsub : E'.vdeps ⊆ rds S.ρ E.vdeps ++ allKinds S.R :=
          fun d hd => liftE_vdeps_sub hrbE (vdeps_sub hw' (by rw [liftE_live]; exact hlive) hd)
        exact roots_lift_ρ h hsub hxd)
      (by rw [canon_ρ h]; simpa using hsome)
    refine StmtT.weakenOut (canon_wf h hab hw) hT' (Or.inr ⟨PW.setE (PW.refl _) ?_, hwc⟩)
    have hf : S.liftE x { E with mode := Ex.mode } =
        ⟨E.ty, liftMode Ex.mode, E.live,
         rds S.ρ E.path ++ (if Ex.mode.ownSlot then [] else allKinds S.R), rds S.ρ E.held ++ allKinds S.R⟩ := by
      simp [liftE, hrbx]
    have hf' : S.liftE x E =
        ⟨E.ty, liftMode E.mode, E.live,
         rds S.ρ E.path ++ (if E.mode.ownSlot then [] else allKinds S.R), rds S.ρ E.held ++ allKinds S.R⟩ := by
      simp [liftE, hrbE]
    rw [hf, hmx']
    rw [hf'] at hw'
    obtain ⟨_, _, _, hlv⟩ := hw'
    refine EntryWeaker.mk' hty'.symm rfl (fun e => hrbx (liftMode_rootb.mp e)) ?_ (fun ho => ?_) ?_
    · show E.live = E'.live
      rw [hlive]; exact ((hlv hlive).1).symm
    · have ho' : E.mode.ownSlot = false := by
        rw [← hos]; simpa [liftMode_ownSlot] using ho
      rw [hos]
      exact (hlv hlive).2.1 (by rw [hm', liftMode_ownSlot]; exact ho')
    · exact (hlv hlive).2.2
  | @ite Γ Δ F c a b ha hb hc ta tb iha ihb =>
    intro _ hab hw
    obtain ⟨t1, ab1⟩ := iha ha hab hw
    obtain ⟨t2, _⟩ := ihb hb hab hw
    exact ⟨StmtT.ite (by rw [src_rename]; exact ha) (by rw [src_rename]; exact hb)
      (exprT_ren h hab hc) t1 t2, ab1⟩
  | @«while» Γ F c k hk hc tk ih =>
    intro _ hab hw
    obtain ⟨t, _⟩ := ih hk hab hw
    exact ⟨StmtT.while (by rw [src_rename]; exact hk) (exprT_ren h hab hc) t, hab⟩
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1 =>
    intro _ hab hw
    obtain ⟨D', hpa', hD'⟩ := pushArg_ren h hab hy hpa
    have hab1 := PushArg.absOK (S := S) hy hpa hab
    have hrbx : Ex.mode ≠ .rootb := by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp
    obtain ⟨E0, h0, hm1⟩ := (hpa.domMode hy).2 x Ex1 hx1
    rw [hx] at h0; cases h0
    have hrb1 : Ex1.mode ≠ .rootb := by rw [hm1]; exact hrbx
    have hT := StmtT.push (P := P) hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1
    have hwo := hT.wf hP hw
    have habo : S.AbsOK (setE (A1.kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ D }) :=
      (hab1.kill _ _ _).setE' hab1 hx1 rfl rfl hrb1
    refine ⟨?_, habo⟩
    have hwc := canon_wf h habo hwo
    rw [canon_setE h, canon_kill h hab1 (allowed_canDo hab hx hty hcan)] at hwc ⊢
    have hT' := StmtT.push (P := P) (F := S.Fc) (x := S.ρ x) (y := S.ρ y) (Ex := S.liftE x Ex)
      (Ey := S.liftE y Ey) (Ex1 := S.liftE x Ex1) (t := t) (D := D')
      (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hx]; exact hty)
      (by rw [liftE_mode x hrbx]; exact canDo_lift hcan) (h.Fcout x)
      (by rw [canon_ρ h, hy]; rfl) (by rw [liftE_live]; exact hly) (by rw [liftE_ty' h hab hy]; exact htyy)
      (fun e => hyx (h.inj _ _ e)) hpa' (roots_lift_ρ h hD' hxD)
      (by rw [canon_ρ h, hx1]; rfl) (by rw [liftE_live]; exact hl1)
    refine StmtT.weakenOut (canon_wf h hab hw) hT' (Or.inr ⟨PW.setE (PW.refl _) ?_, hwc⟩)
    refine EntryWeaker.mk' (by simp [liftE, hrb1]) (by simp [liftE, hrb1])
      (fun e => hrb1 ((liftE_rootb h).mp e)) (by simp [liftE, hrb1]) (fun _ => by simp [liftE, hrb1]) ?_
    simp only [liftE, hrb1, ↓reduceIte]
    exact app_lift (S := S) (List.Subset.refl _) hD'
  | @free Γ F x E t hx hl hm hty hxF =>
    intro _ hab _
    have hrb : E.mode ≠ .rootb := by rw [hm]; simp
    refine ⟨?_, (hab.kill _ _ _).setE' hab hx rfl rfl hrb⟩
    rw [canon_setE h, canon_kill h hab (allowed_own hab hx hm _ _), liftE_dead]
    exact StmtT.free (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl)
      (by rw [liftE_mode x hrb, hm]; rfl) (by rw [liftE_ty' h hab hx]; exact hty) (h.Fcout x)
  | @sub Γ Γ0 Δ0 Δ F k hw0 tk ho ih =>
    intro hs hab hw
    have hab0 := hab.weaker hw0
    obtain ⟨t, abΔ0⟩ := ih hs hab0 hw0.2
    have hwc := canon_weaker h hab0 hw0.2 hw0
    rcases ho with rfl | hwo
    · exact ⟨StmtT.weakenIn hwc t, abΔ0⟩
    · have abΔ := abΔ0.weaker hwo
      exact ⟨StmtT.sub hwc t (Or.inr (canon_weaker h abΔ hwo.2 hwo)), abΔ⟩

end RSetup

end A1
