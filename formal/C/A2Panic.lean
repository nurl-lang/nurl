module

public import C.A2Rhs
public import A2.Invariant

@[expose] public section

/-!
# C10: `CtxWF` and `NameWF` decided; A2's `panic` (AGORA-970)

A2's well-formedness of a context (`CtxWF`: live entries depend only on
roots it has, an armed destructor binding too, only `letd`'s bindings run
destructors, of view-holding types) and its naming discipline (`NameWF`:
every closure dependency by name names a live owner of the recorded type)
are decided over the finite domain (`ctxWF2B_sound`, `nameWFB_sound`).
They give the `panic` rule with the context unchanged (`panic_self`). A
panic in one arm of an `ite`, adopting the other arm's context, is the
next step.
-/

namespace C

open A2

def rootsHave (Γ : Ctx) (rs : List Var) : Bool :=
  rs.all fun r => match Γ r with
    | some Er => Er.mode.isRoot
    | none => false

theorem rootsHave_sound {Γ : Ctx} {rs : List Var} (h : rootsHave Γ rs = true) :
    ∀ r ∈ rs, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  have := List.all_eq_true.mp h r hr
  revert this
  cases hE : Γ r with
  | none => intro h; cases h
  | some Er => intro h; exact ⟨Er, rfl, h⟩

def ctxWF2B (D : List Var) (Γ : Ctx) : Bool :=
  D.all fun v => match Γ v with
    | some E =>
      (!E.live || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) || rootsHave Γ (roots E.vdeps)) &&
      (!E.dbind || !E.mode.ownSlot || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
        rootsHave Γ ((E.vdeps.filter (fun d => !d.kind.isName)).map (·.root))) &&
      (!E.dtor || E.dbind) && (!E.dbind || E.ty.holdsView)
    | none => true

theorem ctxWF2B_sound {D : List Var} {Γ : Ctx} (hs : Supported2 Γ D) (h : ctxWF2B D Γ = true) : CtxWF Γ := by
  have get : ∀ v E, Γ v = some E → _ := fun v E hE => by
    have := List.all_eq_true.mp h v (mem_of_some2 hs hE)
    rw [hE] at this
    exact this
  refine ⟨fun v E hE hl hk r hr => ?_, fun v E hE hd ho hk d hd' hn => ?_, fun v E hE hd => ?_, fun v E hE hd => ?_⟩
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this.1.1.1 with (h0 | h0) | h0
    · rw [hl] at h0; cases h0
    · exact absurd hk h0
    · exact rootsHave_sound h0 r hr
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
    rcases this.1.1.2 with ((h0 | h0) | h0) | h0
    · rw [hd] at h0; cases h0
    · rw [ho] at h0; cases h0
    · exact absurd hk h0
    · exact rootsHave_sound h0 d.root (List.mem_map.mpr ⟨d, List.mem_filter.mpr ⟨hd', by simp [hn]⟩, rfl⟩)
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at this
    rcases this.1.2 with h0 | h0
    · rw [hd] at h0; cases h0
    · exact h0
  · have := get v E hE
    simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at this
    rcases this.2 with h0 | h0
    · rw [hd] at h0; cases h0
    · exact h0

/-- `DepsNamed`, decided. -/
def depsNamedB (Γ : Ctx) (ds : List Dep) : Bool :=
  ds.all fun d => match d.kind with
    | .name b t => match Γ d.root with
      | some Er => Er.live && Er.held.isEmpty && decide (Er.ty = t) && Er.mode.ownSlot &&
          (decide (b = .none) || (decide (b ≠ .replace) && canDoB2 Er.mode b)) && !t.holdsView
      | none => false
    | _ => true

theorem depsNamedB_sound {Γ : Ctx} {ds : List Dep} (h : depsNamedB Γ ds = true) : DepsNamed Γ ds := by
  intro d hd b t hk
  have := List.all_eq_true.mp h d hd
  rw [hk] at this
  simp only at this
  revert this
  cases hE : Γ d.root with
  | none => intro h; cases h
  | some Er =>
    intro h
    simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true', List.isEmpty_iff] at h
    obtain ⟨⟨⟨⟨⟨hl, hh⟩, ht⟩, ho⟩, hb⟩, hv⟩ := h
    refine ⟨Er, rfl, hl, hh, ht, ho, ?_, hv⟩
    rcases hb with h0 | ⟨h0, h1⟩
    · exact Or.inl h0
    · exact Or.inr ⟨h0, canDoB2_sound h1⟩

def nameWFB (D : List Var) (Γ : Ctx) : Bool :=
  D.all fun v => match Γ v with
    | some E => !E.live || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) || depsNamedB Γ E.vdeps
    | none => true

theorem nameWFB_sound {D : List Var} {Γ : Ctx} (hs : Supported2 Γ D) (h : nameWFB D Γ = true) : NameWF Γ := by
  intro v E hE hl hk
  have := List.all_eq_true.mp h v (mem_of_some2 hs hE)
  rw [hE] at this
  simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at this
  rcases this with (h0 | h0) | h0
  · rw [hl] at h0; cases h0
  · exact absurd hk h0
  · exact depsNamedB_sound h0

/-- A panic, typed with the context unchanged. -/
theorem panic_self {P : Prog} {ξ : Exits} {D : List Var} {Γ : Ctx} {F : List Var} (hs : Supported2 Γ D)
    (h1 : ctxWF2B D Γ = true) (h2 : nameWFB D Γ = true) : StmtT P ξ Γ F .panic Γ :=
  .panic (ctxWF2B_sound hs h1) (nameWFB_sound hs h2) (fun _ => rfl)
    (fun _ E hE => ⟨E, hE, rfl, rfl, fun _ => rfl⟩) (DKeep.refl Γ []) (DStay.refl Γ []) id

/-! ### A panic into a given context -/

def fixedB (E : Entry) : Bool :=
  match E.mode with
  | .rootb => true
  | .inout b => decide (b ≠ .replace) && !E.ty.holdsView
  | _ => false

theorem fixedB_sound {E : Entry} (h : fixedB E = false) : ¬ E.fixed := by
  intro hf
  rcases hf with hm | ⟨b, hm, hb, hv⟩
  · simp [fixedB, hm] at h
  · simp [fixedB, hm, hb, hv] at h

def isFrame (m : Mode) : Bool :=
  match m with
  | .own => true
  | .inout _ => true
  | _ => false

theorem isFrame_sound {m : Mode} (h : isFrame m = true) : m.frame := by
  unfold isFrame at h; split at h
  · exact Or.inl rfl
  · rename_i b; exact Or.inr ⟨b, rfl⟩
  · cases h

/-- `FreshE`, decided. -/
def freshEB (Γ : Ctx) (E : Entry) : Bool :=
  !E.live || !(decide (E.ty ≠ .int)) || !(decide (E.mode = .bor)) || !E.fresh ||
    (!E.path.isEmpty && E.path.all fun d =>
      decide (d.kind = .self ∨ d.kind = .inner ∨ d.kind = .view) &&
        (match Γ d.root with | some Er => isFrame Er.mode | none => false))

theorem freshEB_sound {Γ : Ctx} {E : Entry} (h : freshEB Γ E = true) : FreshE Γ E := by
  intro hl hty hm hf
  simp only [freshEB, hl, hm, hf, Bool.not_true, Bool.false_or, Bool.or_eq_true, Bool.not_eq_true',
    decide_eq_false_iff_not, Classical.not_not, decide_true, Bool.and_eq_true, List.isEmpty_eq_false_iff] at h
  rcases h with h0 | ⟨hne, hall⟩
  · simp at h0; exact absurd h0 hty
  · refine ⟨hne, fun d hd => ?_⟩
    have := List.all_eq_true.mp hall d hd
    simp only [Bool.and_eq_true, decide_eq_true_eq] at this
    refine ⟨this.1, ?_⟩
    have h2 := this.2
    revert h2
    cases hE : Γ d.root with
    | none => intro h; cases h
    | some Er => intro h; exact ⟨Er, rfl, isFrame_sound h⟩

def freshOKB (D : List Var) (Γ : Ctx) : Bool :=
  D.all fun v => match Γ v with
    | some E => freshEB Γ E
    | none => true

theorem freshOKB_sound {D : List Var} {Γ : Ctx} (hs : Supported2 Γ D) (h : freshOKB D Γ = true) : FreshOK Γ := by
  intro v E hE
  have := List.all_eq_true.mp h v (mem_of_some2 hs hE)
  rw [hE] at this
  exact freshEB_sound this

/-- The premises of `panic` (and of `loop`'s end) into `Δ`, decided. -/
def panicToB (D : List Var) (Γ Δ : Ctx) : Bool :=
  ctxWF2B D Δ && nameWFB D Δ && freshOKB D Δ &&
  D.all fun v =>
    (Γ v).isSome == (Δ v).isSome &&
    (match Δ v, Γ v with
     | some E, some E0 => decide (E.mode = E0.mode) && decide (E.ty = E0.ty) && (!fixedB E0 || decide (E = E0)) &&
        (!E.dbind || !E.mode.ownSlot || !(decide (E.ty ≠ .int ∨ E.mode = .rootb)) ||
          (E0.dbind && E0.mode.ownSlot && decide (E0.ty ≠ .int ∨ E0.mode = .rootb) &&
            E.vdeps.all fun d => d.kind.isName || decide (d ∈ E0.vdeps)))
     | none, _ => true
     | some _, none => false) &&
    (match Γ v with
     | some E0 => !E0.dbind || !E0.mode.ownSlot ||
        (match Δ v with | some E' => E'.dbind && E'.mode.ownSlot | none => false)
     | none => true)

/-- What `panic` and `loop` ask of the context after. -/
def PanicPrem (Γ Δ : Ctx) : Prop :=
  CtxWF Δ ∧ NameWF Δ ∧ (∀ v, (Γ v).isSome = (Δ v).isSome) ∧
  (∀ v E, Δ v = some E → ∃ E0, Γ v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧ (E0.fixed → E = E0)) ∧
  DKeep Γ Δ [] ∧ DStay Γ Δ [] ∧ (FreshOK Γ → FreshOK Δ)

theorem panicToB_prem {D : List Var} {Γ Δ : Ctx}
    (hs : Supported2 Γ D) (hsΔ : Supported2 Δ D) (h : panicToB D Γ Δ = true) : PanicPrem Γ Δ := by
  simp only [panicToB, Bool.and_eq_true] at h
  obtain ⟨⟨⟨hwf, hnw⟩, hfr⟩, hall⟩ := h
  have get : ∀ v, v ∈ D → _ := fun v hv => List.all_eq_true.mp hall v hv
  refine ⟨ctxWF2B_sound hsΔ hwf, nameWFB_sound hsΔ hnw, fun v => ?_, fun v E hE => ?_,
    fun v E' hE' hd ho hk _ => ?_, fun v E hE hd ho _ => ?_, fun _ => freshOKB_sound hsΔ hfr⟩
  · by_cases hv : v ∈ D
    · have := get v hv
      simp only [Bool.and_eq_true, beq_iff_eq] at this
      exact this.1.1
    · rw [hs v hv, hsΔ v hv]
  · have hv := mem_of_some2 hsΔ hE
    have := (get v hv)
    simp only [Bool.and_eq_true] at this
    have h2 := this.1.2
    rw [hE] at h2
    revert h2
    cases hE0 : Γ v with
    | none => intro h; cases h
    | some E0 =>
      intro h2
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true'] at h2
      obtain ⟨⟨⟨hm, ht⟩, hfx⟩, _⟩ := h2
      refine ⟨E0, rfl, hm, ht, fun hf => ?_⟩
      rcases hfx with h0 | h0
      · exact absurd hf (fixedB_sound h0)
      · exact h0
  · have hv := mem_of_some2 hsΔ hE'
    have := (get v hv)
    simp only [Bool.and_eq_true] at this
    have h2 := this.1.2
    rw [hE'] at h2
    revert h2
    cases hE0 : Γ v with
    | none => intro h; cases h
    | some E0 =>
      intro h2
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true, Bool.not_eq_true',
        decide_eq_false_iff_not] at h2
      obtain ⟨_, hk2⟩ := h2
      rcases hk2 with ((h0 | h0) | h0) | ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩
      · rw [hd] at h0; cases h0
      · rw [ho] at h0; cases h0
      · exact absurd hk h0
      · refine ⟨E0, rfl, h1, h2, h3, fun d hdd hn => ?_⟩
        have := List.all_eq_true.mp h4 d hdd
        simp only [hn, Bool.false_or, decide_eq_true_eq] at this
        exact this
  · have hv := mem_of_some2 hs hE
    have := (get v hv)
    simp only [Bool.and_eq_true] at this
    have h3 := this.2
    rw [hE] at h3
    simp only [hd, ho, Bool.not_true, Bool.false_or] at h3
    revert h3
    cases hE' : Δ v with
    | none => intro h; cases h
    | some E' =>
      intro h3
      simp only [Bool.and_eq_true] at h3
      exact ⟨E', rfl, h3.1, h3.2⟩

theorem panicToB_sound {P : Prog} {ξ : Exits} {D : List Var} {Γ Δ : Ctx} {F : List Var}
    (hs : Supported2 Γ D) (hsΔ : Supported2 Δ D) (h : panicToB D Γ Δ = true) : StmtT P ξ Γ F .panic Δ := by
  obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := panicToB_prem hs hsΔ h
  exact .panic h1 h2 h3 h4 h5 h6 h7

end C
