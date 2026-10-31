import A2.NameWf

/-! A2 — a callee's body, checked once against its own view of its
parameters, is well-typed where a call places it.

The call renames the callee's variables apart from the caller's (`ρ`).  The
caller's context, as the renamed body sees it, is `canon Γa`: each callee
binding lifted (`liftE`), and every other binding — the frame — as the
caller has it.  A lifted entry may additionally depend on anything the
arguments held (`allKinds R`): those roots are frozen for the call, so
nothing in the body can end them. -/

namespace A2

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
  pty : Var → Ty                     -- an `inout` parameter's type
  N   : List Dep                     -- what the arguments hold by name, of the frame
  sym : List Dep                     -- the callee's symbolic names on its `inout` parameters

namespace RSetup
variable (S : RSetup)

/-- Anything the arguments held: views, in every way, and closures, by name. -/
def A : List Dep := allKinds S.R ++ S.N

open Classical in
noncomputable def inv (y : Var) : Option Var :=
  if h : ∃ v, S.ρ v = y then some (Classical.choose h) else none

def liftE (v : Var) (E : Entry) : Entry :=
  if E.mode = .rootb then { S.pe v with live := E.live } else
    ⟨E.ty, liftMode E.mode, E.live,
     rds S.ρ E.path ++ (if E.mode.ownSlot then [] else S.A),
     rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A, false⟩

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
  -- what a borrowed parameter depends on in memory is the frame's
  pe_out : ∀ v, ∀ d ∈ (S.pe v).vdeps, d.kind.isName = false →
             (∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true
  -- the frame: nothing in it depends on the callee's own bindings, and what
  -- depends on an `inout` argument is already ended for everything the
  -- callee may do to it
  Φsat   : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ d ∈ E.vdeps, ∀ v, S.ρ v = d.root →
               ∃ b hv, S.bnd v = some (b, hv) ∧ b.kills hv d.kind = false
  Φwf    : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ r ∈ roots E.vdeps, (∀ v, S.ρ v ≠ r) → ∃ Er, S.Φ r = some Er ∧ Er.mode.isRoot = true
  Φρ     : ∀ v, S.Φ (S.ρ v) = none
  Φio    : ∀ y E b, S.Φ y = some E → E.mode ≠ .inout b
  -- what a borrowed parameter holds: what the arguments held, or (when its
  -- type can hold a closure) an `inout` argument by name, as the callee's
  -- symbolic name says
  pe_held : ∀ v, ∀ d ∈ (S.pe v).held, d ∈ S.A ∨ (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true)
  pe_names : ∀ v, ∀ d ∈ (S.pe v).vdeps, d.kind.isName = true →
               d ∈ S.N ∨ (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true)
  -- the symbolic names: each an `inout` parameter that holds no views and
  -- is not replaced, by its own bound and type
  sym_ok : ∀ d ∈ S.sym, ∃ w b t, d = ⟨w, .name b t⟩ ∧ S.bnd w = some (b, false) ∧ S.pty w = t ∧
             b ≠ .none ∧ b ≠ .replace
  sym_of : ∀ w b t, S.bnd w = some (b, false) → S.pty w = t → b ≠ .none → b ≠ .replace →
             ⟨w, .name b t⟩ ∈ S.sym
  -- what the arguments hold by name of the frame: frame bindings, of the
  -- frame's view; what may change them is not lent, ended in the frame
  -- already, and reached from an argument only by a name of the same bound
  N_name : ∀ d ∈ S.N, d.kind.isName = true
  N_out  : ∀ d ∈ S.N, (∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true
  N_named : DepsNamed S.Φ S.N
  N_mut  : ∀ d ∈ S.N, d.kind.bound ≠ .none → d.root ∉ S.Fc ∧ d.root ∉ S.R ∧
             (∃ Er, S.Φ d.root = some Er ∧ canDo Er.mode d.kind.bound ∧
               ∃ s, Er.ty = .vec s ∧ s.holdsView = false) ∧
             (∀ v, ∀ d' ∈ (S.pe v).vdeps, d'.root = d.root → d'.kind.bound = d.kind.bound) ∧
             (∀ d' ∈ S.N, d'.root = d.root → d'.kind.bound = d.kind.bound) ∧
             (∀ y E, S.Φ y = some E → E.live = true → hits d.kind.bound false d.root E = false)
  Φrb    : ∀ y E, S.Φ y = some E → E.mode = .rootb → E.live = true
  Φnamed : ∀ y E, S.Φ y = some E → E.live = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
             ∀ d ∈ E.vdeps, ∀ b t, d.kind = .name b t →
               (∃ v bh, S.ρ v = d.root ∧ S.bnd v = some bh ∧ S.pty v = t ∧ b ≠ .replace ∧
                  bh.1 ≠ .replace ∧ t.holdsView = false) ∨
               ((∀ v, S.ρ v ≠ d.root) ∧ ∃ Er, S.Φ d.root = some Er ∧ Er.live = true ∧ Er.held = [] ∧
                  Er.ty = t ∧
                  Er.mode.ownSlot = true ∧ (b = .none ∨ b ≠ .replace ∧ canDo Er.mode b) ∧ t.holdsView = false)

/-- The callee's own contexts, as the call sets them up: a borrowed
    parameter depends on nothing it can see but, when it may hold a closure,
    the `inout` parameters by their symbolic names; an `inout` parameter
    carries its bound; one that is fixed stays live and holds nothing. -/
def RSetup.AbsOK (S : RSetup) (Γa : Ctx) : Prop :=
  (∀ v E, Γa v = some E → E.mode = .rootb → E.ty = (S.pe v).ty ∧ E.path = [] ∧
     E.held = (if E.ty.hasFn then S.sym else [])) ∧
  (∀ v E b, Γa v = some E → E.mode = .inout b →
     E.ty.owning = true ∧ S.bnd v = some (b, E.ty.elem.holdsView)) ∧
  (∀ v bh, S.bnd v = some bh → ∃ E, Γa v = some E ∧ E.mode = .inout bh.1 ∧ E.ty = S.pty v ∧
     (E.fixed → E.live = true ∧ E.held = []))

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

theorem mem_A {d : Dep} : d ∈ S.A ↔ d ∈ allKinds S.R ∨ d ∈ S.N := List.mem_append

/-- What the arguments held lies outside the callee, at roots of the frame. -/
theorem A_out (h : S.OK) {d : Dep} (hd : d ∈ S.A) : ∀ w, S.ρ w ≠ d.root := by
  rcases mem_A.mp hd with hd | hd
  · exact h.Rout _ (mem_allKinds hd)
  · exact (h.N_out d hd).1

theorem A_mem (h : S.OK) {d : Dep} (hd : d ∈ S.A) (hn : (!d.kind.isName) = true) : d ∈ allKinds S.R := by
  rcases mem_A.mp hd with hd | hd
  · exact hd
  · rw [h.N_name d hd] at hn; cases hn

theorem A_root (h : S.OK) {d : Dep} (hd : d ∈ S.A) : ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true := by
  rcases mem_A.mp hd with hd | hd
  · exact h.Rroot _ (mem_allKinds hd)
  · exact (h.N_out d hd).2

theorem liftMode_ownSlot (m : Mode) : (liftMode m).ownSlot = m.ownSlot := by cases m <;> rfl
theorem liftMode_isRoot (m : Mode) : (liftMode m).isRoot = m.isRoot := by cases m <;> rfl
theorem liftMode_rootb {m : Mode} : liftMode m = .rootb ↔ m = .rootb := by cases m <;> simp [liftMode]

theorem mem_liftE_vdeps {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) {d : Dep} :
    d ∈ (S.liftE v E).vdeps ↔ (∃ d0 ∈ E.vdeps, d = d0.ren S.ρ) ∨ d ∈ ownHeld E.mode.ownSlot E.ty S.A := by
  have hv : (S.liftE v E).vdeps = (if E.mode.ownSlot then [] else rds S.ρ E.path ++ S.A) ++
      (rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A) := by
    simp only [liftE, hrb, ↓reduceIte, Entry.vdeps, liftMode_ownSlot]
    cases E.mode.ownSlot <;> simp
  rw [hv]
  unfold Entry.vdeps
  cases ho : E.mode.ownSlot
  · have hA : ownHeld false E.ty S.A = S.A := by simp [ownHeld]
    rw [hA]; simp [mem_rds]
    all_goals grind
  · simp [mem_rds]
    all_goals grind

theorem liftE_vdeps_cases {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) {d : Dep}
    (hd : d ∈ (S.liftE v E).vdeps) : (∃ d0 ∈ E.vdeps, d = d0.ren S.ρ) ∨ d ∈ S.A :=
  ((mem_liftE_vdeps hrb).mp hd).imp id (fun h => ownHeld_sub _ _ _ h)

theorem liftE_ty (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) : (S.liftE v E).ty = E.ty := by
  simp [liftE, hrb]

theorem liftE_mode (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) : (S.liftE v E).mode = liftMode E.mode := by
  simp [liftE, hrb]

/-- The caller's view of a callee binding other than a borrowed parameter
    is never fixed: an `inout` parameter is the caller's own binding. -/
theorem liftE_not_fixed {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) : ¬ (S.liftE v E).fixed := by
  intro h
  rcases h with h | ⟨b, h, _⟩ <;> rw [liftE_mode v hrb] at h
  · exact hrb (liftMode_rootb.mp h)
  · cases hm : E.mode <;> rw [hm] at h <;> simp [liftMode] at h

/-- What a callee binding that may be held by name holds, the caller sees it
    hold. -/
theorem liftE_held_named {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) (ho : E.mode.ownSlot = true)
    (hh : E.held = []) (hv : E.ty.holdsView = false) : (S.liftE v E).held = [] := by
  simp [liftE, hrb, hh, ho, ownHeld, hv, rds]

/-- ... nor is anything of a lifted mode. -/
theorem not_fixed_liftMode {E : Entry} {m : Mode} (hm : E.mode = liftMode m) (hrb : m ≠ .rootb) :
    ¬ E.fixed := by
  rintro (h | ⟨b, h, _⟩) <;> rw [hm] at h
  · exact hrb (liftMode_rootb.mp h)
  · cases hq : m <;> rw [hq] at h <;> simp [liftMode] at h

theorem beq_rootb_liftMode (m : Mode) : (liftMode m == .rootb) = (m == .rootb) := by
  cases m <;> rfl

/-- An effect the callee may have does not touch the frame. -/
def Allowed (S : RSetup) (e : Eff) (hv : Bool) (x : Var) : Prop :=
  S.bnd x = none ∨ ∃ b hb, S.bnd x = some (b, hb) ∧ ∀ k, e.kills hv k = true → b.kills hb k = true

/-- A symbolic name, where the call places it: an `inout` argument, by the
    parameter's bound. -/
theorem sym_ren (h : S.OK) {d : Dep} (hd : d ∈ rds S.ρ S.sym) :
    ∃ w b t, d = ⟨S.ρ w, .name b t⟩ ∧ S.bnd w = some (b, false) ∧ S.pty w = t ∧ b ≠ .none ∧
      b ≠ .replace := by
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  obtain ⟨w, b, t, rfl, hb, ht, hbn, hbr⟩ := h.sym_ok d0 hd0
  exact ⟨w, b, t, rfl, hb, ht, hbn, hbr⟩

/-- What a borrowed parameter depends on: the frame, at a root the callee
    cannot name, or an `inout` argument by a symbolic name. -/
theorem pe_dep (h : S.OK) {v : Var} {d : Dep} (hd : d ∈ (S.pe v).vdeps) :
    ((∀ w, S.ρ w ≠ d.root) ∧ ∃ E, S.Φ d.root = some E ∧ E.mode.isRoot = true) ∨
    (d ∈ rds S.ρ S.sym ∧ (S.pe v).ty.hasFn = true) := by
  cases hn : d.kind.isName
  · exact Or.inl (h.pe_out v d hd hn)
  · rcases h.pe_names v d hd hn with hN | hs
    · exact Or.inl (h.N_out d hN)
    · exact Or.inr hs

/-- A borrowed parameter reaches nothing the callee can name but an `inout`
    argument, by a symbolic name. -/
theorem pe_ρ (h : S.OK) {v x : Var} {d : Dep} (hd : d ∈ (S.pe v).vdeps) (hr : d.root = S.ρ x) :
    ∃ b t, d = ⟨S.ρ x, .name b t⟩ ∧ S.bnd x = some (b, false) ∧ S.pty x = t ∧ b ≠ .none ∧
      b ≠ .replace ∧ (S.pe v).ty.hasFn = true := by
  rcases pe_dep h hd with ⟨hout, _⟩ | ⟨hs, hf⟩
  · exact absurd hr.symm (hout x)
  · obtain ⟨w, b, t, rfl, hb, ht, hbn, hbr⟩ := sym_ren h hs
    have := h.inj _ _ hr; subst this
    exact ⟨b, t, rfl, hb, ht, hbn, hbr, hf⟩

/-- Hitting a lifted entry is hitting the entry it lifts, for an effect the
    callee may have: a symbolic name is never ended (the parameter is not
    replaced), whether the closure handed over holds the argument or not. -/
theorem hits_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x) :
    hits e hv (S.ρ x) (S.liftE v E) = hits e hv x E := by
  by_cases hrb : E.mode = .rootb
  · -- on neither side is anything hit: the abstract entry holds only
    -- symbolic names, the lifted one names of `inout` arguments
    have hsym : ∀ b t, S.bnd x = some (b, false) → b ≠ .replace → e.kills hv (.name b t) = false := by
      intro b t hb hbr
      rcases ha with hn | ⟨b', hb', hbb, hk⟩
      · rw [hn] at hb; cases hb
      · rw [hb] at hbb; cases hbb
        cases e with
        | replace =>
          have := hk (.name b t) rfl
          cases b <;> simp [Eff.kills] at this <;> exact absurd rfl hbr
        | _ => rfl
    obtain ⟨_, hp, hh⟩ := hab.1 v E hE hrb
    have h1 : hits e hv x E = false := by
      unfold hits
      simp only [Entry.vdeps, hp, hh, Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
        beq_iff_eq, not_and, Bool.not_eq_true]
      refine Or.inr fun d hd hr => ?_
      have hd' : d ∈ S.sym := by
        rw [hrb] at hd
        simp only [Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, List.nil_append] at hd
        split at hd
        · exact hd
        · cases hd
      obtain ⟨w, b, t, rfl, hb, _, _, hbr⟩ := h.sym_ok d hd'
      simp only at hr; subst hr
      exact hsym b t hb hbr
    rw [h1]
    unfold hits
    simp only [liftE, hrb, ↓reduceIte, Bool.and_eq_false_iff, List.any_eq_false, Bool.and_eq_true,
      beq_iff_eq, not_and, Bool.not_eq_true]
    refine Or.inr fun d hd hr => ?_
    have hvd : ({ S.pe v with live := E.live } : Entry).vdeps = (S.pe v).vdeps := rfl
    rw [hvd] at hd
    obtain ⟨b, t, rfl, hb, _, _, hbr, _⟩ := pe_ρ h hd hr
    exact hsym b t hb hbr
  · unfold hits
    rw [liftE_ty v hrb, liftE_mode v hrb, beq_rootb_liftMode]
    congr 1
    rw [Bool.eq_iff_iff]
    simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
    constructor
    · rintro ⟨d, hd, hr, hk⟩
      rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
      · exact ⟨d0, hd0, h.inj _ _ hr, hk⟩
      · exact absurd hr.symm (A_out h ha x)
    · rintro ⟨d0, hd0, hr, hk⟩
      exact ⟨d0.ren S.ρ, (mem_liftE_vdeps hrb).mpr (Or.inl ⟨d0, hd0, rfl⟩), by simp [Dep.ren, hr], hk⟩

theorem liftE_live (v : Var) (E : Entry) : (S.liftE v E).live = E.live := by
  unfold liftE; split <;> rfl

theorem liftE_dead (v : Var) (E : Entry) :
    S.liftE v { E with live := false } = { S.liftE v E with live := false } := by
  unfold liftE; split <;> simp_all

/-- A binding moved out (`live` and `dtor` cleared; never a borrowed
    parameter, which no rule moves). -/
theorem liftE_moved (v : Var) {E : Entry} (hrb : E.mode ≠ .rootb) :
    S.liftE v { E with live := false, dtor := false } = { S.liftE v E with live := false, dtor := false } := by
  unfold liftE; split <;> simp_all

theorem killE_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {e : Eff} {hv : Bool} {x : Var} (ha : Allowed S e hv x) :
    killE e hv (S.ρ x) (S.liftE v E) = S.liftE v (killE e hv x E) := by
  unfold killE
  rw [hits_lift h hab hE ha]
  split
  · exact (liftE_dead v E).symm
  · rfl

theorem Eff.kills_mono {e b : Eff} (hle : e.le b) (hv : Bool) (k : Kind) (hk : e.kills hv k = true) :
    b.kills hv k = true := by
  unfold Eff.le Eff.rank at hle
  cases e <;> cases b <;> cases k <;> simp_all [Eff.kills]

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
  · rw [canon_ρ h, A2.kill, A2.kill, hc]
    cases hE : Γa v with
    | none => rfl
    | some E => simp only [Option.map_some]; rw [killE_lift h hab hE ha]
  · rw [canon_frame _ hy, A2.kill, hc]
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
  · rw [hr (Or.inl hrb)]; exact EntryWeaker.refl _
  · have hrb' : E'.mode ≠ .rootb := by rw [hm]; exact hrb
    refine ⟨by rw [liftE_ty v hrb', liftE_ty v hrb, ht], by rw [liftE_mode v hrb', liftE_mode v hrb, hm],
      fun h' => absurd h' (liftE_not_fixed hrb), fun hl' => ?_⟩
    rw [liftE_live] at hl'
    obtain ⟨hl0, hp, hh⟩ := hl hl'
    refine ⟨by rw [liftE_live]; exact hl0, fun ho => ?_, ?_⟩
    · rw [liftE_mode v hrb, liftMode_ownSlot] at ho
      simp only [liftE, hrb, ↓reduceIte, hm, ho, Bool.false_eq_true]
      exact append_sub (rds_subset (hp ho)) (List.Subset.refl _)
    · simp only [liftE, hrb, ↓reduceIte, hm, ht]
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
        obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
        rcases pe_dep h hd with ⟨hout, hex⟩ | ⟨hs, _⟩
        · exact canon_frameRoot h hout hex
        · obtain ⟨w, b, t, rfl, hb, _, _, _⟩ := sym_ren h hs
          obtain ⟨Ew, hEw, hm, _⟩ := hab.2.2 w (b, false) hb
          exact canon_root h hEw (by rw [hm]; rfl)
      · rw [liftE_live] at hl
        have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
          rcases hn with h' | h'
          · rw [liftE_ty v hrb] at h'; exact Or.inl h'
          · rw [liftE_rootb h] at h'; exact absurd h' hrb
        obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
        rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
        · obtain ⟨Er, hEr, hro⟩ := hw v E hE hl hn' d0.root (List.mem_map_of_mem hd0)
          exact canon_root h hEr hro
        · exact canon_frameRoot h (A_out h ha) (A_root h ha)
  · rw [hc] at hy
    by_cases hrr : ∃ v, S.ρ v = r
    · obtain ⟨v, rfl⟩ := hrr
      obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
      obtain ⟨b, hv, hb, _⟩ := h.Φsat y E' hy hl hn d hd v hdr.symm
      obtain ⟨Ev, hEv, hm, _⟩ := hab.2.2 v (b, hv) hb
      exact canon_root h hEv (by rw [hm]; rfl)
    · have hout : ∀ v, S.ρ v ≠ r := fun v hv => hrr ⟨v, hv⟩
      exact canon_frameRoot h hout (h.Φwf y E' hy hl hn r hr hout)

theorem allKinds_notName {rs : List Var} {d : Dep} (h : d ∈ allKinds rs) : d.kind.isName = false := by
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false] at h
  obtain ⟨r, _, hd⟩ := h
  rcases hd with rfl | rfl | rfl <;> rfl

/-- A symbolic name, where the call places it, names a binding the caller's
    view has: the `inout` argument, lifted, owns its slot, holds nothing and
    allows the bound. -/
theorem sym_named (h : S.OK) (hab : S.AbsOK Γa) {d : Dep} (hs : d ∈ rds S.ρ S.sym) {b : Eff} {t : Ty}
    (hk : d.kind = .name b t) :
    ∃ Er, S.canon Γa d.root = some Er ∧ Er.live = true ∧ Er.held = [] ∧ Er.ty = t ∧
      Er.mode.ownSlot = true ∧ (b = .none ∨ b ≠ .replace ∧ canDo Er.mode b) ∧ t.holdsView = false := by
  obtain ⟨w, b', t', hd, hb, hpt, _, hbr⟩ := sym_ren h hs
  subst hd
  simp only [Kind.name.injEq] at hk
  obtain ⟨hb1, ht1⟩ := hk
  subst hb1 ht1
  obtain ⟨Ew, hEw, hm, hty, hfx⟩ := hab.2.2 w (b', false) hb
  obtain ⟨_, hbs⟩ := hab.2.1 w Ew b' hEw hm
  rw [hb] at hbs; simp only [Option.some.injEq, Prod.mk.injEq] at hbs
  have hvv : Ew.ty.holdsView = false := by rw [← elem_holdsView]; exact hbs.2.symm
  obtain ⟨hlv, hhv'⟩ := hfx (Or.inr ⟨b', hm, hbr, hvv⟩)
  have hrb' : Ew.mode ≠ .rootb := by rw [hm]; simp
  refine ⟨S.liftE w Ew, by rw [canon_ρ h, hEw]; rfl, by rw [liftE_live]; exact hlv,
    liftE_held_named hrb' (by rw [hm]; rfl) hhv' hvv, by rw [liftE_ty _ hrb', hty, hpt],
    by rw [liftE_mode _ hrb', hm]; rfl, Or.inr ⟨hbr, ?_⟩, by rw [← hpt, ← hty]; exact hvv⟩
  rw [liftE_mode _ hrb', hm]; exact Or.inl rfl

/-- The caller's view of a callee context keeps what is held by name valid. -/
theorem canon_names (h : S.OK) (hab : S.AbsOK Γa) (hn : NameWF Γa) : NameWF (S.canon Γa) := by
  intro y E' hy hl hnn d hd b t hk
  rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨hyf, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq] at hy; subst hy
      by_cases hrb : E.mode = .rootb
      · have hvd : (S.liftE v E).vdeps = (S.pe v).vdeps := by simp [liftE, hrb, Entry.vdeps]
        rw [hvd] at hd
        rcases h.pe_names v d hd (by rw [hk]; rfl) with hN | ⟨hs, _⟩
        · obtain ⟨Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩ := h.N_named d hN b t hk
          exact ⟨Er, by rw [canon_frame _ (h.N_out d hN).1]; exact hEr, hlr, hhr, ht, ho, hc', hhv⟩
        · exact sym_named h hab hs hk
      · rw [liftE_live] at hl
        have hn' : E.ty ≠ .int ∨ E.mode = .rootb := by
          rcases hnn with h' | h'
          · rw [liftE_ty v hrb] at h'; exact Or.inl h'
          · rw [liftE_rootb h] at h'; exact absurd h' hrb
        rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
        · obtain ⟨Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩ := hn v E hE hl hn' d0 hd0 b t hk
          have hrb' : Er.mode ≠ .rootb := fun e => by rw [e] at ho; cases ho
          refine ⟨S.liftE d0.root Er, by
              show S.canon Γa (S.ρ d0.root) = _; rw [canon_ρ h, hEr]; rfl,
            by rw [liftE_live]; exact hlr, liftE_held_named hrb' ho hhr (by rw [ht]; exact hhv),
            by rw [liftE_ty _ hrb', ht], by rw [liftE_mode _ hrb', liftMode_ownSlot]; exact ho, ?_, hhv⟩
          rcases hc' with hb | ⟨hbr, _⟩
          · exact Or.inl hb
          · exact Or.inr ⟨hbr, Or.inl (by rw [liftE_mode _ hrb']; cases hm : Er.mode <;> simp_all [liftMode, Mode.ownSlot])⟩
        · rcases mem_A.mp ha with ha | ha
          · have := allKinds_notName ha; rw [hk] at this; cases this
          · obtain ⟨Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩ := h.N_named d ha b t hk
            exact ⟨Er, by rw [canon_frame _ (h.N_out d ha).1]; exact hEr, hlr, hhr, ht, ho, hc', hhv⟩
  · rw [hc] at hy
    rcases h.Φnamed y E' hy hl hnn d hd b t hk with ⟨v, bh, hρ, hb, hpt, hbr, hbh, hhv⟩ |
        ⟨hout, Er, hEr, hlr, hhr, ht, ho, hc', hhv⟩
    · obtain ⟨Ev, hEv, hmv, htv, hfx⟩ := hab.2.2 v bh hb
      have hrb' : Ev.mode ≠ .rootb := by rw [hmv]; simp
      have hvv : Ev.ty.holdsView = false := by rw [htv, hpt]; exact hhv
      obtain ⟨hlv, hhv'⟩ := hfx (Or.inr ⟨bh.1, hmv, hbh, hvv⟩)
      refine ⟨S.liftE v Ev, by rw [← hρ, canon_ρ h, hEv]; rfl, by rw [liftE_live]; exact hlv,
        liftE_held_named hrb' (by rw [hmv]; rfl) hhv' hvv, by rw [liftE_ty _ hrb', htv, hpt],
        by rw [liftE_mode _ hrb', hmv]; rfl, Or.inr ⟨hbr, ?_⟩, hhv⟩
      rw [liftE_mode _ hrb', hmv]; exact Or.inl rfl
    · exact ⟨Er, by rw [canon_frame _ hout]; exact hEr, hlr, hhr, ht, ho, hc', hhv⟩

theorem canon_weaker (h : S.OK) {Γa Γa' : Ctx} (hab' : S.AbsOK Γa') (hw' : CtxWF Γa')
    (hw : Weaker Γa Γa') : Weaker (S.canon Γa) (S.canon Γa') := by
  refine ⟨fun y => ⟨?_, fun E E' h1 h2 => ?_⟩, canon_wf h hab' hw', canon_names h hab' hw.names⟩
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
    rw [hwe.2.2.1 (Or.inl hm')]; exact hab.1 v E hE hm'
  · obtain ⟨E, hE, hwe⟩ := hw.get' hv
    rw [hwe.1]; exact hab.2.1 v E b hE (by rw [← hwe.2.1]; exact hm)
  · obtain ⟨E, hE, hm, ht, hfx⟩ := hab.2.2 v bh hb
    obtain ⟨E', hE', hwe⟩ := hw.get hE
    refine ⟨E', hE', by rw [hwe.2.1]; exact hm, by rw [hwe.1]; exact ht, fun hf => ?_⟩
    have hf0 : E.fixed := by simp only [Entry.fixed_def] at hf ⊢; rw [hwe.2.1, hwe.1] at hf; exact hf
    rw [hwe.2.2.1 hf0]; exact hfx hf0

theorem AbsOK.kill {Γa : Ctx} (hab : S.AbsOK Γa) (e : Eff) (hv : Bool) (x : Var) :
    S.AbsOK (A2.kill e hv x Γa) := by
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_⟩
  · obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'; subst hv'
    rw [killE_mode] at hm
    rw [killE_ty, killE_path, killE_held]; exact hab.1 v E hE hm
  · obtain ⟨E, hE, _, _⟩ := kill_cmode hv'
    simp only [A2.kill, hE, Option.map_some, Option.some.injEq] at hv'; subst hv'
    rw [killE_mode] at hm; rw [killE_ty]; exact hab.2.1 v E b hE hm
  · obtain ⟨E, hE, hm, hty, hfx⟩ := hab.2.2 v bh hb
    refine ⟨killE e hv x E, by simp [A2.kill, hE], by rw [killE_mode, hm], by rw [killE_ty, hty], fun hf => ?_⟩
    have hf0 : E.fixed := by unfold Entry.fixed at hf ⊢; rw [killE_mode, killE_ty] at hf; exact hf
    have hk : killE e hv x E = E := killE_nil (root_vdeps (by rw [hm]; rfl) (hfx hf0).2) e hv x
    rw [hk]; exact hfx hf0

theorem AbsOK.setE {Γa : Ctx} (hab : S.AbsOK Γa) {x : Var} {E : Entry} (hrb : E.mode ≠ .rootb)
    (hio : ∀ b, E.mode = .inout b → E.ty.owning = true ∧ S.bnd x = some (b, E.ty.elem.holdsView))
    (hbx : ∀ bh, S.bnd x = some bh → E.mode = .inout bh.1)
    (hbt : ∀ bh, S.bnd x = some bh → E.ty = S.pty x)
    (hfx : ∀ bh, S.bnd x = some bh → E.fixed → E.live = true ∧ E.held = []) : S.AbsOK (A2.setE Γa x E) := by
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_⟩
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'; exact absurd hm hrb
    · simp only [A2.setE, upd_ne _ _ hvx] at hv'; exact hab.1 v E' hv' hm
  · by_cases hvx : v = x
    · subst hvx; simp only [A2.setE, upd_same, Option.some.injEq] at hv'; subst hv'; exact hio b hm
    · simp only [A2.setE, upd_ne _ _ hvx] at hv'; exact hab.2.1 v E' b hv' hm
  · by_cases hvx : v = x
    · subst hvx; exact ⟨E, by simp [A2.setE], hbx bh hb, hbt bh hb, hfx bh hb⟩
    · obtain ⟨E0, h0, hm0, ht0, hf0⟩ := hab.2.2 v bh hb
      exact ⟨E0, by simp [A2.setE, upd_ne _ _ hvx, h0], hm0, ht0, hf0⟩

theorem AbsOK.exitScope {Γa : Ctx} (hab : S.AbsOK Γa) {x : Var} (hbx : S.bnd x = none) :
    S.AbsOK (A2.exitScope x Γa) := by
  have hk := hab.kill .replace false x
  refine ⟨fun v E' hv' hm => ?_, fun v E' b hv' hm => ?_, fun v bh hb => ?_⟩
  · have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'; exact hk.1 v E' hv' hm
  · have hvx : v ≠ x := fun e => by subst e; simp [A2.exitScope] at hv'
    simp only [A2.exitScope, upd_ne _ _ hvx] at hv'; exact hk.2.1 v E' b hv' hm
  · have hvx : v ≠ x := fun e => by subst e; rw [hbx] at hb; cases hb
    obtain ⟨E0, h0, hm0, ht0, hf0⟩ := hk.2.2 v bh hb
    exact ⟨E0, by simp [A2.exitScope, upd_ne _ _ hvx, h0], hm0, ht0, hf0⟩

theorem EntryWeaker.mk' {E E' : Entry} (ht : E'.ty = E.ty) (hm : E'.mode = E.mode)
    (hrb : ¬ E.fixed) (hl : E'.live = E.live) (hp : E.mode.ownSlot = false → E.path ⊆ E'.path)
    (hh : E.held ⊆ E'.held) : EntryWeaker E E' :=
  ⟨ht, hm, fun h' => absurd h' hrb, fun h' => ⟨by rw [← hl]; exact h', hp, hh⟩⟩

theorem allKinds_comp {R : List Var} {k : Kind} (hk : k.isName = false) :
    (allKinds R).map (fun d => (⟨d.root, comp d.kind k⟩ : Dep)) ⊆ allKinds R := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
  have hr := mem_allKinds hd0
  have hk0 : d0.kind = .self ∨ d0.kind = .inner ∨ d0.kind = .view := by
    simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
      or_false] at hd0
    obtain ⟨r, _, h⟩ := hd0
    rcases h with rfl | rfl | rfl <;> simp
  simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
    or_false]
  refine ⟨d0.root, hr, ?_⟩
  cases k with
  | name b t => cases hk
  | _ => rcases hk0 with h | h | h <;> rw [h] <;> simp [comp]

theorem A_comp (h : S.OK) {k : Kind} (hk : k.isName = false) :
    S.A.map (fun d => (⟨d.root, comp d.kind k⟩ : Dep)) ⊆ S.A := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := List.mem_map.mp hd
  rcases mem_A.mp hd0 with h0 | h0
  · exact mem_A.mpr (Or.inl (allKinds_comp hk (List.mem_map_of_mem h0)))
  · have hn := h.N_name d0 h0
    obtain ⟨r, kd⟩ := d0
    cases kd with
    | name b t =>
      have : comp (.name b t) k = .name b t := by cases k <;> simp [comp]
      simp only [this]; exact mem_A.mpr (Or.inr h0)
    | _ => simp [Kind.isName] at hn

/-- What a lifted binding lends is what the binding it lifts lends, renamed,
    or something the arguments held. -/
theorem derive_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (k : Kind)
    (hk : k.isName = false) :
    derive (S.ρ y) (S.liftE y Ey) k ⊆ rds S.ρ (derive y Ey k) ++ S.A := by
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
    have hpath : (S.liftE y Ey).path = rds S.ρ Ey.path ++ S.A := by simp [liftE, hrb, hos]
    rw [hpath, List.map_append] at hd
    rcases List.mem_append.mp hd with hd | hd
    · obtain ⟨d1, hd1, rfl⟩ := List.mem_map.mp hd
      obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd1
      exact List.mem_append_left _ (mem_rds.mpr ⟨_, List.mem_map_of_mem hd0, rfl⟩)
    · exact List.mem_append_right _ (A_comp h hk hd)

theorem liftE_held {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) :
    (S.liftE v E).held = rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A := by
  simp [liftE, hrb]

theorem held_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) :
    (S.liftE y Ey).held ⊆ rds S.ρ Ey.held ++ S.A := by
  by_cases hrb : Ey.mode = .rootb
  · simp only [liftE, hrb, ↓reduceIte]
    intro d hd
    rcases h.pe_held y d hd with hA | ⟨hs, hf⟩
    · exact List.mem_append_right _ hA
    · obtain ⟨hty, _, hh⟩ := hab.1 y Ey hy hrb
      rw [hty, hf] at hh; simp only [↓reduceIte] at hh
      rw [hh]; exact List.mem_append_left _ hs
  · rw [liftE_held hrb]; exact append_sub (List.Subset.refl _) (ownHeld_sub _ _ _)

/-- A borrowed binding, or one a copy is lent from, holds what it lifts, and
    anything the arguments held. -/
theorem held_lift_bor (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (t : Ty) :
    (S.liftE y Ey).held ⊆ rds S.ρ Ey.held ++ ownHeld false t S.A := by
  rw [ownHeld_false]; exact held_lift h hab hy

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
  | isl hx hl ht =>
    exact ExprT.isl (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl)
      (by rw [liftE_ty' h hab hx]; exact ht)

theorem liftE_indep {E : Entry} (hrb : E.mode ≠ .rootb) (x v : Var) : S.liftE x E = S.liftE v E := by
  simp [liftE, hrb]

theorem allowed_own (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (hm : Ey.mode = .own)
    (e : Eff) (hv : Bool) : Allowed S e hv y := by
  left
  cases hb : S.bnd y with
  | none => rfl
  | some bh =>
    obtain ⟨E, hE, hmE, _⟩ := hab.2.2 y bh hb
    rw [hy] at hE; cases hE; rw [hm] at hmE; cases hmE

theorem allowed_canDo' (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    {e : Eff} (hcan : canDo Ey.mode e) : Allowed S e Ey.ty.elem.holdsView y := by
  rcases hcan with hm | ⟨b, hm, hle⟩
  · exact allowed_own hab hy hm e _
  · obtain ⟨_, hb⟩ := hab.2.1 y Ey b hy hm
    exact Or.inr ⟨b, _, hb, fun k hk => Eff.kills_mono hle _ k hk⟩

theorem allowed_canDo (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} {t : Ty} (hy : Γa y = some Ey)
    (ht : Ey.ty = .vec t) {e : Eff} (hcan : canDo Ey.mode e) : Allowed S e t.holdsView y := by
  have h := allowed_canDo' hab hy hcan
  rw [ht] at h; exact h

theorem canDo_lift {m : Mode} {e : Eff} (h : canDo m e) : canDo (liftMode m) e := by
  rcases h with rfl | ⟨b, rfl, _⟩ <;> exact Or.inl rfl

theorem intE_lift (x : Var) : EntryWeaker intE (S.liftE x intE) := by
  have he : S.liftE x intE = ⟨.int, .bor, true, S.A, S.A, false⟩ := by
    simp [liftE, intE, liftMode, rds, Mode.ownSlot, ownHeld_false]
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
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot, ownHeld_false]; exact hl
  | vec s =>
    refine EntryWeaker.mk' (by simp [elemE, liftE]) (by simp [elemE, liftE, liftMode])
      (by simp [elemE]) (by simp [elemE, liftE]) (fun _ => ?_) ?_
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot, ownHeld_false]; exact hl
  | prod a b =>
    refine EntryWeaker.mk' (by simp [elemE, liftE]) (by simp [elemE, liftE, liftMode])
      (by simp [elemE]) (by simp [elemE, liftE]) (fun _ => ?_) ?_
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot, ownHeld_false]; exact hl
  | sum a b =>
    refine EntryWeaker.mk' (by simp [elemE, liftE]) (by simp [elemE, liftE, liftMode])
      (by simp [elemE]) (by simp [elemE, liftE]) (fun _ => ?_) ?_
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot, ownHeld_false]; exact hl
  | fn ms =>
    refine EntryWeaker.mk' (by simp [elemE, liftE]) (by simp [elemE, liftE, liftMode])
      (by simp [elemE]) (by simp [elemE, liftE]) (fun _ => ?_) ?_
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .inner rfl
    · simp only [elemE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot, ownHeld_false]; exact hl

theorem popE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    {t : Ty} (ht : Ey.ty = .vec t) (hrb : Ey.mode ≠ .rootb) (hos : Ey.mode.ownSlot = true) (x : Var) :
    EntryWeaker (popE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (popE y Ey t)) := by
  have hv : ownHeld true (Ty.vec t) S.A = ownHeld true t S.A := by simp [ownHeld, Ty.holdsView]
  have hl : (S.liftE y Ey).held = rds S.ρ Ey.held ++ ownHeld true t S.A := by
    rw [liftE_held hrb, hos, ht, hv]
  cases t with
  | vec s =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | prod a b =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | sum a b =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | fn ms =>
    refine EntryWeaker.mk' (by simp [popE, liftE]) (by simp [popE, liftE, liftMode])
      (by simp [popE]) (by simp [popE, liftE]) (fun h' => by simp [popE, Mode.ownSlot] at h') ?_
    show (S.liftE y Ey).held ⊆ _
    rw [hl, liftE_held (by simp [popE])]; simp [popE, Mode.ownSlot]
  | int => exact elemE_lift h hab hy .int x
  | slice s => exact elemE_lift h hab hy (.slice s) x

/-- A field read, where the call places it. -/
theorem projE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) :
    EntryWeaker (projE (S.ρ y) (S.liftE y Ey) t) (S.liftE x (projE y Ey t)) := by
  have hl := held_lift h hab hy
  have hpd : projDeps (S.ρ y) (S.liftE y Ey) ⊆ rds S.ρ (projDeps y Ey) ++ S.A := by
    by_cases hrb : Ey.mode = .rootb
    · have hm : (S.liftE y Ey).mode = .rootb := (liftE_rootb h).mpr hrb
      simp only [projDeps, hm, hrb, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte]
      intro d hd; simp at hd; subst hd; simp [rds, Dep.ren]
    have hm' : (S.liftE y Ey).mode ≠ .rootb := fun e => hrb ((liftE_rootb h).mp e)
    have hos : (S.liftE y Ey).mode.ownSlot = Ey.mode.ownSlot := by
      rw [liftE_mode y hrb]; cases hm : Ey.mode <;> rfl
    unfold projDeps; rw [hos]; simp only [hm', hrb, ↓reduceIte]
    split
    · intro d hd; simp at hd; subst hd; simp [rds, Dep.ren]
    · rename_i hos'
      have : (liftMode Ey.mode).ownSlot = false := by
        cases hm : Ey.mode <;> simp_all [liftMode, Mode.ownSlot]
      have hf : Ey.mode.ownSlot = false := by simpa using hos'
      intro d hd
      simpa [liftE, hrb, this, hf] using hd
  cases t with
  | int => exact intE_lift x
  | _ =>
    refine EntryWeaker.mk' (by simp [projE, liftE]) (by simp [projE, liftE, liftMode])
      (by simp [projE]) (by simp [projE, liftE]) (fun _ => ?_) ?_
    · simp only [projE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true,
        rds, List.map_append]
      intro d hd
      rcases List.mem_append.mp hd with hd | hd
      · rcases List.mem_append.mp (hpd hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_left _ h1)
        · exact List.mem_append_right _ h1
      · rcases List.mem_append.mp (hl hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_right _ h1)
        · exact List.mem_append_right _ h1
    · simp only [projE, liftE, reduceCtorEq, ↓reduceIte]; exact hl

/-- A field moved out of a struct taken apart, where the call places it. -/
theorem ownHeld_lift {X L : List Dep} {t : Ty} (hl : X ⊆ rds S.ρ L ++ S.A) :
    ownHeld true t X ⊆ rds S.ρ (ownHeld true t L) ++ ownHeld true t S.A := by
  unfold ownHeld; split
  · intro d hd; cases hd
  · exact hl

theorem compE_lift (h : S.OK) (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (t : Ty) (x : Var) : EntryWeaker (compE (S.liftE y Ey) t) (S.liftE x (compE Ey t)) := by
  have hl := held_lift h hab hy
  cases t with
  | int => exact intE_lift x
  | slice s =>
    refine EntryWeaker.mk' (by simp [compE, liftE]) (by simp [compE, liftE, liftMode])
      (by simp [compE]) (by simp [compE, liftE]) (fun _ => ?_) ?_
    · simp only [compE, liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact hl
    · simp only [compE, liftE, reduceCtorEq, ↓reduceIte]; exact hl
  | vec s =>
    refine EntryWeaker.mk' (by simp [compE, liftE]) (by simp [compE, liftE, liftMode])
      (by simp [compE]) (by simp [compE, liftE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot]; exact ownHeld_lift hl
  | prod a b =>
    refine EntryWeaker.mk' (by simp [compE, liftE]) (by simp [compE, liftE, liftMode])
      (by simp [compE]) (by simp [compE, liftE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot]; exact ownHeld_lift hl
  | sum a b =>
    refine EntryWeaker.mk' (by simp [compE, liftE]) (by simp [compE, liftE, liftMode])
      (by simp [compE]) (by simp [compE, liftE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot]; exact ownHeld_lift hl
  | fn ms =>
    refine EntryWeaker.mk' (by simp [compE, liftE]) (by simp [compE, liftE, liftMode])
      (by simp [compE]) (by simp [compE, liftE]) (fun h' => by simp [compE, Mode.ownSlot] at h') ?_
    simp only [compE, liftE, reduceCtorEq, ↓reduceIte, Mode.ownSlot]; exact ownHeld_lift hl

theorem AbsOK.setE' {Γ0 Γ1 : Ctx} (hab : S.AbsOK Γ1) (hab0 : S.AbsOK Γ0) {x : Var} {E0 E : Entry}
    (hx : Γ0 x = some E0) (hm : E.mode = E0.mode) (ht : E.ty = E0.ty) (hrb : E.mode ≠ .rootb)
    (hfx : E.fixed → E.live = true ∧ E.held = []) :
    S.AbsOK (A2.setE Γ1 x E) := by
  refine hab.setE hrb (fun b hb => ?_) (fun bh hb => ?_) (fun bh hb => ?_) (fun _ _ => hfx)
  · rw [ht]; exact hab0.2.1 x E0 b hx (hm ▸ hb)
  · obtain ⟨E', hE', hm', _⟩ := hab0.2.2 x bh hb
    rw [hx] at hE'; cases hE'; rw [hm]; exact hm'
  · obtain ⟨E', hE', _, ht', _⟩ := hab0.2.2 x bh hb
    rw [hx] at hE'; cases hE'; rw [ht]; exact ht'

theorem AbsOK.fresh {Γ : Ctx} (hab : S.AbsOK Γ) {x : Var} (hx : Γ x = none) : S.bnd x = none := by
  cases hb : S.bnd x with
  | none => rfl
  | some bh => obtain ⟨E, hE, _⟩ := hab.2.2 x bh hb; rw [hx] at hE; cases hE

/-- A fixed `inout` binding of the callee is live and holds nothing. -/
theorem AbsOK.fixed {Γ : Ctx} (hab : S.AbsOK Γ) {v : Var} {E : Entry} (hv : Γ v = some E)
    (hf : E.fixed) (hrb : E.mode ≠ .rootb) : E.live = true ∧ E.held = [] := by
  rcases hf with h | ⟨b, hb, _⟩
  · exact absurd h hrb
  · obtain ⟨_, hbv⟩ := hab.2.1 v E b hv hb
    obtain ⟨E', hE', _, _, hfx⟩ := hab.2.2 v _ hbv
    rw [hv] at hE'; cases hE'
    exact hfx (Or.inr ⟨b, hb, by assumption⟩)

theorem AbsOK.add {Γ Γ1 : Ctx} (hab0 : S.AbsOK Γ) (hab : S.AbsOK Γ1) {x : Var} (hx : Γ x = none)
    {E : Entry} (hm : E.mode = .own ∨ E.mode = .bor) : S.AbsOK (A2.setE Γ1 x E) := by
  have hbx := hab0.fresh hx
  refine hab.setE (by rcases hm with hm | hm <;> rw [hm] <;> simp) (fun b hb => ?_) (fun bh hb => ?_)
    (fun bh hb => ?_) (fun bh hb => ?_)
  · rcases hm with hm | hm <;> rw [hm] at hb <;> cases hb
  · rw [hbx] at hb; cases hb
  · rw [hbx] at hb; cases hb
  · rw [hbx] at hb; cases hb

/-- Nothing the call can see pins a binding the callee may replace: a
    borrowed parameter's dependencies are outside the callee, and the frame
    holds by name no `inout` argument the callee may replace (`Φsat`). -/
theorem NoPin.lift (h : S.OK) (_hab : S.AbsOK Γa) {y : Var}
    (hb : ∀ bh, S.bnd y = some bh → bh.1 = .replace) : NoPin (S.canon Γa) (S.ρ y) := by
  intro q E hq hm d hd hbd hdr
  rcases canon_cases h Γa q with ⟨v, rfl, hc⟩ | ⟨hqf, hc⟩
  · rw [hc] at hq
    cases hE : Γa v with
    | none => rw [hE] at hq; cases hq
    | some E0 =>
      rw [hE] at hq; simp only [Option.map_some, Option.some.injEq] at hq; subst hq
      have hrb : E0.mode = .rootb := (liftE_rootb h).mp hm
      have hvd : (S.liftE v E0).vdeps = (S.pe v).vdeps := by simp [liftE, hrb, Entry.vdeps]
      rw [hvd] at hd
      obtain ⟨b, t, rfl, hbb, _, _, hbr, _⟩ := pe_ρ h hd hdr
      exact hbr (hb _ hbb)
  · rw [hc] at hq
    obtain ⟨b, hv, hbb, hk⟩ := h.Φsat q E hq (h.Φrb q E hq hm) (Or.inr hm) d hd y hdr.symm
    have := hb _ hbb; simp only at this; subst this
    obtain ⟨r, k⟩ := d
    cases k <;> simp_all [Kind.bound, Eff.kills]

theorem bnd_own (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey) (hm : Ey.mode = .own) :
    ∀ bh, S.bnd y = some bh → bh.1 = .replace := fun bh hb => by
  obtain ⟨E, hE, hmE, _⟩ := hab.2.2 y bh hb
  rw [hy] at hE; cases hE; rw [hm] at hmE; cases hmE

theorem bnd_replace (hab : S.AbsOK Γa) {y : Var} {Ey : Entry} (hy : Γa y = some Ey)
    (hm : Ey.mode = .own ∨ Ey.mode = .inout .replace ∨ Ey.mode = .bor) :
    ∀ bh, S.bnd y = some bh → bh.1 = .replace := fun bh hb => by
  obtain ⟨E, hE, hmE, _⟩ := hab.2.2 y bh hb
  rw [hy] at hE; cases hE
  rcases hm with hm | hm | hm <;> rw [hm] at hmE
  · cases hmE
  · exact (Mode.inout.inj hmE).symm
  · cases hmE

theorem PushArg.ty_at {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hp : PushArg Γ F y Ey t D Γ1) (hy : Γ y = some Ey) {x : Var} {Ex Ex1 : Entry} (hx : Γ x = some Ex)
    (hx1 : Γ1 x = some Ex1) : Ex1.ty = Ex.ty := by
  cases hp with
  | move =>
    by_cases hxy : x = y
    · subst hxy; simp only [A2.setE, upd_same, Option.some.injEq] at hx1
      rw [hy] at hx; cases hx; subst hx1; rfl
    · simp only [A2.setE, upd_ne _ _ hxy, A2.kill, hx, Option.map_some, Option.some.injEq] at hx1
      subst hx1; exact killE_ty _ _ _ _
  | int => rw [hx] at hx1; cases hx1; rfl
  | slice => rw [hx] at hx1; cases hx1; rfl

theorem PushArg.absOK {Γ Γ1 : Ctx} {F : List Var} {y : Var} {Ey : Entry} {t : Ty} {D : List Dep}
    (hy : Γ y = some Ey) (hp : PushArg Γ F y Ey t D Γ1) (hab : S.AbsOK Γ) : S.AbsOK Γ1 := by
  cases hp with
  | move _ hm _ _ => exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (by simp [hm])
  | int => exact hab
  | slice => exact hab

/-- A closure literal's captures, checked in the callee, hold where the
    call places it. -/
theorem CapsOK.lift (h : S.OK) (_hab : S.AbsOK Γa) {Fa : List Var} {D D1 : List Dep}
    {cs : List (Var × PMode × Ty)} (hc : CapsOK Γa Fa D cs) (hD : D1 ⊆ rds S.ρ D ++ S.A) :
    CapsOK (S.canon Γa) S.Fc D1 (cs.map fun c => (S.ρ c.1, c.2)) := by
  have hroot1 : ∀ d ∈ D1, ∀ v, d.root = S.ρ v → ∃ d0 ∈ D, d0.root = v ∧ d.kind = d0.kind := by
    intro d hd v hv
    rcases List.mem_append.mp (hD hd) with hd' | hd'
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd'
      exact ⟨d0, hd0, h.inj _ _ hv, rfl⟩
    · exact absurd hv.symm (A_out h hd' v)
  have hargE : ∀ c ∈ cs, ∀ Ev, Γa c.1 = some Ev → Ev.mode.ownSlot = true →
      argE (S.canon Γa) (S.ρ c.1) = S.liftE c.1 Ev := by
    intro c _ Ev hEv _
    unfold argE; rw [canon_ρ h, hEv]; rfl
  refine ⟨?_, fun c' hc' => ?_⟩
  · have he : ((cs.map fun c => (S.ρ c.1, c.2)).map (·.1)) = (cs.map (·.1)).map S.ρ := by
      simp [List.map_map, Function.comp_def]
    rw [he]; exact List.Pairwise.map S.ρ (fun a b hne e => hne (h.inj a b e)) hc.1
  · obtain ⟨c, hc1, rfl⟩ := List.mem_map.mp hc'
    obtain ⟨Ev, hEv, hl, hh, ht, ho, hhv, hmode⟩ := hc.2 c hc1
    have hrb : Ev.mode ≠ .rootb := fun e => by rw [e] at ho; cases ho
    refine ⟨S.liftE c.1 Ev, by rw [canon_ρ h, hEv]; rfl, by rw [liftE_live]; exact hl,
      liftE_held_named hrb ho hh (by rw [ht]; exact hhv),
      by rw [liftE_ty _ hrb]; exact ht, by rw [liftE_mode _ hrb, liftMode_ownSlot]; exact ho, hhv, ?_⟩
    rcases hmode with ⟨hinp, hrd⟩ | ⟨b, s, hb, hbn, hbr, hcan, hcF, hts, hsv, hnD, hnc⟩
    · refine Or.inl ⟨hinp, fun d hd hdr hn => ?_⟩
      obtain ⟨d0, hd0, hr0, hk0⟩ := hroot1 d hd c.1 hdr
      rw [hk0]; exact hrd d0 hd0 hr0 (hk0 ▸ hn)
    · refine Or.inr ⟨b, s, hb, hbn, hbr, by rw [liftE_mode _ hrb]; exact canDo_lift hcan, h.Fcout _, hts,
        hsv, fun d hd hdr => ?_, fun c'' hc'' d hd hdr => ?_⟩
      · obtain ⟨d0, hd0, hr0, _⟩ := hroot1 d hd c.1 hdr
        exact hnD d0 hd0 hr0
      · obtain ⟨c2, hc2, rfl⟩ := List.mem_map.mp hc''
        obtain ⟨Ev2, hEv2, _, _, _, ho2, _⟩ := hc.2 c2 hc2
        have hrb2 : Ev2.mode ≠ .rootb := fun e => by rw [e] at ho2; cases ho2
        rw [hargE c2 hc2 Ev2 hEv2 ho2] at hd
        simp only [liftE, hrb2, ↓reduceIte] at hd
        rcases List.mem_append.mp hd with hd' | hd'
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd'
          have hae : argE Γa c2.1 = Ev2 := by unfold argE; rw [hEv2]; rfl
          exact hnc c2 hc2 d0 (by rw [hae]; exact hd0) (h.inj _ _ hdr)
        · exact A_out h (ownHeld_sub _ _ _ hd') c.1 hdr.symm

theorem app_lift {a b a0 b0 X : List Dep} (ha : a ⊆ rds S.ρ a0 ++ X)
    (hb : b ⊆ rds S.ρ b0 ++ X) : a ++ b ⊆ rds S.ρ (a0 ++ b0) ++ X := by
  intro d hd
  simp only [rds, List.map_append, List.mem_append] at hd ha hb ⊢
  rcases hd with hd | hd
  · rcases List.mem_append.mp (ha hd) with h1 | h1
    · exact Or.inl (Or.inl h1)
    · exact Or.inr h1
  · rcases List.mem_append.mp (hb hd) with h1 | h1
    · exact Or.inl (Or.inr h1)
    · exact Or.inr h1


theorem pushArg_ren (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {y : Var} {Ey : Entry} {t : Ty}
    {D : List Dep} {Γa1 : Ctx} (hy : Γa y = some Ey) (hp : PushArg Γa Fa y Ey t D Γa1) :
    ∃ D', PushArg (S.canon Γa) S.Fc (S.ρ y) (S.liftE y Ey) t D' (S.canon Γa1) ∧
      D' ⊆ rds S.ρ D ++ S.A ∧ (Ey.ty = t → D' ⊆ rds S.ρ D ++ ownHeld true t S.A) := by
  cases hp with
  | move ho hm hyF _ =>
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y) { S.liftE y Ey with live := false, dtor := false } := by
      rw [canon_setE h, canon_kill h hab (allowed_own hab hy hm _ _), liftE_moved _ hrb]
    rw [hctx]
    refine ⟨_, PushArg.move ho (by rw [liftE_mode y hrb, hm]; rfl) (h.Fcout y)
      (NoPin.lift h hab (bnd_own hab hy hm)), held_lift h hab hy, fun hty => ?_⟩
    rw [liftE_held hrb, hm, hty]; exact List.Subset.refl _
  | int => exact ⟨[], PushArg.int, by simp, fun _ => by simp⟩
  | @slice s hm =>
    have hsl : ownHeld true (Ty.slice s) S.A = S.A := by simp [ownHeld, Ty.holdsView]
    have hs : derive (S.ρ y) (S.liftE y Ey) .self ++ (S.liftE y Ey).held ⊆
        rds S.ρ (derive y Ey .self ++ Ey.held) ++ S.A := by
      intro d hd
      rcases List.mem_append.mp hd with hd | hd
      · rcases List.mem_append.mp (derive_lift h hab hy .self rfl hd) with h1 | h1
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
          exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_left _ hd0, rfl⟩)
        · exact List.mem_append_right _ h1
      · rcases List.mem_append.mp (held_lift h hab hy hd) with h1 | h1
        · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
          exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_right _ hd0, rfl⟩)
        · exact List.mem_append_right _ h1
    refine ⟨_, PushArg.slice ?_, hs, fun _ => by rw [hsl]; exact hs⟩
    rcases hm with hm | hm
    · left; rw [liftE_mode y (by rw [hm]; simp), hm]; rfl
    · right; rw [liftE_rootb h]; exact hm

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
  | @moveOwn y Ey hy hl hm hyF _ =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y) { S.liftE y Ey with live := false, dtor := false } := by
      rw [canon_setE h, canon_kill h hab (allowed_own hab hy hm _ _), liftE_moved _ hrb]
    rw [hctx]
    refine ⟨_, RhsT.moveOwn hc (by rw [liftE_live]; exact hl) (by rw [liftE_mode y hrb, hm]; rfl)
      (h.Fcout y) (NoPin.lift h hab (bnd_own hab hy hm)), fun x => ?_⟩
    have he : S.liftE x ⟨Ey.ty, .own, true, [], Ey.held, false⟩ =
        ⟨(S.liftE y Ey).ty, .own, true, [], (S.liftE y Ey).held, false⟩ := by
      simp [liftE, hm, liftMode, rds, Mode.ownSlot]
    rw [he]; exact EntryWeaker.refl _
  | @copyRoot y Ey hy hl hm =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    refine ⟨_, RhsT.copyRoot hc (by rw [liftE_live]; exact hl) (by rw [liftE_rootb h]; exact hm),
      fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; exact (liftE_ty' h hab hy).symm)
      (by simp [liftE, liftMode]) (by simp) (by simp [liftE]) (fun _ => ?_) ?_
    · simp only [liftE, reduceCtorEq, ↓reduceIte, liftMode, Mode.ownSlot, Bool.false_eq_true]
      exact derive_lift h hab hy .self rfl
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
      exact derive_lift h hab hy .self rfl
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
      exact derive_lift h hab hy .view rfl
    · simp only [liftE, reduceCtorEq, ↓reduceIte]; exact held_lift h hab hy
  | @sat y i Ey t hy hl ht hi =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    exact ⟨_, RhsT.sat hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht)
      (exprT_ren h hab hi), fun x => elemE_lift h hab hy t x⟩
  | @pop y Ey t hy hl ht hcan hyF =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    have hrb : Ey.mode ≠ .rootb := by
      rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp
    have hos : Ey.mode.ownSlot = true := by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> rfl
    rw [canon_kill h hab (allowed_canDo hab hy ht hcan)]
    exact ⟨_, RhsT.pop hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht)
      (by rw [liftE_mode y hrb]; exact canDo_lift hcan) (h.Fcout y), fun x => popE_lift h hab hy ht hrb hos x⟩
  | @pair y z Ey Ez Γa1 Γa2 Dy Dz hy hly hpa1 hz hlz hpa2 hzd =>
    have hc1 : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_ren h hab hy hpa1
    have hab1 := PushArg.absOK (S := S) hy hpa1 hab
    have hc2 : S.canon Γa1 (S.ρ z) = some (S.liftE z Ez) := by rw [canon_ρ h, hz]; rfl
    obtain ⟨D2, hp2, hD2, hD2o⟩ := pushArg_ren h hab1 hz hpa2
    have hty1 := liftE_ty' h hab hy
    have hty2 := liftE_ty' h hab1 hz
    rw [← hty1] at hp1
    rw [← hty2] at hp2
    have hzd' : (S.liftE z Ez).mode.ownSlot = true → S.ρ z ∉ roots D1 := by
      intro hos hr
      have hos' : Ez.mode.ownSlot = true := by
        by_cases hrb : Ez.mode = .rootb
        · rw [(liftE_rootb h).mpr hrb] at hos; cases hos
        · rw [liftE_mode z hrb] at hos; cases hm : Ez.mode <;> simp_all [liftMode, Mode.ownSlot]
      obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
      rcases List.mem_append.mp (hD1 hd) with h1 | h1
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
        have : d0.root = z := h.inj _ _ hdr
        exact hzd hos' (this ▸ List.mem_map_of_mem hd0)
      · exact A_out h h1 z hdr.symm
    refine ⟨_, RhsT.pair hc1 (by rw [liftE_live]; exact hly) hp1 hc2 (by rw [liftE_live]; exact hlz) hp2 hzd',
      fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; simp [hty1, hty2]) (by simp [liftE, liftMode]) (by simp)
      (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    simp only [liftE, reduceCtorEq, ↓reduceIte]
    have hm1 : ownHeld true Ey.ty S.A ⊆ ownHeld true (.prod Ey.ty Ez.ty) S.A :=
      ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _
    have hm2 : ownHeld true Ez.ty S.A ⊆ ownHeld true (.prod Ey.ty Ez.ty) S.A :=
      ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _
    exact app_lift (fun d hd => append_sub (List.Subset.refl _) hm1 (hD1o rfl hd))
      (fun d hd => append_sub (List.Subset.refl _) hm2 (hD2o rfl hd))
  | @fst y Ey a b hy hl ht =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    exact ⟨_, RhsT.fst hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht),
      fun x => projE_lift h hab hy a x⟩
  | @snd y Ey a b hy hl ht =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    exact ⟨_, RhsT.snd hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht),
      fun x => projE_lift h hab hy b x⟩
  | @inl y b Ey Γa1 D hy hly hpa hb =>
    have hc1 : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_ren h hab hy hpa
    have hty1 := liftE_ty' h hab hy
    rw [← hty1] at hp1
    refine ⟨_, RhsT.inl hc1 (by rw [liftE_live]; exact hly) hp1 hb, fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; simp [hty1]) (by simp [liftE, liftMode]) (by simp)
      (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    simp only [liftE, reduceCtorEq, ↓reduceIte]
    exact fun d hd => append_sub (List.Subset.refl _)
      (ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _) (hD1o rfl hd)
  | @inr a y Ey Γa1 D hy hly hpa ha =>
    have hc1 : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_ren h hab hy hpa
    have hty1 := liftE_ty' h hab hy
    rw [← hty1] at hp1
    refine ⟨_, RhsT.inr hc1 (by rw [liftE_live]; exact hly) hp1 ha, fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]; simp [hty1]) (by simp [liftE, liftMode]) (by simp)
      (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    simp only [liftE, reduceCtorEq, ↓reduceIte]
    exact fun d hd => append_sub (List.Subset.refl _)
      (ownHeld_mono (fun h => by simp [Ty.holdsView, h]) _) (hD1o rfl hd)
  | @pack fs te ms y cs Ey Γa1 D hy hly hte hpa hcaps =>
    have hc1 : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    obtain ⟨D1, hp1, hD1, hD1o⟩ := pushArg_ren h hab hy hpa
    have hty1 := liftE_ty' h hab hy
    refine ⟨_, RhsT.pack hc1 (by rw [liftE_live]; exact hly) (by rw [hty1]; exact hte) hp1
      (CapsOK.lift h (PushArg.absOK hy hpa hab) hcaps hD1), fun x => ?_⟩
    refine EntryWeaker.mk' (by rw [liftE_ty x (by simp)]) (by simp [liftE, liftMode]) (by simp)
      (by simp [liftE]) (fun h' => by simp [Mode.ownSlot] at h') ?_
    simp only [liftE, reduceCtorEq, ↓reduceIte]
    intro d hd
    rcases List.mem_append.mp hd with hd | hd
    · rcases List.mem_append.mp (hD1 hd) with hd' | hd'
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd'
        exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_left _ hd0, rfl⟩)
      · exact List.mem_append_right _ hd'
    · obtain ⟨c', hc', rfl⟩ := List.mem_map.mp hd
      obtain ⟨c, hc, rfl⟩ := List.mem_map.mp hc'
      exact List.mem_append_left _ (mem_rds.mpr ⟨⟨c.1, .name c.2.1.bound c.2.2⟩,
        List.mem_append_right _ (List.mem_map_of_mem hc), rfl⟩)
  | @getl y Ey a b hy hl ht =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    exact ⟨_, RhsT.getl hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht),
      fun x => projE_lift h hab hy a x⟩
  | @getr y Ey a b hy hl ht =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    exact ⟨_, RhsT.getr hc (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hy]; exact ht),
      fun x => projE_lift h hab hy b x⟩
  | @takel y Ey a b hy hl hm hty hyF _ =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y) { S.liftE y Ey with live := false, dtor := false } := by
      rw [canon_setE h, canon_kill h hab (allowed_own hab hy hm _ _), liftE_moved _ hrb]
    rw [hctx]
    exact ⟨_, RhsT.takel hc (by rw [liftE_live]; exact hl) (by rw [liftE_mode y hrb, hm]; rfl)
      (by rw [liftE_ty' h hab hy]; exact hty) (h.Fcout y) (NoPin.lift h hab (bnd_own hab hy hm)),
      fun x => compE_lift h hab hy a x⟩
  | @taker y Ey a b hy hl hm hty hyF _ =>
    have hc : S.canon Γa (S.ρ y) = some (S.liftE y Ey) := by rw [canon_ρ h, hy]; rfl
    have hrb : Ey.mode ≠ .rootb := by rw [hm]; simp
    have hctx : S.canon (setE (kill .replace false y Γa) y { Ey with live := false, dtor := false }) =
        setE (kill .replace false (S.ρ y) (S.canon Γa)) (S.ρ y) { S.liftE y Ey with live := false, dtor := false } := by
      rw [canon_setE h, canon_kill h hab (allowed_own hab hy hm _ _), liftE_moved _ hrb]
    rw [hctx]
    exact ⟨_, RhsT.taker hc (by rw [liftE_live]; exact hl) (by rw [liftE_mode y hrb, hm]; rfl)
      (by rw [liftE_ty' h hab hy]; exact hty) (h.Fcout y) (NoPin.lift h hab (bnd_own hab hy hm)),
      fun x => compE_lift h hab hy b x⟩

theorem mem_allKinds_iff {L : List Var} {d : Dep} : d ∈ allKinds L ↔ d.root ∈ L ∧ d.kind.isName = false := by
  constructor
  · intro h
    refine ⟨mem_allKinds h, ?_⟩
    simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil,
      or_false] at h
    obtain ⟨r, _, h⟩ := h
    rcases h with rfl | rfl | rfl <;> rfl
  · intro ⟨hd, hk⟩
    simp only [allKinds, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false]
    exact ⟨d.root, hd, by obtain ⟨r, k⟩ := d; cases k <;> simp_all [Kind.isName]⟩

/-- Pointwise: each entry of `Γ` is at least as strong as `Γ'`'s. -/
def PW (Γ Γ' : Ctx) : Prop :=
  ∀ v, (Γ v = none ↔ Γ' v = none) ∧ ∀ E E', Γ v = some E → Γ' v = some E' → EntryWeaker E E'

theorem PW.weaker {Γ Γ' : Ctx} (h : PW Γ Γ') (hw : CtxWF Γ') (hn : NameWF Γ') : Weaker Γ Γ' := ⟨h, hw, hn⟩

theorem PW.refl (Γ : Ctx) : PW Γ Γ := fun v => ⟨Iff.rfl, fun E E' h1 h2 => by
  rw [h1] at h2; cases h2; exact EntryWeaker.refl _⟩

theorem PW.kill {Γ Γ' : Ctx} (h : PW Γ Γ') (e : Eff) (hv : Bool) (x : Var) :
    PW (A2.kill e hv x Γ) (A2.kill e hv x Γ') := by
  intro v
  refine ⟨?_, fun E E' h1 h2 => ?_⟩
  · simp only [A2.kill, Option.map_eq_none_iff]; exact (h v).1
  · simp only [A2.kill] at h1 h2
    cases hE : Γ v with
    | none => rw [hE] at h1; cases h1
    | some E0 =>
      cases hE' : Γ' v with
      | none => rw [hE'] at h2; cases h2
      | some E0' =>
        rw [hE] at h1; rw [hE'] at h2; cases h1; cases h2
        exact killE_weaker ((h v).2 E0 E0' hE hE')

theorem PW.setE {Γ Γ' : Ctx} (h : PW Γ Γ') {x : Var} {E E' : Entry} (he : EntryWeaker E E') :
    PW (A2.setE Γ x E) (A2.setE Γ' x E') := by
  intro v
  by_cases hvx : v = x
  · subst hvx; simp only [A2.setE, upd_same, reduceCtorEq, iff_self, Option.some.injEq, true_and]
    intro a b ha hb; subst ha hb; exact he
  · simp only [A2.setE, upd_ne _ _ hvx]; exact h v

theorem getD_map {args : List Var} {i : Nat} (hi : i < args.length) (ρ : Var → Var) :
    (args.map ρ).getD i 0 = ρ (args.getD i 0) := by
  simp [List.getD, hi]

theorem argE_canon (h : S.OK) {a : Var} {Ea : Entry} (ha : Γa a = some Ea) :
    argE (S.canon Γa) (S.ρ a) = S.liftE a Ea := by
  unfold argE; rw [canon_ρ h, ha]; rfl

theorem sub_rds_append {a b : List Dep} {L : List Dep} (ha : a ⊆ rds S.ρ L ++ S.A)
    (hb : b ⊆ rds S.ρ L ++ S.A) : a ++ b ⊆ rds S.ρ L ++ S.A := by
  intro d hd; rcases List.mem_append.mp hd with h | h
  · exact ha h
  · exact hb h

theorem sub_mono {a L L' : List Dep} (ha : a ⊆ rds S.ρ L ++ S.A) (hL : L ⊆ L') :
    a ⊆ rds S.ρ L' ++ S.A :=
  fun _ hd => append_sub (rds_subset hL) (List.Subset.refl _) (ha hd)

theorem argDeps_lift (h : S.OK) (hab : S.AbsOK Γa) {args : List Var} {j : Nat} (hj : j < args.length)
    {Ea : Entry} (hEa : Γa (args.getD j 0) = some Ea) (k : Kind) (hk : k.isName = false) :
    argDeps (S.canon Γa) (args.map S.ρ) (j, k) ⊆ rds S.ρ (argDeps Γa args (j, k)) ++ S.A := by
  unfold argDeps
  simp only [getD_map hj, argE_canon h hEa, liftE_ty' h hab hEa]
  have hae : argE Γa (args.getD j 0) = Ea := by unfold argE; rw [hEa]; rfl
  rw [hae]
  split
  · simp
  · exact derive_lift h hab hEa k hk

theorem vdeps_sub {E E' : Entry} (hw : EntryWeaker E E') (hl : E'.live = true) : E.vdeps ⊆ E'.vdeps := by
  obtain ⟨_, hm, _, hlv⟩ := hw
  obtain ⟨_, hp, hh⟩ := hlv hl
  unfold Entry.vdeps; rw [hm]
  cases ho : E.mode.ownSlot with
  | true => exact append_sub (List.Subset.refl _) hh
  | false => exact append_sub (hp ho) hh


/-- What a borrowed parameter depends on in the callee: the symbolic names
    of the `inout` parameters, when its type may hold a closure. -/
theorem vdeps_rootb (hab : S.AbsOK Γa) {a : Var} {Ea : Entry} (hEa : Γa a = some Ea)
    (hrb : Ea.mode = .rootb) : Ea.vdeps = if (S.pe a).ty.hasFn then S.sym else [] := by
  obtain ⟨hty, hp, hh⟩ := hab.1 a Ea hEa hrb
  simp only [Entry.vdeps, hp, hh, hrb, Mode.ownSlot, Bool.false_eq_true, ↓reduceIte, List.nil_append, hty]

/-- A borrowed parameter's abstract entry holds the symbolic name of an
    `inout` parameter whenever its type may hold a closure. -/
theorem abs_sym (hab : S.AbsOK Γa) {a : Var} {Ea : Entry} (hEa : Γa a = some Ea) (hrb : Ea.mode = .rootb)
    (hf : (S.pe a).ty.hasFn = true) {d : Dep} (hd : d ∈ S.sym) : d ∈ Ea.vdeps := by
  rw [vdeps_rootb hab hEa hrb, hf]; simpa using hd

/-- What a lifted binding holds by name: what the binding it lifts does, or
    what the arguments do. -/
theorem names_liftE (h : S.OK) (hab : S.AbsOK Γa) {a : Var} {Ea : Entry} (hEa : Γa a = some Ea) {d : Dep}
    (hd : d ∈ (S.liftE a Ea).vdeps) (hn : d.kind.isName = true) :
    (∃ d0 ∈ Ea.vdeps, d = d0.ren S.ρ) ∨ d ∈ S.N := by
  by_cases hrb : Ea.mode = .rootb
  · have hvd : (S.liftE a Ea).vdeps = (S.pe a).vdeps := by simp [liftE, hrb, Entry.vdeps]
    rw [hvd] at hd
    rcases h.pe_names a d hd hn with hN | ⟨hs, hf⟩
    · exact Or.inr hN
    · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hs
      exact Or.inl ⟨d0, abs_sym hab hEa hrb hf hd0, rfl⟩
  · rcases liftE_vdeps_cases hrb hd with h1 | h1
    · exact Or.inl h1
    · rcases mem_A.mp h1 with h2 | h2
      · rw [allKinds_notName h2] at hn; cases hn
      · exact Or.inr h2

/-- Every argument of a well-typed call is bound. -/
theorem CallT.args_some {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) : ∀ a ∈ args, ∃ Ea, Γ a = some Ea := by
  obtain ⟨fn, _, hlen, hargs, _⟩ := hc
  intro a ha
  obtain ⟨i, hi, rfl⟩ := mem_args ha
  obtain ⟨Ea, hEa, _⟩ := hargs i (hlen ▸ hi)
  exact ⟨Ea, hEa⟩

/-- What a closure handed to a call in the callee may change, where the call
    places it: what it may change in the callee, or what the arguments'
    closures may. -/
theorem mem_mutNames_canon (h : S.OK) (hab : S.AbsOK Γa) {args : List Var}
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) {d : Dep}
    (hd : d ∈ mutNames (S.canon Γa) (args.map S.ρ)) :
    d ∈ rds S.ρ (mutNames Γa args) ∨ (d ∈ S.N ∧ d.kind.bound ≠ .none) := by
  unfold mutNames at hd ⊢
  obtain ⟨hd, hb⟩ := List.mem_filter.mp hd
  simp only [argNames, List.flatMap_map, List.mem_flatMap] at hd
  obtain ⟨a, ha, hda⟩ := hd
  obtain ⟨Ea, hEa⟩ := hargs a ha
  rw [argE_canon h hEa, liftE_ty' h hab hEa] at hda
  have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
  split at hda
  · simp at hda
  · rename_i hn
    obtain ⟨hdv, hdn⟩ := List.mem_filter.mp hda
    rcases names_liftE h hab hEa hdv hdn with ⟨d0, hd0, rfl⟩ | hN
    · refine Or.inl (mem_rds.mpr ⟨d0, List.mem_filter.mpr ⟨?_, hb⟩, rfl⟩)
      simp only [argNames, List.mem_flatMap]
      exact ⟨a, ha, by rw [hae, ite_eq_right hn]; exact List.mem_filter.mpr ⟨hd0, hdn⟩⟩
    · exact Or.inr ⟨hN, by simpa using hb⟩

/-- What a closure the callee hands to a call may change, where the call
    places it: a closure the renamed call hands over may change it too, or
    it is an `inout` argument the callee's symbolic name stands for (which
    the closure handed over may or may not hold). -/
theorem mutNames_canon_sub (h : S.OK) (hab : S.AbsOK Γa) {args : List Var}
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) :
    ∀ d ∈ rds S.ρ (mutNames Γa args), d ∈ mutNames (S.canon Γa) (args.map S.ρ) ∨
      ∃ w b t, d = ⟨S.ρ w, .name b t⟩ ∧ S.bnd w = some (b, false) ∧ b ≠ .replace := by
  intro d hd
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  unfold mutNames at hd0 ⊢
  obtain ⟨hd0, hb⟩ := List.mem_filter.mp hd0
  simp only [argNames, List.mem_flatMap] at hd0
  obtain ⟨a, ha, hda⟩ := hd0
  obtain ⟨Ea, hEa⟩ := hargs a ha
  have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
  rw [hae] at hda
  split at hda
  · simp at hda
  · rename_i hn
    obtain ⟨hdv, hdn⟩ := List.mem_filter.mp hda
    by_cases hrb : Ea.mode = .rootb
    · -- a symbolic name
      have hs : d0 ∈ S.sym := by
        rw [vdeps_rootb hab hEa hrb] at hdv
        split at hdv
        · exact hdv
        · cases hdv
      obtain ⟨w, b, t, rfl, hbw, _, _, hbr⟩ := h.sym_ok d0 hs
      exact Or.inr ⟨w, b, t, rfl, hbw, hbr⟩
    · refine Or.inl (List.mem_filter.mpr ⟨?_, hb⟩)
      simp only [argNames, List.flatMap_map, List.mem_flatMap]
      refine ⟨a, ha, ?_⟩
      rw [argE_canon h hEa, liftE_ty' h hab hEa, ite_eq_right hn]
      exact List.mem_filter.mpr ⟨(mem_liftE_vdeps hrb).mpr (Or.inl ⟨d0, hdv, rfl⟩), hdn⟩

theorem kills_isName {e : Eff} (he : e ≠ .replace) (hv : Bool) {k : Kind} (hk : k.isName = true) :
    e.kills hv k = false := by
  cases k with
  | name b t => cases e <;> simp_all [Eff.kills]
  | _ => simp [Kind.isName] at hk

theorem hits_false_of {e : Eff} {hv : Bool} {x : Var} {E : Entry}
    (h : ∀ d ∈ E.vdeps, d.root = x → e.kills hv d.kind = false) : hits e hv x E = false := by
  unfold hits
  cases h1 : E.vdeps.any (fun d => d.root == x && e.kills hv d.kind) with
  | false => simp
  | true =>
    obtain ⟨d, hd, hdd⟩ := List.any_eq_true.mp h1
    simp only [Bool.and_eq_true, beq_iff_eq] at hdd
    rw [h d hd hdd.1] at hdd; cases hdd.2

theorem isName_of_bound {k : Kind} (h : k.bound ≠ .none) : k.isName = true := by
  cases k <;> simp_all [Kind.bound, Kind.isName]

theorem N_bound (h : S.OK) {d : Dep} (hd : d ∈ S.N) (hb : d.kind.bound ≠ .none) :
    d.kind.bound ≠ .replace := by
  have hn := h.N_name d hd
  obtain ⟨r, k⟩ := d
  cases k with
  | name b t =>
    obtain ⟨_, _, _, _, _, _, hc, _⟩ := h.N_named _ hd b t rfl
    rcases hc with hc | ⟨hc, _⟩
    · exact absurd hc hb
    · exact hc
  | _ => simp [Kind.isName] at hn

/-- What the arguments' closures may change ends nothing the call can see:
    the frame has ended it already, and nothing else reaches it but by name. -/
theorem canon_quiet (h : S.OK) (_hab : S.AbsOK Γa) {d : Dep} (hd : d ∈ S.N) (hb : d.kind.bound ≠ .none) :
    ∀ v E, S.canon Γa v = some E → E.live = true → hits d.kind.bound false d.root E = false := by
  obtain ⟨_, hR, _, hpe, _, hΦ⟩ := h.N_mut d hd hb
  have hbr := N_bound h hd hb
  intro y E hy hl
  rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E0 =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq] at hy; subst hy
      refine hits_false_of fun d' hd' hdr => ?_
      by_cases hrb : E0.mode = .rootb
      · have hvd : (S.liftE v E0).vdeps = (S.pe v).vdeps := by simp [liftE, hrb, Entry.vdeps]
        rw [hvd] at hd'
        exact kills_isName hbr false (isName_of_bound (by rw [hpe v d' hd' hdr]; exact hb))
      · rcases liftE_vdeps_cases hrb hd' with ⟨d0, _, rfl⟩ | ha
        · exact absurd hdr ((h.N_out d hd).1 d0.root)
        · rcases mem_A.mp ha with ha | ha
          · exact absurd (hdr ▸ mem_allKinds ha) hR
          · exact kills_isName hbr false (h.N_name d' ha)
  · rw [hc] at hy; exact hΦ y E hy hl

/-- The kills `ds` leave one binding (in any order). -/
def killAll (ds : List Dep) (E : Entry) : Entry :=
  if ds.any (fun d => hits d.kind.bound false d.root E) then { E with live := false } else E

theorem hits_live (e : Eff) (hv : Bool) (x : Var) (E : Entry) (l : Bool) :
    hits e hv x { E with live := l } = hits e hv x E := rfl

theorem killE_killAll (d : Dep) (ds : List Dep) (E : Entry) :
    killE d.kind.bound false d.root (killAll ds E) = killAll (d :: ds) E := by
  have hh : hits d.kind.bound false d.root (killAll ds E) = hits d.kind.bound false d.root E := by
    unfold killAll; split <;> rfl
  unfold killE; rw [hh]
  unfold killAll
  simp only [List.any_cons]
  by_cases h1 : ds.any (fun d => hits d.kind.bound false d.root E) = true <;>
  by_cases h2 : hits d.kind.bound false d.root E = true <;> simp [h1, h2]

theorem killNames_eq : ∀ (ds : List Dep) (Γ : Ctx) (v : Var),
    A2.killNames ds Γ v = (Γ v).map (killAll ds)
  | [], Γ, v => by
    cases h : Γ v <;> simp [A2.killNames, killAll, h]
  | d :: ds, Γ, v => by
    show A2.kill _ _ _ (A2.killNames ds Γ) v = _
    simp only [A2.kill, killNames_eq ds Γ v, Option.map_map]
    cases Γ v with
    | none => rfl
    | some E =>
      simp only [Option.map_some, Function.comp, Option.some.injEq]
      exact killE_killAll d ds E

theorem hits_mono {e : Eff} {hv : Bool} {x : Var} {E E' : Entry} (hw : EntryWeaker E E')
    (hl : E'.live = true) (hh : hits e hv x E = true) : hits e hv x E' = true := by
  unfold hits at hh ⊢
  rw [hw.1, hw.2.1]
  simp only [Bool.and_eq_true] at hh ⊢
  refine ⟨hh.1, ?_⟩
  obtain ⟨d, hd, hdd⟩ := List.any_eq_true.mp hh.2
  exact List.any_eq_true.mpr ⟨d, vdeps_sub hw hl hd, hdd⟩

theorem killAll_weaker {M ds : List Dep} {E E' : Entry} (hw : EntryWeaker E E')
    (hds : ∀ d ∈ ds, d ∈ M ∨ (E.fixed → E.live = true → hits d.kind.bound false d.root E = false))
    (hM : ∀ d ∈ M, d ∈ ds ∨ (E'.live = true → hits d.kind.bound false d.root E' = false)) :
    EntryWeaker (killAll M E) (killAll ds E') := by
  have hkM : ∀ {E0 : Entry}, (killAll M E0).ty = E0.ty ∧ (killAll M E0).mode = E0.mode ∧
      (killAll M E0).path = E0.path ∧ (killAll M E0).held = E0.held := by
    intro E0; unfold killAll; split <;> exact ⟨rfl, rfl, rfl, rfl⟩
  have hkd : ∀ {E0 : Entry}, (killAll ds E0).ty = E0.ty ∧ (killAll ds E0).mode = E0.mode ∧
      (killAll ds E0).path = E0.path ∧ (killAll ds E0).held = E0.held := by
    intro E0; unfold killAll; split <;> exact ⟨rfl, rfl, rfl, rfl⟩
  -- a live `E'` no kill of `ds` hits: no kill of `M` hits `E`
  have hnoM : E'.live = true → ds.any (fun d => hits d.kind.bound false d.root E') = false →
      M.any (fun d => hits d.kind.bound false d.root E) = false := by
    intro hl hn
    cases h1 : M.any (fun d => hits d.kind.bound false d.root E) with
    | false => rfl
    | true =>
      obtain ⟨d, hd, hh⟩ := List.any_eq_true.mp h1
      have hh' := hits_mono hw hl hh
      rcases hM d hd with hd' | hq
      · have : ds.any (fun d => hits d.kind.bound false d.root E') = true :=
          List.any_eq_true.mpr ⟨d, hd', hh'⟩
        rw [hn] at this; cases this
      · rw [hq hl] at hh'; cases hh'
  by_cases hrb : E.fixed
  · have he := hw.2.2.1 hrb
    rw [he] at hnoM ⊢
    -- the same entry: `M` and `ds` hit it alike
    have hsame : killAll M E = killAll ds E := by
      cases hl : E.live with
      | false =>
        unfold killAll; split <;> split <;> first | rfl | (cases E; simp_all)
      | true =>
        cases hn : ds.any (fun d => hits d.kind.bound false d.root E) with
        | false =>
          unfold killAll; rw [hnoM hl hn, hn]
        | true =>
          obtain ⟨d, hd, hh⟩ := List.any_eq_true.mp hn
          have hm : M.any (fun d => hits d.kind.bound false d.root E) = true := by
            rcases hds d hd with hdM | hq
            · exact List.any_eq_true.mpr ⟨d, hdM, hh⟩
            · rw [hq hrb hl] at hh; cases hh
          unfold killAll; rw [hm, hn]
    rw [hsame]; exact EntryWeaker.refl _
  · refine ⟨by rw [hkd.1, hkM.1, hw.1], by rw [hkd.2.1, hkM.2.1, hw.2.1],
      fun e => absurd (by simp only [Entry.fixed_def] at e ⊢; rw [hkM.2.1, hkM.1] at e; exact e) hrb,
      fun hl' => ?_⟩
    have hl0 : E'.live = true ∧ ds.any (fun d => hits d.kind.bound false d.root E') = false := by
      unfold killAll at hl'; split at hl'
      · simp at hl'
      · rename_i hn; exact ⟨hl', by simpa using hn⟩
    obtain ⟨hlE, hp, hh⟩ := hw.2.2.2 hl0.1
    refine ⟨?_, fun ho => ?_, ?_⟩
    · unfold killAll; rw [hnoM hl0.1 hl0.2]; exact hlE
    · rw [hkM.2.2.1, hkd.2.2.1]; exact hp (by rw [← hkM.2.1]; exact ho)
    · rw [hkM.2.2.2, hkd.2.2.2]; exact hh

/-- Running more closures, each either among those run on the weaker side or
    ending nothing there, keeps a context as strong. -/
theorem PW.killNames' {X Y : Ctx} (hp : PW X Y) {M ds : List Dep}
    (hds : ∀ d ∈ ds, d ∈ M ∨ ∀ v E, X v = some E → E.fixed → E.live = true →
      hits d.kind.bound false d.root E = false)
    (hM : ∀ d ∈ M, d ∈ ds ∨ ∀ v E, Y v = some E → E.live = true → hits d.kind.bound false d.root E = false) :
    PW (A2.killNames M X) (A2.killNames ds Y) := by
  intro v
  rw [killNames_eq, killNames_eq]
  refine ⟨by simp only [Option.map_eq_none_iff]; exact (hp v).1, fun E E' h1 h2 => ?_⟩
  cases hX : X v with
  | none => rw [hX] at h1; cases h1
  | some E0 =>
    cases hY : Y v with
    | none => rw [hY] at h2; cases h2
    | some E0' =>
      rw [hX] at h1; rw [hY] at h2
      simp only [Option.map_some, Option.some.injEq] at h1 h2; subst h1 h2
      exact killAll_weaker ((hp v).2 E0 E0' hX hY)
        (fun d hd => (hds d hd).imp id (fun hq hf hl => hq v E0 hX hf hl))
        (fun d hd => (hM d hd).imp id (fun hq hl => hq v E0' hY hl))

theorem heldOfArgs_lift (h : S.OK) (hab : S.AbsOK Γa) {args : List Var}
    (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) :
    heldOfArgs (S.canon Γa) (args.map S.ρ) ⊆ rds S.ρ (heldOfArgs Γa args) ++ S.A := by
  intro d hd
  unfold heldOfArgs at hd ⊢
  rcases List.mem_append.mp hd with hd | hd
  · rw [mem_allKinds_iff] at hd
    obtain ⟨hd, hdk⟩ := hd
    simp only [List.flatMap_map, List.mem_flatMap] at hd
    obtain ⟨a, ha, hda⟩ := hd
    obtain ⟨Ea, hEa⟩ := hargs a ha
    rw [argE_canon h hEa, liftE_ty' h hab hEa] at hda
    have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    split at hda
    · simp at hda
    · rename_i hn
      obtain ⟨d1, hd1, hdr⟩ := List.mem_map.mp hda
      have hd1' := List.mem_filter.mp hd1
      rcases List.mem_append.mp (held_lift h hab hEa hd1'.1) with h1 | h1
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
        refine List.mem_append_left _ (mem_rds.mpr ⟨⟨d0.root, d.kind⟩, List.mem_append_left _ ?_, ?_⟩)
        · rw [mem_allKinds_iff]
          simp only [List.mem_flatMap]
          exact ⟨⟨a, ha, by
            rw [hae, ite_eq_right hn]; exact List.mem_map_of_mem (List.mem_filter.mpr ⟨hd0, hd1'.2⟩)⟩, hdk⟩
        · obtain ⟨r, k⟩ := d; simp only [Dep.ren] at hdr ⊢; rw [← hdr]
      · rcases mem_A.mp h1 with h1 | h1
        · exact List.mem_append_right _
            (mem_A.mpr (Or.inl (mem_allKinds_iff.mpr ⟨hdr ▸ mem_allKinds h1, hdk⟩)))
        · have := h.N_name d1 h1
          simp [this] at hd1'
  · simp only [argNames, List.flatMap_map, List.mem_flatMap] at hd
    obtain ⟨a, ha, hda⟩ := hd
    obtain ⟨Ea, hEa⟩ := hargs a ha
    rw [argE_canon h hEa, liftE_ty' h hab hEa] at hda
    have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    split at hda
    · simp at hda
    · rename_i hn
      have hd' := List.mem_filter.mp hda
      rcases names_liftE h hab hEa hd'.1 hd'.2 with ⟨d0, hd0, rfl⟩ | hN
      · refine List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_append_right _ ?_, rfl⟩)
        simp only [argNames, List.mem_flatMap]
        exact ⟨a, ha, by rw [hae, ite_eq_right hn]; exact List.mem_filter.mpr ⟨hd0, hd'.2⟩⟩
      · exact List.mem_append_right _ (mem_A.mpr (Or.inr hN))


theorem AbsOK.killNames {Γ : Ctx} (hab : S.AbsOK Γ) : ∀ ds, S.AbsOK (A2.killNames ds Γ)
  | [] => hab
  | _ :: ds => show S.AbsOK (A2.kill _ _ _ (A2.killNames ds Γ)) from (AbsOK.killNames hab ds).kill _ _ _

theorem canon_killNames (h : S.OK) {Γ : Ctx} (hab : S.AbsOK Γ) :
    ∀ (ds : List Dep), (∀ d ∈ ds, Allowed S d.kind.bound false d.root) →
      S.canon (A2.killNames ds Γ) = A2.killNames (rds S.ρ ds) (S.canon Γ)
  | [], _ => rfl
  | d :: ds, hal => by
    show S.canon (A2.kill _ _ _ (A2.killNames ds Γ)) = A2.kill _ _ _ (A2.killNames (rds S.ρ ds) (S.canon Γ))
    rw [canon_kill h (hab.killNames ds) (hal d (by simp)),
      canon_killNames h hab ds (fun d' hd' => hal d' (by simp [hd']))]
    rfl

theorem PW.killNames {Γ Γ' : Ctx} (hp : PW Γ Γ') : ∀ ds, PW (A2.killNames ds Γ) (A2.killNames ds Γ')
  | [] => hp
  | _ :: ds => show PW (A2.kill _ _ _ (A2.killNames ds Γ)) (A2.kill _ _ _ (A2.killNames ds Γ')) from
      (PW.killNames hp ds).kill _ _ _

/-- What a closure handed to a call may change is changed by the call, where
    the call places it. -/
theorem namesFree_lift (h : S.OK) (hab : S.AbsOK Γa) {Fa : List Var} {ps : List (PMode × Ty)}
    {args : List Var} (hargs : ∀ a ∈ args, ∃ Ea, Γa a = some Ea) (hnf : NamesFree Γa Fa ps args) :
    NamesFree (S.canon Γa) S.Fc ps (args.map S.ρ) := by
  intro d hd
  rcases mem_mutNames_canon h hab hargs hd with hd | ⟨hN, hb⟩
  case inr =>
    -- what the arguments' closures may change
    obtain ⟨hFc, hR, ⟨Er, hEr, hcan, s, hts, hsv⟩, hpe, hN', _⟩ := h.N_mut d hN hb
    have hout := (h.N_out d hN).1
    have hae : argE (S.canon Γa) d.root = Er := by unfold argE; rw [canon_frame _ hout, hEr]; rfl
    refine ⟨by rw [hae]; exact hcan, ⟨s, by rw [hae]; exact hts, hsv⟩, hFc, Or.inl fun hm => ?_,
      fun a' ha' _ d' hd' hr' => ?_⟩
    · obtain ⟨a, _, he⟩ := List.mem_map.mp hm; exact hout a he
    · obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
      obtain ⟨Ea, hEa⟩ := hargs a ha
      rw [argE_canon h hEa] at hd'
      by_cases hrb : Ea.mode = .rootb
      · have hvd : (S.liftE a Ea).vdeps = (S.pe a).vdeps := by simp [liftE, hrb, Entry.vdeps]
        rw [hvd] at hd'; exact hpe a d' hd' hr'
      · rcases liftE_vdeps_cases hrb hd' with ⟨d1, _, rfl⟩ | ha2
        · exact absurd hr' (hout d1.root)
        · rcases mem_A.mp ha2 with ha2 | ha2
          · exact absurd (hr' ▸ mem_allKinds ha2) hR
          · exact hN' d' ha2 hr'
  obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp hd
  obtain ⟨hcan, ⟨s, hts, hsv⟩, hF, hna, hoth⟩ := hnf d0 hd0
  have hex : ∃ E0, Γa d0.root = some E0 := by
    cases hE : Γa d0.root with
    | some E0 => exact ⟨E0, rfl⟩
    | none =>
      exfalso; unfold argE at hcan; rw [hE] at hcan
      rcases hcan with hm | ⟨b, hm, _⟩ <;> simp [intE] at hm
  obtain ⟨E0, hE0⟩ := hex
  have hae0 : argE Γa d0.root = E0 := by unfold argE; rw [hE0]; rfl
  rw [hae0] at hcan hts
  have hrb0 : E0.mode ≠ .rootb := fun e => by rw [e] at hcan; rcases hcan with hm | ⟨b, hm, _⟩ <;> cases hm
  refine ⟨?_, ⟨s, ?_, hsv⟩, h.Fcout _, ?_, fun a' ha' hn' d' hd' hr' => ?_⟩
  · show canDo (argE (S.canon Γa) (S.ρ d0.root)).mode d0.kind.bound
    rw [argE_canon h hE0, liftE_mode _ hrb0]; exact canDo_lift hcan
  · show (argE (S.canon Γa) (S.ρ d0.root)).ty = _
    rw [argE_canon h hE0, liftE_ty _ hrb0]; exact hts
  · rcases hna with hna | ⟨i, t, hai, hpi⟩
    · refine Or.inl fun hm => ?_
      obtain ⟨a, ha, he⟩ := List.mem_map.mp hm
      exact hna (h.inj _ _ he ▸ ha)
    · exact Or.inr ⟨i, t, by rw [List.getElem?_map, hai]; rfl, hpi⟩
  · obtain ⟨a, ha, rfl⟩ := List.mem_map.mp ha'
    obtain ⟨Ea, hEa⟩ := hargs a ha
    rw [argE_canon h hEa] at hn' hd'
    have hae : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    have hn1 : Ea.ty ≠ .int ∨ Ea.mode = .rootb := by
      rcases hn' with h' | h'
      · rw [liftE_ty' h hab hEa] at h'; exact Or.inl h'
      · rw [liftE_rootb h] at h'; exact Or.inr h'
    by_cases hrb : Ea.mode = .rootb
    · have hvd : (S.liftE a Ea).vdeps = (S.pe a).vdeps := by simp [liftE, hrb, Entry.vdeps]
      rw [hvd] at hd'
      -- a symbolic name's image: the abstract parameter holds the symbolic name
      obtain ⟨b, t, rfl, hb, hpt, hbn, hbr, hf⟩ := pe_ρ h hd' hr'
      exact hoth a ha (by rw [hae]; exact hn1) ⟨d0.root, .name b t⟩
        (by rw [hae]; exact abs_sym hab hEa hrb hf (h.sym_of _ b t hb hpt hbn hbr)) rfl
    · rcases liftE_vdeps_cases hrb hd' with ⟨d1, hd1, rfl⟩ | hak
      · exact hoth a ha (by rw [hae]; exact hn1) d1 (by rw [hae]; exact hd1) (h.inj _ _ hr')
      · exact absurd hr' ((A_out h hak) d0.root ∘ Eq.symm)

/-- What a call through a package returns, where a call places it. -/
theorem recvRes_lift (h : S.OK) (hab : S.AbsOK Γa) {c : Var} {Ec E E' : Entry} (hc : Γa c = some Ec)
    (hmo : E.mode = .own ∨ E.mode = .bor) (x : Var) (hw : EntryWeaker E' (S.liftE x E)) :
    EntryWeaker (recvRes (S.ρ c) (S.liftE c Ec) E') (S.liftE x (recvRes c Ec E)) := by
  have hrb : E.mode ≠ .rootb := by rcases hmo with h' | h' <;> rw [h'] <;> simp
  -- the receiver's roots, lifted
  have hA : allKinds (recvRoots (S.ρ c) (S.liftE c Ec)) ⊆
      rds S.ρ (allKinds (recvRoots c Ec)) ++ S.A := by
    intro d hd
    have hr := allKinds_root hd
    have hdk := (mem_allKinds_iff.mp hd).2
    have key : ∀ r0 ∈ recvRoots c Ec, d.root = S.ρ r0 →
        d ∈ rds S.ρ (allKinds (recvRoots c Ec)) ++ S.A := by
      intro r0 hr0 he
      refine List.mem_append_left _ (mem_rds.mpr ⟨⟨r0, d.kind⟩, mem_allKinds_iff.mpr ⟨hr0, hdk⟩, ?_⟩)
      obtain ⟨r, k⟩ := d; simp only [Dep.ren] at he ⊢; rw [he]
    unfold recvRoots at hr
    rcases List.mem_append.mp hr with hr | hr
    · obtain ⟨d1, hd1, he⟩ := List.mem_map.mp hr
      have hd1' := List.mem_filter.mp hd1
      rcases List.mem_append.mp (derive_lift h hab hc .self rfl hd1'.1) with h1 | h1
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
        exact key d0.root (List.mem_append_left _ (List.mem_map_of_mem
          (List.mem_filter.mpr ⟨hd0, hd1'.2⟩))) he.symm
      · exact List.mem_append_right _ (mem_A.mpr (Or.inl
          (mem_allKinds_iff.mpr ⟨he ▸ mem_allKinds (A_mem h h1 hd1'.2), hdk⟩)))
    · obtain ⟨d1, hd1, he⟩ := List.mem_map.mp hr
      have hd1' := List.mem_filter.mp hd1
      rcases List.mem_append.mp (held_lift h hab hc hd1'.1) with h1 | h1
      · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
        exact key d0.root (List.mem_append_right _ (List.mem_map_of_mem
          (List.mem_filter.mpr ⟨hd0, hd1'.2⟩))) he.symm
      · exact List.mem_append_right _ (mem_A.mpr (Or.inl
          (mem_allKinds_iff.mpr ⟨he ▸ mem_allKinds (A_mem h h1 hd1'.2), hdk⟩)))
  obtain ⟨ht, hm, _, hl⟩ := hw
  have hty : (S.liftE x E).ty = E.ty := liftE_ty x hrb
  have hmd : (S.liftE x E).mode = liftMode E.mode := liftE_mode x hrb
  have hos : (liftMode E.mode).ownSlot = E.mode.ownSlot := liftMode_ownSlot _
  have hpath : (S.liftE x E).path = rds S.ρ E.path ++ (if E.mode.ownSlot then [] else S.A) := by
    simp only [liftE, hrb, ↓reduceIte]
  have hheld : (S.liftE x E).held = rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A := liftE_held hrb
  have hrrb : (recvRes c Ec E).mode ≠ .rootb := hrb
  have hpath2 : (S.liftE x (recvRes c Ec E)).path =
      rds S.ρ (E.path ++ allKinds (recvRoots c Ec)) ++ (if E.mode.ownSlot then [] else S.A) := by
    unfold liftE; simp only [hrrb, ↓reduceIte]; rfl
  have hheld2 : (S.liftE x (recvRes c Ec E)).held =
      rds S.ρ (ownHeld E.mode.ownSlot E.ty (E.held ++ allKinds (recvRoots c Ec))) ++
        ownHeld E.mode.ownSlot E.ty S.A := by
    simp [liftE, recvRes, hrb]
  refine ⟨?_, ?_, fun h' => ?_, fun hl' => ?_⟩
  · show (S.liftE x (recvRes c Ec E)).ty = E'.ty
    rw [← ht, hty]; simp [liftE, recvRes, hrb]
  · show (S.liftE x (recvRes c Ec E)).mode = E'.mode
    rw [← hm, hmd]; simp [liftE, recvRes, hrb]
  · exfalso
    change E'.mode = .rootb ∨ ∃ b, E'.mode = .inout b ∧ b ≠ .replace ∧ E'.ty.holdsView = false at h'
    rw [← hm, hmd] at h'
    rcases h' with h' | ⟨b, h', _⟩
    · exact hrb (liftMode_rootb.mp h')
    · cases hq : E.mode <;> rw [hq] at h' <;> simp [liftMode] at h'
  · have hlE : (S.liftE x E).live = true := by
      have : (S.liftE x (recvRes c Ec E)).live = E.live := by simp [liftE, recvRes, hrb]
      rw [liftE_live]; rw [this] at hl'; exact hl'
    obtain ⟨hl1, hp1, hh1⟩ := hl hlE
    refine ⟨hl1, fun hos' => ?_, ?_⟩
    · change E'.mode.ownSlot = false at hos'
      have hosE : E.mode.ownSlot = false := by rw [← hm, hmd, hos] at hos'; exact hos'
      have hp := hp1 hos'
      rw [hpath, hosE] at hp
      rw [hpath2, hosE]
      simp only [Bool.false_eq_true, ↓reduceIte, rds, List.map_append] at hp ⊢
      intro d hd
      rcases List.mem_append.mp hd with hd | hd
      · rcases List.mem_append.mp (hp hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_left _ h1)
        · exact List.mem_append_right _ h1
      · rcases List.mem_append.mp (hA hd) with h1 | h1
        · exact List.mem_append_left _ (List.mem_append_right _ h1)
        · exact List.mem_append_right _ h1
    · have hE'os : E'.mode.ownSlot = E.mode.ownSlot := by rw [← hm, hmd, hos]
      have hE'ty : E'.ty = E.ty := by rw [← ht, hty]
      show ownHeld E'.mode.ownSlot E'.ty (E'.held ++ _) ⊆ (S.liftE x (recvRes c Ec E)).held
      rw [hE'os, hE'ty, hheld2]
      rw [hheld] at hh1
      by_cases hc0 : (E.mode.ownSlot && !E.ty.holdsView) = true
      · simp only [ownHeld, hc0, ↓reduceIte]; intro d hd; cases hd
      · simp only [ownHeld, hc0, Bool.false_eq_true, ↓reduceIte] at hh1 ⊢
        simp only [rds, List.map_append] at hh1 ⊢
        intro d hd
        rcases List.mem_append.mp hd with hd | hd
        · rcases List.mem_append.mp (hh1 hd) with h1 | h1
          · exact List.mem_append_left _ (List.mem_append_left _ h1)
          · exact List.mem_append_right _ h1
        · rcases List.mem_append.mp (hA hd) with h1 | h1
          · exact List.mem_append_left _ (List.mem_append_right _ h1)
          · exact List.mem_append_right _ h1

theorem flatMap_lift {l : List (Nat × Kind)} {fc fa : Nat × Kind → List Dep}
    (hf : ∀ jk ∈ l, fc jk ⊆ rds S.ρ (fa jk) ++ S.A) :
    l.flatMap fc ⊆ rds S.ρ (l.flatMap fa) ++ S.A := by
  intro d hd
  obtain ⟨jk, hjk, hd'⟩ := List.mem_flatMap.mp hd
  rcases List.mem_append.mp (hf jk hjk hd') with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_flatMap.mpr ⟨jk, hjk, hd0⟩, rfl⟩)
  · exact List.mem_append_right _ h1

theorem outHeld_lift (h : S.OK) (hab : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (houts : ∀ o ∈ fn.outHolds, o.2.1 < args.length ∧ o.2.2.isName = false)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (i : Nat) :
    outHeld (S.canon Γa) fn (args.map S.ρ) i ⊆ rds S.ρ (outHeld Γa fn args i) ++ S.A := by
  intro d hd
  unfold outHeld at hd ⊢
  obtain ⟨o, ho, hd'⟩ := List.mem_flatMap.mp hd
  have hom := (List.mem_filter.mp ho).1
  obtain ⟨Ea, hEa⟩ := hargs o.2.1 (houts o hom).1
  rcases List.mem_append.mp (argDeps_lift h hab (houts o hom).1 hEa o.2.2 (houts o hom).2 hd') with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact List.mem_append_left _ (mem_rds.mpr ⟨d0, List.mem_flatMap.mpr ⟨o, ho, hd0⟩, rfl⟩)
  · exact List.mem_append_right _ h1

theorem resMode_ne (fn : Fn) : resMode fn ≠ .rootb := by unfold resMode; split <;> simp
theorem resMode_notInout (fn : Fn) (b : Eff) : resMode fn ≠ .inout b := by unfold resMode; split <;> simp

/-- A call's result is never fixed. -/
theorem callRes_not_fixed (Γ : Ctx) (fn : Fn) (args : List Var) : ¬ (callRes Γ fn args).fixed := by
  simp only [Entry.fixed_def, callRes]
  rintro (h | ⟨b, h, _⟩)
  · exact resMode_ne fn h
  · exact resMode_notInout fn b h
theorem liftMode_resMode (fn : Fn) : liftMode (resMode fn) = resMode fn := by unfold resMode; split <;> rfl

theorem resMode_ownSlot (fn : Fn) : (resMode fn).ownSlot = fn.resOwn := by
  unfold resMode; cases fn.resOwn <;> rfl

theorem liftE_callRes (Γ : Ctx) (fn : Fn) (args : List Var) (x : Var) :
    S.liftE x (callRes Γ fn args) =
      ⟨fn.resTy, resMode fn, true,
       rds S.ρ (fn.lends.flatMap (argDeps Γ args) ++ heldOfArgs Γ args) ++
         (if (resMode fn).ownSlot then [] else S.A),
       rds S.ρ (ownHeld fn.resOwn fn.resTy (fn.rholds.flatMap (argDeps Γ args) ++ heldOfArgs Γ args)) ++
         ownHeld fn.resOwn fn.resTy S.A, false⟩ := by
  simp only [liftE, callRes, resMode_ne fn, ↓reduceIte, liftMode_resMode, resMode_ownSlot]

theorem callRes_lift (h : S.OK) (hab : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (hl : ∀ jk ∈ fn.lends ++ fn.rholds, jk.1 < args.length ∧ jk.2.isName = false)
    (hargs : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea) (x : Var) :
    EntryWeaker (callRes (S.canon Γa) fn (args.map S.ρ)) (S.liftE x (callRes Γa fn args)) := by
  have hall : ∀ a ∈ args, ∃ Ea, Γa a = some Ea := by
    intro a ha; obtain ⟨i, hi, rfl⟩ := mem_args ha; exact hargs i hi
  have hA : ∀ jk ∈ fn.lends ++ fn.rholds, argDeps (S.canon Γa) (args.map S.ρ) jk ⊆
      rds S.ρ (argDeps Γa args jk) ++ S.A := by
    intro jk hjk
    obtain ⟨Ea, hEa⟩ := hargs jk.1 (hl jk hjk).1
    exact argDeps_lift h hab (hl jk hjk).1 hEa jk.2 (hl jk hjk).2
  have hH := heldOfArgs_lift h hab hall
  rw [liftE_callRes]
  refine EntryWeaker.mk' rfl rfl (callRes_not_fixed _ _ _) rfl (fun _ => ?_) ?_
  · rename_i ho
    simp only [callRes] at ho
    simp only [ho, Bool.false_eq_true, ↓reduceIte]
    exact app_lift (S := S) (flatMap_lift (S := S) (fun jk hjk => hA jk (List.mem_append_left _ hjk))) hH
  · show ownHeld fn.resOwn fn.resTy _ ⊆ _
    by_cases hc0 : (fn.resOwn && !fn.resTy.holdsView) = true
    · simp only [ownHeld, hc0, ↓reduceIte]; intro d hd; cases hd
    · simp only [ownHeld, hc0, Bool.false_eq_true, ↓reduceIte]
      exact app_lift (S := S) (flatMap_lift (S := S) (fun jk hjk => hA jk (List.mem_append_right _ hjk))) hH

theorem callPostAux_lift (h : S.OK) (hab0 : S.AbsOK Γa) {fn : Fn} {args : List Var}
    (houts : ∀ o ∈ fn.outHolds, o.2.1 < args.length ∧ o.2.2.isName = false)
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
          (fun bh hb => ?_) (fun _ _ hf => absurd hf (by simp [hae0, hm]))
        · simp [hae0, hm] at hb
        · obtain ⟨E, hE, hmE, _⟩ := hab0.2.2 a bh hb
          rw [hEa] at hE; cases hE; rw [hm] at hmE; cases hmE
        · obtain ⟨E, hE, hmE, _⟩ := hab0.2.2 a bh hb
          rw [hEa] at hE; cases hE; rw [hm] at hmE; cases hmE
      · rw [canon_setE h, canon_kill h hab (allowed_own hab0 hEa hm _ _), hae, hae0, liftE_moved _ hrb]
        exact PW.setE (hpw.kill _ _ _) (EntryWeaker.refl _)
    | inout b =>
      obtain ⟨ht, hcan, _⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
      simp only [callPostAux, List.map_cons]
      apply callPostAux_lift h hab0 houts hargs ps as (i + 1) _ _ hz'
      · refine (hab.kill _ _ _).setE (by simp [hae0, hrb]) (fun b' hb => ?_) (fun bh hb => ?_)
          (fun bh hb => ?_) (fun _ _ hf => ?_)
        · simp only [hae0] at hb ⊢
          exact hab0.2.1 a Ea b' hEa hb
        · obtain ⟨E, hE, hmE, _⟩ := hab0.2.2 a bh hb
          rw [hEa] at hE; cases hE; simp only [hae0]; exact hmE
        · obtain ⟨E, hE, _, htE, _⟩ := hab0.2.2 a bh hb
          rw [hEa] at hE; cases hE; simp only [hae0]; exact htE
        · -- a fixed `inout` argument holds nothing, and still holds nothing
          simp only [hae0] at hf
          have hf0 : Ea.fixed := hf
          obtain ⟨hl0, hh0⟩ := hab0.fixed hEa hf0 hrb
          have hv0 : Ea.ty.holdsView = false := by
            rcases hf0 with h' | ⟨_, _, _, h'⟩
            · exact absurd h' hrb
            · exact h'
          have hsv : t.holdsView = false := by
            have h' := hv0; rw [ht] at h'; exact h'
          simp only [hae0, hsv]; exact ⟨hl0, by simp [hh0]⟩
      · have hal := allowed_canDo' hab0 hEa hcan
        rw [ht] at hal
        rw [canon_setE h, canon_kill h hab hal, hae, hae0]
        refine PW.setE (hpw.kill _ _ _) ?_
        refine EntryWeaker.mk' ?_ ?_ ?_ ?_ ?_ ?_
        · simp [liftE, hrb]
        · simp [liftE, hrb]
        · intro hf
          exact liftE_not_fixed (S := S) (v := a) hrb (by simpa using hf)
        · simp [liftE, hrb]
        · intro ho; simp [liftE, hrb]
        · simp only [liftE, hrb, ↓reduceIte]
          by_cases hv : t.holdsView = true
          · simp only [hv, ↓reduceIte]
            have hoA : ownHeld Ea.mode.ownSlot Ea.ty S.A = S.A := by
              rw [ht]; simp [ownHeld, hv]
            rw [hoA]
            have h1 := outHeld_lift h hab0 houts hargs i
            have h2 := heldOfArgs_lift h hab0 (fun a ha => by
              obtain ⟨j, hj, rfl⟩ := mem_args ha; exact hargs j hj)
            exact app_lift (S := S) (app_lift (S := S) (List.Subset.refl _) h1) h2
          · simp only [hv, Bool.false_eq_true, ↓reduceIte]
            exact List.Subset.refl _

theorem mem_zip_getD {ps : List (PMode × Ty)} {as : List Var} {pa : (PMode × Ty) × Var}
    (h : pa ∈ ps.zip as) : ∃ k, ∃ hk : k < ps.length, k < as.length ∧ pa = (ps[k], as.getD k 0) := by
  obtain ⟨k, hk, he⟩ := List.getElem_of_mem h
  have hk1 : k < ps.length := by simp at hk; omega
  have hk2 : k < as.length := by simp at hk; omega
  refine ⟨k, hk1, hk2, ?_⟩
  rw [← he]; simp [List.getD, hk2]

theorem roots_liftE_ρ (h : S.OK) (hab : S.AbsOK Γa) {v a : Var} {E : Entry} (hE : Γa v = some E)
    (hn : a ∉ roots E.vdeps) : S.ρ a ∉ roots (S.liftE v E).vdeps := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  by_cases hrb : E.mode = .rootb
  · have hvd : (S.liftE v E).vdeps = (S.pe v).vdeps := by simp [liftE, hrb, Entry.vdeps]
    rw [hvd] at hd
    obtain ⟨b, t, rfl, hb, hpt, hbn, hbr, hf⟩ := pe_ρ h hd hdr
    exact hn (List.mem_map.mpr ⟨⟨a, .name b t⟩, abs_sym hab hE hrb hf (h.sym_of a b t hb hpt hbn hbr), rfl⟩)
  · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
    · apply hn
      have : d0.root = a := h.inj _ _ hdr
      exact this ▸ List.mem_map_of_mem hd0
    · exact A_out h ha a hdr.symm

/-- ... and in memory: a symbolic name is a name. -/
theorem roots_liftE_ρ_mem (h : S.OK) {v a : Var} {E : Entry}
    (hn : a ∉ roots (memDeps E.vdeps)) : S.ρ a ∉ roots (memDeps (S.liftE v E).vdeps) := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  obtain ⟨hd, hdn⟩ := List.mem_filter.mp hd
  by_cases hrb : E.mode = .rootb
  · have hvd : (S.liftE v E).vdeps = (S.pe v).vdeps := by simp [liftE, hrb, Entry.vdeps]
    rw [hvd] at hd
    obtain ⟨b, t, rfl, _⟩ := pe_ρ h hd hdr
    simp [Kind.isName] at hdn
  · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
    · apply hn
      have : d0.root = a := h.inj _ _ hdr
      exact this ▸ List.mem_map_of_mem (List.mem_filter.mpr ⟨hd0, hdn⟩)
    · exact A_out h ha a hdr.symm

/-- The context after a call's parameters are handed back is made of the
    entries before, of the same mode, and (for a borrowed one) of the same
    dependencies: only the arguments moved or changed, none of them borrowed,
    are rebound. -/
theorem callPostAux_entry {Γ0 : Ctx} {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, pa.1.1.moves = true → ∃ E0, Γ0 pa.2 = some E0 ∧ E0.mode ≠ .rootb) →
      (∀ v E1, Γ v = some E1 → ∃ E0, Γ0 v = some E0 ∧ E1.mode = E0.mode ∧
        (E0.mode = .rootb → E1.vdeps = E0.vdeps)) →
      ∀ v E, callPostAux Γ0 fn args ps as i Γ v = some E →
        ∃ E0, Γ0 v = some E0 ∧ E.mode = E0.mode ∧ (E0.mode = .rootb → E.vdeps = E0.vdeps) := by
  intro ps
  induction ps with
  | nil => intro as i Γ _ hI v E hv; cases as <;> exact hI v E hv
  | cons q ps ih =>
    intro as i Γ hz hI v E hv
    obtain ⟨pm, t⟩ := q
    cases as with
    | nil => cases pm <;> exact hI v E hv
    | cons a as =>
      have hz' : ∀ pa ∈ ps.zip as, pa.1.1.moves = true → ∃ E0, Γ0 pa.2 = some E0 ∧ E0.mode ≠ .rootb :=
        fun pa hpa => hz pa (by simp [hpa])
      -- killing keeps modes and dependencies
      have hIk : ∀ e hv, ∀ v E1, A2.kill e hv a Γ v = some E1 → ∃ E0, Γ0 v = some E0 ∧
          E1.mode = E0.mode ∧ (E0.mode = .rootb → E1.vdeps = E0.vdeps) := by
        intro e hv v E1 h1
        simp only [A2.kill] at h1
        obtain ⟨E2, h2, rfl⟩ := Option.map_eq_some_iff.mp h1
        obtain ⟨E0, h0, hm0, hvd⟩ := hI v E2 h2
        exact ⟨E0, h0, by rw [killE_mode, hm0], fun hr => by rw [killE_vdeps, hvd hr]⟩
      have hset : pm.moves = true → ∀ (E' : Entry) (hm : E'.mode = (argE Γ0 a).mode) (e hv),
          ∀ v E1, setE (A2.kill e hv a Γ) a E' v = some E1 → ∃ E0, Γ0 v = some E0 ∧
            E1.mode = E0.mode ∧ (E0.mode = .rootb → E1.vdeps = E0.vdeps) := by
        intro hpm E' hm e hv v E1 h1
        by_cases hva : v = a
        · subst hva
          simp only [A2.setE, upd_same, Option.some.injEq] at h1; subst h1
          obtain ⟨E0, h0, hrb⟩ := hz ((pm, t), v) (by simp) hpm
          have hae : argE Γ0 v = E0 := by unfold argE; rw [h0]; rfl
          exact ⟨E0, h0, by rw [hm, hae], fun hr => absurd hr hrb⟩
        · simp only [A2.setE, upd_ne _ _ hva] at h1; exact hIk _ _ v E1 h1
      cases pm with
      | inp => exact ih as (i + 1) Γ hz' hI v E hv
      | sink =>
        simp only [callPostAux] at hv
        exact ih as (i + 1) _ hz' (hset rfl _ (by rfl) _ _) v E hv
      | inout b =>
        simp only [callPostAux] at hv
        exact ih as (i + 1) _ hz' (hset rfl _ (by rfl) _ _) v E hv

/-- No entry of the caller's view is an `inout` one: the callee's `inout`
    parameters are the caller's own bindings. -/
theorem canon_noio (h : S.OK) {y : Var} {E : Entry} (hy : S.canon Γa y = some E) (b : Eff) :
    E.mode ≠ .inout b := by
  rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨_, hc⟩
  · rw [hc] at hy
    cases hE : Γa v with
    | none => rw [hE] at hy; cases hy
    | some E0 =>
      rw [hE] at hy; simp only [Option.map_some, Option.some.injEq] at hy; subst hy
      by_cases hrb : E0.mode = .rootb
      · simp only [liftE, hrb, ↓reduceIte]; rw [h.pe_rb]; simp
      · rw [liftE_mode v hrb]; cases E0.mode <;> simp [liftMode]
  · rw [hc] at hy; exact h.Φio y E b hy

/-- A symbolic name's change, where the call places it, ends nothing fixed
    after the call's parameters are handed back: a borrowed binding reaches
    the `inout` argument only by name, and the parameter is not replaced. -/
theorem sym_quiet (h : S.OK) (_hab : S.AbsOK Γa) {w : Var} {b : Eff}
    (hb : S.bnd w = some (b, false)) (hbr : b ≠ .replace) {fn : Fn} {args : List Var}
    (hz : ∀ pa ∈ fn.params.zip (args.map S.ρ), pa.1.1.moves = true →
      ∃ E0, S.canon Γa pa.2 = some E0 ∧ E0.mode ≠ .rootb) :
    ∀ v E, callPostAux (S.canon Γa) fn (args.map S.ρ) fn.params (args.map S.ρ) 0 (S.canon Γa) v = some E →
      E.fixed → E.live = true → hits b false (S.ρ w) E = false := by
  intro v E hv hf _
  obtain ⟨E0, h0, hm, hvd⟩ := callPostAux_entry fn.params (args.map S.ρ) 0 (S.canon Γa) hz
    (fun v E1 h1 => ⟨E1, h1, rfl, fun _ => rfl⟩) v E hv
  have hrb : E0.mode = .rootb := by
    rcases hf with hf | ⟨b', hm', _⟩
    · rw [← hm]; exact hf
    · exact absurd (hm ▸ hm') (canon_noio h h0 b')
  refine hits_false_of fun d hd hdr => ?_
  rw [hvd hrb] at hd
  rcases canon_cases h Γa v with ⟨v', rfl, hc⟩ | ⟨_, hc⟩
  · rw [hc] at h0
    cases hE : Γa v' with
    | none => rw [hE] at h0; cases h0
    | some E1 =>
      rw [hE] at h0; simp only [Option.map_some, Option.some.injEq] at h0; subst h0
      have hrb1 : E1.mode = .rootb := (liftE_rootb h).mp hrb
      have hvd1 : (S.liftE v' E1).vdeps = (S.pe v').vdeps := by simp [liftE, hrb1, Entry.vdeps]
      rw [hvd1] at hd
      obtain ⟨b', t, rfl, hb', _, _, _, _⟩ := pe_ρ h hd hdr
      rw [hb] at hb'; simp only [Option.some.injEq, Prod.mk.injEq] at hb'
      exact kills_isName hbr false rfl
  · rw [hc] at h0
    obtain ⟨b', hv', hb', hk⟩ := h.Φsat v E0 h0 (h.Φrb v E0 h0 hrb) (Or.inr hrb) d hd w hdr.symm
    rw [hb] at hb'; simp only [Option.some.injEq, Prod.mk.injEq] at hb'
    obtain ⟨rfl, rfl⟩ := hb'
    exact hk

theorem paramOK_lift (h : S.OK) (hab : S.AbsOK Γa) {v : Var} {E : Entry} (hE : Γa v = some E)
    {pm : PMode} {t : Ty} (hp : paramOK pm t E) : paramOK pm t (S.liftE v E) := by
  cases pm with
  | inp => show _ = _; rw [liftE_ty' h hab hE]; exact hp
  | sink =>
    obtain ⟨ht, hm, hs⟩ := hp
    have hrb : E.mode ≠ .rootb := by rw [hm]; simp
    exact ⟨by rw [liftE_ty v hrb]; exact ht, by rw [liftE_mode v hrb, hm]; rfl, hs⟩
  | inout b =>
    obtain ⟨ht, hcan, hs⟩ := hp
    have hrb : E.mode ≠ .rootb := by rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
    exact ⟨by rw [liftE_ty v hrb]; exact ht, by rw [liftE_mode v hrb]; exact canDo_lift hcan, hs⟩

theorem AbsOK.callPostAux {Γa : Ctx} (hab0 : S.AbsOK Γa) {fn : Fn} {args : List Var} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (i : Nat) (Γ : Ctx),
      (∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea) →
      S.AbsOK Γ → S.AbsOK (A2.callPostAux Γa fn args ps as i Γ)
  | [], _, _, _, _, hab => by simpa [A2.callPostAux] using hab
  | _ :: _, [], _, _, _, hab => by simpa [A2.callPostAux] using hab
  | (pm, t) :: ps, a :: as, i, Γ, hz, hab => by
    obtain ⟨Ea, hEa, hpo⟩ := hz ((pm, t), a) (by simp)
    have hz' : ∀ pa ∈ ps.zip as, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea :=
      fun pa hpa => hz pa (by simp [hpa])
    have hae0 : argE Γa a = Ea := by unfold argE; rw [hEa]; rfl
    cases pm with
    | inp => exact AbsOK.callPostAux hab0 ps as (i + 1) Γ hz' hab
    | sink =>
      obtain ⟨_, hm, _⟩ := hpo
      simp only [A2.callPostAux]
      exact AbsOK.callPostAux hab0 ps as (i + 1) _ hz'
        ((hab.kill _ _ _).setE' hab0 hEa (by simp [hae0]) (by simp [hae0]) (by simp [hae0, hm])
          (fun hf => absurd hf (by simp [hae0, hm])))
    | inout b =>
      obtain ⟨ht, hcan, _⟩ := hpo
      have hrb : Ea.mode ≠ .rootb := by
        rcases hcan with hm | ⟨b', hm, _⟩ <;> rw [hm] <;> simp
      simp only [A2.callPostAux]
      exact AbsOK.callPostAux hab0 ps as (i + 1) _ hz'
        ((hab.kill _ _ _).setE' hab0 hEa (by simp [hae0]) (by simp [hae0]) (by simp [hae0, hrb])
          (fun hf => by
            simp only [hae0] at hf ⊢
            have hf0 : Ea.fixed := hf
            obtain ⟨hl0, hh0⟩ := hab0.fixed hEa hf0 hrb
            have hv0 : t.holdsView = false := by
              rcases hf0 with h' | ⟨_, _, _, h'⟩
              · exact absurd h' hrb
              · rw [ht] at h'; exact h'
            simp [hv0, hl0, hh0]))

/-- A call in the callee's body, where the call places it. -/
theorem callT_ren (h : S.OK) (hab : S.AbsOK Γa) {P : Prog} (hP : ProgOK P) {Fa : List Var} {f : Nat}
    {args : List Var} {E : Entry} {Γa1 : Ctx} (hc : CallT P Γa Fa f args E Γa1) :
    ∃ E' Γ', CallT P (S.canon Γa) S.Fc f (args.map S.ρ) E' Γ' ∧ PW Γ' (S.canon Γa1) ∧
      ∀ x, EntryWeaker E' (S.liftE x E) := by
  obtain ⟨fn, hf, hlen, hargs, hnf, rfl, rfl⟩ := hc
  have hfn : FnOK P fn := hP fn (List.mem_of_getElem? hf)
  obtain ⟨_, _, _, _, _, _, hlends, hrholds, houts, _⟩ := hfn
  have hex : ∀ j < args.length, ∃ Ea, Γa (args.getD j 0) = some Ea := by
    intro j hj; obtain ⟨Ea, h1, _⟩ := hargs j (hlen ▸ hj); exact ⟨Ea, h1⟩
  have hexA : ∀ a ∈ args, ∃ Ea, Γa a = some Ea := by
    intro a ha; obtain ⟨j, hj, rfl⟩ := mem_args ha; exact hex j hj
  have hlr : ∀ jk ∈ fn.lends ++ fn.rholds, jk.1 < args.length ∧ jk.2.isName = false := by
    intro jk hjk
    rcases List.mem_append.mp hjk with hj | hj
    · obtain ⟨⟨hl, _⟩, hk⟩ := hlends jk hj; exact ⟨by omega, hk⟩
    · obtain ⟨⟨hl, _⟩, hk⟩ := hrholds jk hj; exact ⟨by omega, hk⟩
  have hou : ∀ o ∈ fn.outHolds, o.2.1 < args.length ∧ o.2.2.isName = false := by
    intro o ho; obtain ⟨⟨hl, _⟩, hk⟩ := houts o ho; exact ⟨by omega, hk⟩
  have hz : ∀ pa ∈ fn.params.zip args, ∃ Ea, Γa pa.2 = some Ea ∧ paramOK pa.1.1 pa.1.2 Ea := by
    intro pa hpa
    obtain ⟨k, hk, _, rfl⟩ := mem_zip_getD hpa
    obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
    exact ⟨Ea, hEa, hok⟩
  have hal : ∀ d ∈ mutNames Γa args, Allowed S d.kind.bound false d.root := by
    intro d hd
    obtain ⟨hcan, ⟨s, hts, hsv⟩, _⟩ := hnf d hd
    cases hE : Γa d.root with
    | none =>
      exfalso; unfold argE at hcan; rw [hE] at hcan
      rcases hcan with hm | ⟨b, hm, _⟩ <;> simp [intE] at hm
    | some E0 =>
      have hae : argE Γa d.root = E0 := by unfold argE; rw [hE]; rfl
      rw [hae] at hcan hts
      have := allowed_canDo hab hE hts hcan
      rwa [hsv] at this
  refine ⟨_, _, ⟨fn, hf, by simp [hlen], fun i hi => ?_, namesFree_lift h hab hexA hnf, rfl, rfl⟩, ?_,
    callRes_lift h hab hlr hex⟩
  · obtain ⟨Ea, hEa, hl, hok, hmv, _⟩ := hargs i hi
    have hia : i < args.length := hlen ▸ hi
    rw [getD_map hia]
    refine ⟨_, by rw [canon_ρ h, hEa]; rfl, by rw [liftE_live]; exact hl, paramOK_lift h hab hEa hok,
      fun hm => ?_, fun hpm => ?_⟩
    · obtain ⟨hF, hroot, hsk, hself, hoth⟩ := hmv hm
      refine ⟨h.Fcout _, roots_liftE_ρ_mem h hroot, fun hs => roots_liftE_ρ h hab hEa (hsk hs),
        fun b hb d hd hdr => ?_, fun j hj hji => ?_⟩
      · -- the argument's own names on itself: it is not borrowed
        have hrb : Ea.mode ≠ .rootb := by
          rw [hb] at hok; rcases hok.2.1 with hm' | ⟨_, hm', _⟩ <;> rw [hm'] <;> simp
        rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
        · exact hself b hb d0 hd0 (h.inj _ _ hdr)
        · exact absurd hdr.symm (A_out h ha _)
      have hja : j < args.length := hlen ▸ hj
      obtain ⟨hne, hnr, hns, hnb⟩ := hoth j hj hji
      obtain ⟨Ej, hEj⟩ := hex j hja
      rw [getD_map hja, argE_canon h hEj]
      have hae : argE Γa (args.getD j 0) = Ej := by unfold argE; rw [hEj]; rfl
      rw [hae] at hnr hns hnb
      refine ⟨fun e => hne (h.inj _ _ e), roots_liftE_ρ_mem h hnr,
        fun hs => roots_liftE_ρ h hab hEj (hns hs), fun b hb d hd hdr => ?_⟩
      -- an `inout` argument reached by name: by the parameter's bound, as
      -- the callee's symbolic name says (or as the callee's own closure does)
      by_cases hrb : Ej.mode = .rootb
      · have hvd : (S.liftE (args.getD j 0) Ej).vdeps = (S.pe (args.getD j 0)).vdeps := by
          simp [liftE, hrb, Entry.vdeps]
        rw [hvd] at hd
        obtain ⟨b', t, rfl, hb', hpt, hbn, hbr, hf⟩ := pe_ρ h hd hdr
        exact hnb b hb ⟨args.getD i 0, .name b' t⟩
          (abs_sym hab hEj hrb hf (h.sym_of _ b' t hb' hpt hbn hbr)) rfl
      · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
        · exact hnb b hb d0 hd0 (h.inj _ _ hdr)
        · exact absurd hdr.symm (A_out h ha _)
    · refine NoPin.lift h hab fun bh hb => ?_
      obtain ⟨E, hE, hmE, _⟩ := hab.2.2 _ bh hb
      rw [hEa] at hE; cases hE
      rcases hpm with hs | hs
      · rw [hs] at hok; obtain ⟨_, hmo, _⟩ := hok; rw [hmo] at hmE; cases hmE
      · rw [hs] at hok; obtain ⟨_, hcan, _⟩ := hok
        rcases hcan with hmo | ⟨b, hmo, hle⟩
        · rw [hmo] at hmE; cases hmE
        · rw [hmo] at hmE; cases hmE
          cases hb1 : bh.1 <;> rw [hb1] at hle <;> simp_all [Eff.le, Eff.rank]
  · unfold callPost
    rw [canon_killNames h (AbsOK.callPostAux hab fn.params args 0 Γa hz hab) _ hal]
    refine PW.killNames' (callPostAux_lift h hab hou hex fn.params args 0 Γa _ hz hab (PW.refl _))
      (fun d hd => ?_) (fun d hd => ?_)
    · rcases mutNames_canon_sub h hab hexA d hd with hd | ⟨w, b, t, rfl, hbw, hbr⟩
      · exact Or.inl hd
      · refine Or.inr (sym_quiet h hab hbw hbr fun pa hpa hm => ?_)
        obtain ⟨k, hk, hka, rfl⟩ := mem_zip_getD hpa
        have hka' : k < args.length := by simpa using hka
        obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
        simp only at hm ⊢
        rw [getD_map hka', canon_ρ h, hEa]
        refine ⟨_, rfl, ?_⟩
        revert hok hm; generalize fn.params[k] = q; obtain ⟨pm, t⟩ := q
        cases pm with
        | inp => intro hm; simp [PMode.moves] at hm
        | sink =>
          intro _ hok
          have hrb : Ea.mode ≠ .rootb := by rw [hok.2.1]; simp
          rw [liftE_mode _ hrb, hok.2.1]; simp [liftMode]
        | inout b' =>
          intro _ hok
          have hrb : Ea.mode ≠ .rootb := by
            rcases hok.2.1 with hm | ⟨_, hm, _⟩ <;> rw [hm] <;> simp
          rw [liftE_mode _ hrb]; cases hm' : Ea.mode <;> simp_all [liftMode]
    · rcases mem_mutNames_canon h hab hexA hd with hd | ⟨hN, hb⟩
      · exact Or.inl hd
      · exact Or.inr (canon_quiet h (AbsOK.callPostAux hab fn.params args 0 Γa hz hab) hN hb)

/-! ### The callee's contexts stay as the call set them up -/

theorem RhsT.absOK {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hr : RhsT Γ F r E Γ1)
    (hab : S.AbsOK Γ) : S.AbsOK Γ1 := by
  cases hr with
  | @moveOwn y Ey hy _ hm _ _ =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (fun hf => absurd hf (by simp [hm]))
  | pop => exact hab.kill _ _ _
  | pair hy _ hpa1 hz _ hpa2 _ => exact PushArg.absOK hz hpa2 (PushArg.absOK hy hpa1 hab)
  | inl hy _ hpa _ => exact PushArg.absOK hy hpa hab
  | inr hy _ hpa _ => exact PushArg.absOK hy hpa hab
  | pack hy _ _ hpa => exact PushArg.absOK hy hpa hab
  | @takel y Ey _ _ hy _ hm _ _ _ =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (fun hf => absurd hf (by simp [hm]))
  | @taker y Ey _ _ hy _ hm _ _ _ =>
    exact (hab.kill _ _ _).setE' hab hy rfl rfl (by rw [hm]; simp) (fun hf => absurd hf (by simp [hm]))
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
  | pair => exact ⟨Or.inl rfl, rfl⟩
  | @fst _ _ a => cases a <;> exact ⟨Or.inr rfl, rfl⟩
  | @snd _ _ _ b => cases b <;> exact ⟨Or.inr rfl, rfl⟩
  | inl => exact ⟨Or.inl rfl, rfl⟩
  | inr => exact ⟨Or.inl rfl, rfl⟩
  | pack => exact ⟨Or.inl rfl, rfl⟩
  | @getl _ _ a => cases a <;> exact ⟨Or.inr rfl, rfl⟩
  | @getr _ _ _ b => cases b <;> exact ⟨Or.inr rfl, rfl⟩
  | @takel _ _ a => cases a <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩
  | @taker _ _ _ b => cases b <;> first | exact ⟨Or.inl rfl, rfl⟩ | exact ⟨Or.inr rfl, rfl⟩

theorem CallT.absOK {P : Prog} {Γ Γ1 : Ctx} {F : List Var} {f : Nat} {args : List Var} {E : Entry}
    (hc : CallT P Γ F f args E Γ1) (hab : S.AbsOK Γ) : S.AbsOK Γ1 ∧ (E.mode = .own ∨ E.mode = .bor) ∧
      E.live = true := by
  obtain ⟨fn, _, _, hargs, _, rfl, rfl⟩ := hc
  refine ⟨(AbsOK.callPostAux hab fn.params args 0 Γ (fun pa hpa => ?_) hab).killNames _, ?_, rfl⟩
  · obtain ⟨k, hk, _, rfl⟩ := mem_zip_getD hpa
    obtain ⟨Ea, hEa, _, hok, _⟩ := hargs k hk
    exact ⟨Ea, hEa, hok⟩
  · simp only [callRes, resMode]; split <;> simp

theorem roots_sub {a b : List Dep} (h : a ⊆ b) : roots a ⊆ roots b := by
  intro r hr
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hr
  exact List.mem_map_of_mem (h hd)

theorem roots_lift_ρ (h : S.OK) {a : Var} {D : List Dep} {L : List Dep} (hD : D ⊆ rds S.ρ L ++ S.A)
    (hn : a ∉ roots L) : S.ρ a ∉ roots D := by
  intro hr
  obtain ⟨d, hd, hdr⟩ := List.mem_map.mp hr
  rcases List.mem_append.mp (hD hd) with h1 | h1
  · obtain ⟨d0, hd0, rfl⟩ := mem_rds.mp h1
    exact hn (h.inj _ _ hdr ▸ List.mem_map_of_mem hd0)
  · exact A_out h h1 a hdr.symm

theorem liftE_vdeps_sub {v : Var} {E : Entry} (hrb : E.mode ≠ .rootb) :
    (S.liftE v E).vdeps ⊆ rds S.ρ E.vdeps ++ S.A := by
  intro d hd
  rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
  · exact List.mem_append_left _ (mem_rds.mpr ⟨d0, hd0, rfl⟩)
  · exact List.mem_append_right _ ha

theorem allowed_replace (hab : S.AbsOK Γa) {x : Var} {Ex : Entry} (hx : Γa x = some Ex)
    (hm : Ex.mode = .own ∨ Ex.mode = .bor ∨ Ex.mode = .inout .replace) (hv : Bool) :
    Allowed S .replace hv x := by
  cases hb : S.bnd x with
  | none => exact Or.inl hb
  | some bh =>
    obtain ⟨E, hE, hmE, _⟩ := hab.2.2 x bh hb
    rw [hx] at hE; cases hE
    obtain ⟨b, hb'⟩ := bh
    refine Or.inr ⟨b, hb', hb, fun k _ => ?_⟩
    rcases hm with hm | hm | hm <;> rw [hm] at hmE <;> cases hmE
    cases k <;> rfl

theorem src_rename (ρ : Var → Var) (s : Stmt) : (s.rename ρ).src = s.src := by
  induction s <;> simp_all [Stmt.rename, Stmt.src]

/-- A context with the same bindings, modes and types, and the same
    borrowed parameters, as one the call set up. -/
theorem AbsOK.of_same {Γa Δa : Ctx} (hab : S.AbsOK Γa) (hdom : ∀ v, (Γa v).isSome = (Δa v).isSome)
    (hm : ∀ v E, Δa v = some E → ∃ E0, Γa v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) : S.AbsOK Δa := by
  refine ⟨fun v E hv hrb => ?_, fun v E b hv hio => ?_, fun v bh hb => ?_⟩
  · obtain ⟨E0, h0, hm0, _, he⟩ := hm v E hv
    rw [he (Or.inl (hm0 ▸ hrb))] at hrb ⊢
    exact hab.1 v E0 h0 hrb
  · obtain ⟨E0, h0, hm0, ht0, _⟩ := hm v E hv
    rw [ht0]; exact hab.2.1 v E0 b h0 (hm0 ▸ hio)
  · obtain ⟨E0, h0, hm0, ht0, hf0⟩ := hab.2.2 v bh hb
    have hs := hdom v; rw [h0] at hs
    obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hs.symm
    obtain ⟨E1, h1, hm1, ht1, he⟩ := hm v E hE
    rw [h0] at h1; cases h1
    refine ⟨E, hE, by rw [hm1, hm0], by rw [ht1, ht0], fun hf => ?_⟩
    have hf1 : E0.fixed := by simp only [Entry.fixed_def] at hf ⊢; rw [hm1, ht1] at hf; exact hf
    rw [he hf1]; exact hf0 hf1

theorem canon_same (h : S.OK) {Γa Δa : Ctx} (hab : S.AbsOK Γa)
    (hdom : ∀ v, (Γa v).isSome = (Δa v).isSome)
    (hm : ∀ v E, Δa v = some E → ∃ E0, Γa v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) :
    (∀ y, (S.canon Γa y).isSome = (S.canon Δa y).isSome) ∧
    (∀ y E, S.canon Δa y = some E → ∃ E0, S.canon Γa y = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) := by
  have habΔ := hab.of_same hdom hm
  refine ⟨fun y => ?_, fun y E hy => ?_⟩
  · rcases canon_cases h Γa y with ⟨v, rfl, hc⟩ | ⟨hyf, hc⟩
    · rw [hc, canon_ρ h]; have := hdom v; cases h1 : Γa v <;> cases h2 : Δa v <;> simp_all
    · rw [hc, canon_frame Δa hyf]
  · rcases canon_cases h Δa y with ⟨v, rfl, hc⟩ | ⟨hyf, hc⟩
    · rw [hc] at hy
      obtain ⟨E1, h1, rfl⟩ := Option.map_eq_some_iff.mp hy
      obtain ⟨E0, h0, hm0, ht0, hrb⟩ := hm v E1 h1
      refine ⟨S.liftE v E0, by rw [canon_ρ h, h0]; rfl, ?_, ?_, fun hr => ?_⟩
      · by_cases hrb0 : E0.mode = .rootb
        · rw [hrb (Or.inl hrb0)]
        · have hrb1 : E1.mode ≠ .rootb := by rw [hm0]; exact hrb0
          rw [liftE_mode v hrb1, liftE_mode v hrb0, hm0]
      · rw [liftE_ty' h habΔ h1, liftE_ty' h hab h0, ht0]
      · by_cases hrb0 : E0.mode = .rootb
        · rw [hrb (Or.inl hrb0)]
        · exact absurd hr (liftE_not_fixed hrb0)
    · rw [hc] at hy
      exact ⟨E, by rw [canon_frame Γa hyf]; exact hy, rfl, rfl, fun _ => rfl⟩

/-- The renaming lemma: a callee's source statement, typed in its own
    contexts, is typed where the call places it, in the caller's view of
    those contexts. -/
theorem StmtT.ren (h : S.OK) {P : Prog} (hP : ProgOK P) {Γa : Ctx} {Fa : List Var} {s : Stmt}
    {Δa : Ctx} (hd : StmtT P Γa Fa s Δa) : s.src = true → S.AbsOK Γa → CtxWF Γa → NameWF Γa →
    StmtT P (S.canon Γa) S.Fc (s.rename S.ρ) (S.canon Δa) ∧ S.AbsOK Δa := by
  induction hd with
  | skip => exact fun _ hab _ _ => ⟨StmtT.skip, hab⟩
  | @seq Γ Γ1 Δ F a b hb ta tb iha ihb =>
    intro hs hab hw hn
    simp only [Stmt.src, Bool.and_eq_true] at hs
    obtain ⟨t1, ab1⟩ := iha hs.1 hab hw hn
    obtain ⟨t2, ab2⟩ := ihb hs.2 ab1 (ta.wf hP hw) (ta.names hP hs.1 hn)
    exact ⟨StmtT.seq (by rw [src_rename]; exact hb) t1 t2, ab2⟩
  | @letv Γ Γ1 Δ F x r k E hks hx hxF hr hk _ ih =>
    intro _ hab hw hn
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h hab hr
    obtain ⟨hn1, hEn, _⟩ := hr.names hn
    have hab1 := RhsT.absOK (S := S) hr hab
    obtain ⟨hmo, _⟩ := RhsT.out hr
    obtain ⟨hw1, hdom, _, hEr⟩ := hr.wf hw
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 hEr
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx⟩
    rw [canon_exitScope h abk (Or.inl hbx)]
    have hwc := canon_wf h habx hwx
    have hnc := canon_names h habx hnx
    rw [canon_setE h] at hwc hnc tk
    exact StmtT.letv (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) hr'
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) (hE' x), hwc, hnc⟩ tk)
      (NoPin.lift h abk (fun bh hb => by rw [hbx] at hb; cases hb))
  | @letd Γ Γ1 Δ F x f r k E hks hx hxF hr hown hview hdtor hk _ ih =>
    intro _ hab hw hn
    obtain ⟨E', hr', hE'⟩ := RhsT.ren h hab hr
    obtain ⟨hn1, hEn, _⟩ := hr.names hn
    have hab1 := RhsT.absOK (S := S) hr hab
    obtain ⟨hmo, _⟩ := RhsT.out hr
    obtain ⟨hw1, hdom, _, hEr⟩ := hr.wf hw
    have hx1 : Γ1 x = none := by have := hdom x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 hEr
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx⟩
    rw [canon_exitScope h abk (Or.inl hbx)]
    have hwc := canon_wf h habx hwx
    have hnc := canon_names h habx hnx
    rw [canon_setE h] at hwc hnc tk
    have hl := (hE' x).1
    have hm := (hE' x).2.1
    simp only [liftE, hown, reduceCtorEq, ite_false, liftMode] at hl hm
    exact StmtT.letd (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) hr'
      hm.symm (by rw [← hl]; exact hview) (by rw [← hl]; exact hdtor)
      (StmtT.weakenIn ⟨PW.setE (PW.refl _) (hE' x), hwc, hnc⟩ tk)
      (NoPin.lift h abk (fun bh hb => by rw [hbx] at hb; cases hb))
  | @callc Γ Γ1 Δ F x c j zs k Ec E ms σ sig hks hx hxF hc htc hj hσ hhd hout hcT hnz hk _ ih =>
    intro _ hab hw hn
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h hab hP hcT
    obtain ⟨hn1, hEn, _⟩ := hcT.names hP hn
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hcT hab
    obtain ⟨hw1, hdm, hE⟩ := hcT.wf hP hw
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hlc : Ec.live = true := by
      obtain ⟨fn, _, hlen, hargs, _⟩ := hcT
      obtain ⟨Ea, hEa, hl, _⟩ := hargs 0 (by rw [← hlen]; simp)
      simp only [List.getD_cons_zero] at hEa; rw [hc] at hEa; cases hEa; exact hl
    have hwx := hw1.add hx1 (fun _ _ => recvRes_roots hw hdm hc hlc (by rw [htc]; simp) hE)
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) (recvRes_named (c := c) (Ec := Ec) hEn)
    have habx := hab.add hab1 hx (E := recvRes c Ec E) hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx⟩
    rw [canon_exitScope h abk (Or.inl hbx)]
    have hwc := canon_wf h habx hwx
    have hnc := canon_names h habx hnx
    rw [canon_setE h] at hwc hnc tk
    refine StmtT.callc (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hx]; rfl) (h.Fcout x)
      (by rw [canon_ρ h, hc]; rfl) (by rw [liftE_ty' h hab hc]; exact htc) hj hσ hhd hout hc'
      (fun z hz d hd hb hdr => ?_)
      (StmtT.weakenIn ⟨PW.setE hpw (recvRes_lift h hab hc hmo x (hE' x)), hwc, hnc⟩ tk)
      (NoPin.lift h abk (fun bh hb => by rw [hbx] at hb; cases hb))
    -- no argument is a binding the receiver may change: in the callee, nor
    -- where the call places it (what the arguments held names the frame; a
    -- symbolic name's image names an `inout` argument the receiver names)
    obtain ⟨z0, hz0, rfl⟩ := List.mem_map.mp hz
    by_cases hrb : Ec.mode = .rootb
    · have hvd : (S.liftE c Ec).vdeps = (S.pe c).vdeps := by simp [liftE, hrb, Entry.vdeps]
      rw [hvd] at hd
      obtain ⟨b, t, rfl, hbw, hpt, hbn, hbr, hf⟩ := pe_ρ h hd hdr
      exact hnz z0 hz0 ⟨z0, .name b t⟩ (abs_sym hab hc hrb hf (h.sym_of _ b t hbw hpt hbn hbr)) hb rfl
    · rcases liftE_vdeps_cases hrb hd with ⟨d0, hd0, rfl⟩ | ha
      · exact hnz z0 hz0 d0 hd0 hb (h.inj _ _ hdr)
      · exact A_out h ha z0 hdr.symm
  | @letcall Γ Γ1 Δ F x f args k E hks hx hxF hc hk _ ih =>
    intro _ hab hw hn
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h hab hP hc
    obtain ⟨hn1, hEn, _⟩ := hc.names hP hn
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hc hab
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP hw
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 (fun _ _ => hE)
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx⟩
    rw [canon_exitScope h abk (Or.inl hbx)]
    have hwc := canon_wf h habx hwx
    have hnc := canon_names h habx hnx
    rw [canon_setE h] at hwc hnc tk
    exact StmtT.letcall (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) hc'
      (StmtT.weakenIn ⟨PW.setE hpw (hE' x), hwc, hnc⟩ tk)
      (NoPin.lift h abk (fun bh hb => by rw [hbx] at hb; cases hb))
  | scope => intro hs; simp [Stmt.src] at hs
  | scopeD => intro hs; simp [Stmt.src] at hs
  | rbind => intro hs; simp [Stmt.src] at hs
  | frozen => intro hs; simp [Stmt.src] at hs
  | panic hwf hnΔ hdom hm =>
    intro _ hab _ _
    have habΔ := hab.of_same hdom hm
    obtain ⟨hdom', hm'⟩ := canon_same h hab hdom hm
    exact ⟨StmtT.panic (canon_wf h habΔ hwf) (canon_names h habΔ hnΔ) hdom' hm', habΔ⟩
  | @letrec Γ Γ1 Δ F x f k E fn hks hx hxF hf hp hty ho hc hk _ ih =>
    intro _ hab hw hn
    obtain ⟨E', Γ', hc', hpw, hE'⟩ := callT_ren h hab hP hc
    obtain ⟨hn1, hEn, _⟩ := hc.names hP hn
    obtain ⟨hab1, hmo, _⟩ := CallT.absOK (S := S) hc hab
    obtain ⟨hw1, hdm, hE⟩ := hc.wf hP hw
    have hx1 : Γ1 x = none := by have := hdm.1 x; rw [hx] at this; cases h' : Γ1 x <;> simp_all
    have hwx := hw1.add hx1 (fun _ _ => hE)
    have hnx := NameWF.setE hn1 (fun Ex h => by rw [hx1] at h; cases h) (fun Ex h => by rw [hx1] at h; cases h) hEn
    have habx := hab.add hab1 hx hmo
    obtain ⟨tk, abk⟩ := ih hks habx hwx hnx
    have hbx := hab.fresh hx
    refine ⟨?_, abk.exitScope hbx⟩
    rw [canon_exitScope h abk (Or.inl hbx)]
    have hwc := canon_wf h habx hwx
    have hnc := canon_names h habx hnx
    rw [canon_setE h] at hwc hnc tk
    exact StmtT.letrec (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) hf hp
      hty ho hc' (StmtT.weakenIn ⟨PW.setE hpw (hE' x), hwc, hnc⟩ tk)
      (NoPin.lift h abk (fun bh hb => by rw [hbx] at hb; cases hb))
  | catchR => intro hs; simp [Stmt.src] at hs
  | @assign Γ Γ1 F x r Ex E hx hxF hmodes hr hty hxd hsome hpin =>
    intro _ hab hw hn
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
    have hT := StmtT.assign (P := P) hx hxF hmodes hr hty hxd hsome hpin
    have hwo := hT.wf hP hw
    have hno := hT.names hP rfl hn
    have habo : S.AbsOK (setE (A2.kill .replace false x Γ1) x { E with mode := Ex.mode }) :=
      (hab1.kill _ _ _).setE' hab hx rfl hty hrbx (fun hf => absurd hf (by
        rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩ <;> simp [h1]))
    refine ⟨?_, habo⟩
    have hwc := canon_wf h habo hwo
    have hnc := canon_names h habo hno
    rw [canon_setE h, canon_kill h hab1 hal] at hwc hnc ⊢
    have hT' := StmtT.assign (P := P) (x := S.ρ x) (Ex := S.liftE x Ex) (E := E') (F := S.Fc)
      (by rw [canon_ρ h, hx]; rfl) (h.Fcout x) (by
        rw [hmx', hm']
        rcases hmodes with ⟨h1, h2⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rw [h1, h2]
        · exact Or.inl ⟨rfl, rfl⟩
        · exact Or.inl ⟨rfl, rfl⟩
        · exact Or.inr (Or.inr ⟨rfl, rfl⟩))
      hr' (by rw [hty', liftE_ty x hrbx, hty]) (by
        have hsub : E'.vdeps ⊆ rds S.ρ E.vdeps ++ S.A :=
          fun d hd => liftE_vdeps_sub hrbE (vdeps_sub hw' (by rw [liftE_live]; exact hlive) hd)
        exact roots_lift_ρ h hsub hxd)
      (by rw [canon_ρ h]; simpa using hsome)
      (NoPin.lift h hab (bnd_replace hab hx (by
        rcases hmodes with ⟨h1, _⟩ | ⟨h1, _⟩ | ⟨h1, _⟩
        · exact Or.inl h1
        · exact Or.inr (Or.inl h1)
        · exact Or.inr (Or.inr h1))))
    refine StmtT.weakenOut (canon_wf h hab hw) (canon_names h hab hn) hT'
      (Or.inr ⟨PW.setE (PW.refl _) ?_, hwc, hnc⟩)
    have hf : S.liftE x { E with mode := Ex.mode } =
        ⟨E.ty, liftMode Ex.mode, E.live,
         rds S.ρ E.path ++ (if Ex.mode.ownSlot then [] else S.A),
         rds S.ρ E.held ++ ownHeld Ex.mode.ownSlot E.ty S.A, false⟩ := by
      simp [liftE, hrbx]
    have hf' : S.liftE x E =
        ⟨E.ty, liftMode E.mode, E.live,
         rds S.ρ E.path ++ (if E.mode.ownSlot then [] else S.A),
         rds S.ρ E.held ++ ownHeld E.mode.ownSlot E.ty S.A, false⟩ := by
      simp [liftE, hrbE]
    rw [hf, hmx']
    rw [hf'] at hw'
    obtain ⟨_, _, _, hlv⟩ := hw'
    refine EntryWeaker.mk' hty'.symm rfl (not_fixed_liftMode rfl hrbx) ?_ (fun ho => ?_) ?_
    · show E.live = E'.live
      rw [hlive]; exact ((hlv hlive).1).symm
    · have ho' : E.mode.ownSlot = false := by
        rw [← hos]; simpa [liftMode_ownSlot] using ho
      rw [hos]
      exact (hlv hlive).2.1 (by rw [hm', liftMode_ownSlot]; exact ho')
    · rw [hos]; exact (hlv hlive).2.2
  | @ite Γ Δ F c a b ha hb hc ta tb iha ihb =>
    intro _ hab hw hn
    obtain ⟨t1, ab1⟩ := iha ha hab hw hn
    obtain ⟨t2, _⟩ := ihb hb hab hw hn
    exact ⟨StmtT.ite (by rw [src_rename]; exact ha) (by rw [src_rename]; exact hb)
      (exprT_ren h hab hc) t1 t2, ab1⟩
  | @«while» Γ F c k hk hc tk ih =>
    intro _ hab hw hn
    obtain ⟨t, _⟩ := ih hk hab hw hn
    exact ⟨StmtT.while (by rw [src_rename]; exact hk) (exprT_ren h hab hc) t, hab⟩
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1 =>
    intro _ hab hw hn
    obtain ⟨D', hpa', hD', hD'o⟩ := pushArg_ren h hab hy hpa
    have hab1 := PushArg.absOK (S := S) hy hpa hab
    have hrbx : Ex.mode ≠ .rootb := by rcases hcan with hm | ⟨b, hm, _⟩ <;> rw [hm] <;> simp
    obtain ⟨E0, h0, hm1⟩ := (hpa.domMode hy).2 x Ex1 hx1
    rw [hx] at h0; cases h0
    have hrb1 : Ex1.mode ≠ .rootb := by rw [hm1]; exact hrbx
    have hT := StmtT.push (P := P) hx hl hty hcan hxF hy hly htyy hyx hpa hxD hx1 hl1
    have hwo := hT.wf hP hw
    have hno := hT.names hP rfl hn
    have habo : S.AbsOK (setE (A2.kill .realloc t.holdsView x Γ1) x
        { Ex1 with held := Ex1.held ++ ownHeld true t D }) :=
      (hab1.kill _ _ _).setE' hab1 hx1 rfl rfl hrb1 (fun hf => by
        have hf0 : Ex1.fixed := hf
        obtain ⟨hl0, hh0⟩ := hab1.fixed hx1 hf0 hrb1
        have hty1 : Ex1.ty = .vec t := by rw [PushArg.ty_at hpa hy hx hx1, hty]
        have hv : t.holdsView = false := by
          rcases hf0 with h' | ⟨_, _, _, h'⟩
          · exact absurd h' hrb1
          · rw [hty1] at h'; exact h'
        exact ⟨hl0, by simp [hh0, ownHeld, hv]⟩)
    refine ⟨?_, habo⟩
    have hwc := canon_wf h habo hwo
    have hnc := canon_names h habo hno
    rw [canon_setE h, canon_kill h hab1 (allowed_canDo hab hx hty hcan)] at hwc hnc ⊢
    have hT' := StmtT.push (P := P) (F := S.Fc) (x := S.ρ x) (y := S.ρ y) (Ex := S.liftE x Ex)
      (Ey := S.liftE y Ey) (Ex1 := S.liftE x Ex1) (t := t) (D := D')
      (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl) (by rw [liftE_ty' h hab hx]; exact hty)
      (by rw [liftE_mode x hrbx]; exact canDo_lift hcan) (h.Fcout x)
      (by rw [canon_ρ h, hy]; rfl) (by rw [liftE_live]; exact hly) (by rw [liftE_ty' h hab hy]; exact htyy)
      (fun e => hyx (h.inj _ _ e)) hpa' (roots_lift_ρ h hD' hxD)
      (by rw [canon_ρ h, hx1]; rfl) (by rw [liftE_live]; exact hl1)
    refine StmtT.weakenOut (canon_wf h hab hw) (canon_names h hab hn) hT'
      (Or.inr ⟨PW.setE (PW.refl _) ?_, hwc, hnc⟩)
    refine EntryWeaker.mk' (by simp [liftE, hrb1]) (by simp [liftE, hrb1])
      (not_fixed_liftMode (by simp [liftE, hrb1]) hrb1) (by simp [liftE, hrb1]) (fun _ => by simp [liftE, hrb1]) ?_
    have hty1 : Ex1.ty = .vec t := by rw [PushArg.ty_at hpa hy hx hx1, hty]
    have hD'' : D' ⊆ rds S.ρ D ++ ownHeld Ex1.mode.ownSlot Ex1.ty S.A := by
      intro d hd
      rcases List.mem_append.mp (hD'o htyy hd) with h1 | h1
      · exact List.mem_append_left _ h1
      · refine List.mem_append_right _ ?_
        rw [hty1]
        cases Ex1.mode.ownSlot
        · simp only [ownHeld_false]; exact ownHeld_sub _ _ _ h1
        · have : ownHeld true (Ty.vec t) S.A = ownHeld true t S.A := by simp [ownHeld, Ty.holdsView]
          rw [this]; exact h1
    simp only [liftE, hrb1, ↓reduceIte]
    by_cases hv : t.holdsView = true
    · have h1 : ownHeld true t D' = D' := ownHeld_views true hv D'
      have h2 : ownHeld true t D = D := ownHeld_views true hv D
      rw [h1, h2]
      exact app_lift (S := S) (List.Subset.refl _) hD''
    · have hv' : t.holdsView = false := by simpa using hv
      simp only [ownHeld, hv', Bool.not_false, Bool.and_self, ↓reduceIte, List.append_nil]
      exact append_sub (List.Subset.refl _) (List.Subset.refl _)
  | @free Γ F x E t hx hl hm hty hxF _ =>
    intro _ hab _ _
    have hrb : E.mode ≠ .rootb := by rw [hm]; simp
    refine ⟨?_, (hab.kill _ _ _).setE' hab hx rfl rfl hrb (fun hf => absurd hf (by simp [hm]))⟩
    rw [canon_setE h, canon_kill h hab (allowed_own hab hx hm _ _), liftE_moved _ hrb]
    exact StmtT.free (by rw [canon_ρ h, hx]; rfl) (by rw [liftE_live]; exact hl)
      (by rw [liftE_mode x hrb, hm]; rfl) (by rw [liftE_ty' h hab hx]; exact hty) (h.Fcout x)
      (NoPin.lift h hab (bnd_own hab hx hm))
  | @unpair Γ Δ F y x z k E a b hks hy hl hm hty hyF hx hz hxz hxF hzF hk _ _ _ ih =>
    intro _ hab hw hn
    have hrep := canDo_replace_cases hm
    have hrb : E.mode ≠ .rootb := by rcases hrep with h1 | h1 <;> rw [h1] <;> simp
    have hxy : x ≠ y := fun e => by rw [e, hy] at hx; cases hx
    have hzy : z ≠ y := fun e => by rw [e, hy] at hz; cases hz
    have hab1 : S.AbsOK (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) :=
      (hab.kill _ _ _).setE' hab hy rfl rfl hrb (fun hf => absurd hf (by
        rcases hrep with h1 | h1 <;> simp [h1]))
    have hcm : ∀ t, (compE E t).mode = .own ∨ (compE E t).mode = .bor := by
      intro t; cases t <;> simp [compE, intE]
    have habx := AbsOK.add hab hab1 hx (hcm a)
    have habz := AbsOK.add hab habx hz (hcm b)
    have hw3 := hw.unpair hy hl hm.ownSlot hty hx hz hxz
    have hn3 := hn.unpair hy hl hty hx hz hxz
    obtain ⟨tk, abk⟩ := ih hks habz hw3 hn3
    have hbx := hab.fresh hx
    have hbz := hab.fresh hz
    have hpz := NoPin.lift h abk (y := z) (fun bh hb => by rw [hbz] at hb; cases hb)
    have hpx := NoPin.lift h (abk.exitScope hbz) (y := x) (fun bh hb => by rw [hbx] at hb; cases hb)
    rw [canon_exitScope h abk (Or.inl hbz)] at hpx
    refine ⟨?_, (abk.exitScope hbz).exitScope hbx⟩
    rw [canon_exitScope h (abk.exitScope hbz) (Or.inl hbx), canon_exitScope h abk (Or.inl hbz)]
    have hwc := canon_wf h habz hw3
    have hnc := canon_names h habz hn3
    have hal : Allowed S .replace false y := allowed_replace hab hy (by
      rcases hrep with h1 | h1
      · exact Or.inl h1
      · exact Or.inr (Or.inr h1)) false
    rw [canon_setE h, canon_setE h, canon_setE h, canon_kill h hab hal,
      liftE_moved _ hrb] at hwc hnc tk
    have hxz' : S.ρ x ≠ S.ρ z := fun e => hxz (h.inj _ _ e)
    refine StmtT.unpair (by rw [src_rename]; exact hks) (by rw [canon_ρ h, hy]; rfl)
      (by rw [liftE_live]; exact hl) (by
        rw [liftE_mode y hrb]; rcases hrep with h1 | h1 <;> rw [h1] <;> exact Or.inl rfl)
      (by rw [liftE_ty' h hab hy]; exact hty)
      (h.Fcout y) (by rw [canon_ρ h, hx]; rfl) (by rw [canon_ρ h, hz]; rfl) hxz' (h.Fcout x) (h.Fcout z)
      (StmtT.weakenIn ⟨PW.setE (PW.setE (PW.refl _) (compE_lift h hab hy a x)) (compE_lift h hab hy b z),
        hwc, hnc⟩ tk) (NoPin.lift h hab (bnd_replace hab hy (by
          rcases hrep with h1 | h1
          · exact Or.inl h1
          · exact Or.inr (Or.inl h1)))) hpz hpx
  | @sub Γ Γ0 Δ0 Δ F k hw0 tk ho ih =>
    intro hs hab hw hn
    have hab0 := hab.weaker hw0
    obtain ⟨t, abΔ0⟩ := ih hs hab0 hw0.2.1 hw0.2.2
    have hwc := canon_weaker h hab0 hw0.2.1 hw0
    rcases ho with rfl | hwo
    · exact ⟨StmtT.weakenIn hwc t, abΔ0⟩
    · have abΔ := abΔ0.weaker hwo
      exact ⟨StmtT.sub hwc t (Or.inr (canon_weaker h abΔ hwo.2.1 hwo)), abΔ⟩

end RSetup

end A2
