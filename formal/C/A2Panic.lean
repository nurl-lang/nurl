import C.A2Rhs
import A2.Invariant

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

end C
