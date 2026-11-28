module

public import C.A2Chan

@[expose] public section

/-!
# C8p: A2's closure literal and its captures by name, decided (AGORA-978)

`.pack fs te ms y cs`: the environment `y` (of type `te`) moves in, as
`vec_push` takes it (`PushArg`, `pushArg2`), and the captures by name `cs`
meet `CapsOK` (`capsB`): each read only (`inp`), or a Vec the closure
changes (`inout b`, a bound short of a new value). The class is the one the
literal's interface declares where it fits (`packClass`, AGORA-1020: a
spawned closure's interface is of class `send`), else `any`, the one every
closure value of a type shares, whatever environment it carries; `any`
fits an environment that holds no destructor value (`Cross.Fits`: `any`
allows views, cells and shares, and no destructor values).
`inferRhs2p` is `inferRhs2c` with it; `inferRhs2p_ok` is sound and keeps
contexts inside the domain.
-/

namespace C

open A2

theorem fits_any {te : Ty} {cs : List (Var × PMode × Ty)} (h : te.holdsDtor = false) : Cross.Fits .any te cs := by
  unfold Cross.Fits; simp [h]

/-- One capture by name of `CapsOK`, decided: a live binding that holds
    nothing, of the recorded type, owning its slot, holding no views; read
    only (`inp`), with nothing the environment holds naming it with an
    effect; or changed (`inout b`, a Vec whose elements hold no views, `b`
    neither nothing nor a new value, and one the binding may undergo), with
    the binding not frozen, and nothing the environment or another capture
    holds rooted at it. -/
def capOKB (Γ : Ctx) (F : List Var) (D : List Dep) (c : Var × PMode × Ty) : Bool :=
  match Γ c.1 with
  | some Ev => Ev.live && Ev.held.isEmpty && decide (Ev.ty = c.2.2) && Ev.mode.ownSlot &&
      !c.2.2.holdsView &&
      match c.2.1 with
      | .inp => D.all (fun d => !(decide (d.root = c.1)) || !d.kind.isName || decide (d.kind.bound = .none))
      | .inout b => decide (b ≠ .none) && decide (b ≠ .replace) && canDoB2 Ev.mode b &&
          decide (c.1 ∉ F) &&
          (match c.2.2 with | .vec s => !s.holdsView | _ => false) &&
          D.all (fun d => decide (d.root ≠ c.1))
      -- (nothing another capture holds is rooted at `c`: every capture holds
      -- nothing, by its own `held.isEmpty` (`capOKB_held`), so no scan of the
      -- captures per capture; github#2242's review)
      | .sink => false
  | none => false

/-- `CapsOK`, decided: the names apart, and each capture `capOKB`. -/
def capsB (Γ : Ctx) (F : List Var) (D : List Dep) (cs : List (Var × PMode × Ty)) : Bool :=
  decide (cs.map (·.1)).Nodup && cs.all (capOKB Γ F D)

/-- A capture `capOKB` accepts holds nothing. -/
theorem capOKB_held {Γ : Ctx} {F : List Var} {D : List Dep} {c : Var × PMode × Ty}
    (h : capOKB Γ F D c = true) : (argE Γ c.1).held = [] := by
  unfold capOKB at h
  split at h
  · rename_i Ev hEv
    simp only [Bool.and_eq_true, List.isEmpty_iff] at h
    simp only [argE, hEv, Option.getD_some]
    exact h.1.1.1.1.2
  · cases h

theorem capsB_sound {Γ : Ctx} {F : List Var} {D : List Dep} {cs : List (Var × PMode × Ty)}
    (h : capsB Γ F D cs = true) : CapsOK Γ F D cs := by
  simp only [capsB, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  refine ⟨h.1, fun c hc => ?_⟩
  have h2 := h.2 c hc
  unfold capOKB at h2
  split at h2
  · rename_i Ev hEv
    simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true', List.isEmpty_iff] at h2
    obtain ⟨⟨⟨⟨⟨hl, hh⟩, hty⟩, ho⟩, hv⟩, hm⟩ := h2
    refine ⟨Ev, hEv, hl, hh, hty, ho, hv, ?_⟩
    obtain ⟨v, m, t⟩ := c
    cases m with
    | inp =>
      simp only [List.all_eq_true, Bool.or_eq_true, Bool.not_eq_true', decide_eq_true_eq,
        decide_eq_false_iff_not] at hm
      refine Or.inl ⟨rfl, fun d hdD hr hn => ?_⟩
      rcases hm d hdD with (h0 | h0) | h0
      · exact absurd hr h0
      · rw [hn] at h0; cases h0
      · exact h0
    | inout b =>
      simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at hm
      obtain ⟨⟨⟨⟨⟨hb0, hbr⟩, hcd⟩, hF⟩, hvec⟩, hD⟩ := hm
      cases t with
      | vec s =>
        simp only [Bool.not_eq_true'] at hvec
        exact Or.inr ⟨b, s, rfl, hb0, hbr, canDoB2_sound hcd, hF, rfl, hvec, hD,
          fun c' hc' d hd => by rw [capOKB_held (h.2 c' hc')] at hd; cases hd⟩
      | _ => simp at hvec
    | sink => cases hm
  · cases h2

/-- `Cross.Fits`, decided. -/
def fitsB (q : Cross) (te : Ty) (cs : List (Var × PMode × Ty)) : Bool :=
  (q.views || (!te.holdsView && cs.isEmpty)) && (q.cells || !te.hasCell) && (q.shares || !te.hasArc) &&
    (q.drops || !te.holdsDtor) && (q.views || !te.hasGuard)

theorem fitsB_sound {q : Cross} {te : Ty} {cs : List (Var × PMode × Ty)} (h : fitsB q te cs = true) :
    Cross.Fits q te cs := by
  simp only [fitsB, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', List.isEmpty_iff] at h
  obtain ⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩ := h
  refine ⟨fun hq => ?_, fun hq => ?_, fun hq => ?_, fun hq => ?_, fun hq => ?_⟩
  · rcases h1 with h1 | h1
    · rw [hq] at h1; cases h1
    · exact h1
  · rcases h2 with h2 | h2
    · rw [hq] at h2; cases h2
    · exact h2
  · rcases h3 with h3 | h3
    · rw [hq] at h3; cases h3
    · exact h3
  · rcases h4 with h4 | h4
    · rw [hq] at h4; cases h4
    · exact h4
  · rcases h5 with h5 | h5
    · rw [hq] at h5; cases h5
    · exact h5

/-- A closure literal's class (AGORA-1020): the one its interface declares,
    where that fits the environment, else `any`. A2's `pack` takes any
    class that fits (`Cross.Fits`), and the literal names no class of its
    own, so the checker reads the one the program's interface function `m`
    (the literal's `ms = [m]`) takes the closure at: its first parameter,
    of type `.fn [m] q`. A closure that is spawned (A3) is of an interface
    of class `send`; every other one keeps `any`, the class every closure
    value of a type shares, so what was accepted stays accepted. -/
def packClass (P : Prog) (ms : List Nat) (te : Ty) (cs : List (Var × PMode × Ty)) : Cross :=
  match ms with
  | [m] => match P[m]? with
    | some fn => match fn.params with
      | (_, .fn ms' q) :: _ => if decide (ms' = ms) && fitsB q te cs then q else .any
      | _ => .any
    | none => .any
  | _ => .any

/-- The class chosen fits the environment, where `any` would (its
    destructor clause). -/
theorem packClass_fits {P : Prog} {ms : List Nat} {te : Ty} {cs : List (Var × PMode × Ty)}
    (hd : te.holdsDtor = false) : Cross.Fits (packClass P ms te cs) te cs := by
  unfold packClass
  split
  · split
    · split
      · split
        · rename_i hq
          simp only [Bool.and_eq_true] at hq
          exact fitsB_sound hq.2
        · exact fits_any hd
      · exact fits_any hd
    · exact fits_any hd
  · exact fits_any hd

/-- A2's `RhsT` for a closure literal, computed. -/
def packRhs (P : Prog) (D : List Var) (Γ : Ctx) (F : List Var) : Rhs → Option (Entry × Ctx)
  | .pack _ te ms y cs => match liveE2 Γ y with
    | some Ey =>
      if decide (Ey.ty = te) && !te.holdsDtor then
        match pushArg2 D Γ F y Ey te with
        | some (Ds, Γ1) =>
          if capsB Γ1 F Ds cs then
            some (⟨.fn ms (packClass P ms te cs), .own, true, [], Ds ++ capDeps cs, false, false, false, false⟩, Γ1)
          else none
        | none => none
      else none
    | none => none
  | _ => none

theorem packRhs_ok {P : Prog} {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : packRhs P D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  cases r with
  | pack _ te ms y cs =>
    simp only [packRhs] at h
    split at h
    · rename_i Ey hEy
      obtain ⟨hy, hyl⟩ := liveE2_some hEy
      split at h
      · rename_i hc
        simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc
        obtain ⟨hty, hd⟩ := hc
        split at h
        · rename_i Ds Γa hpa
          obtain ⟨pa, sa⟩ := pushArg2_sound hs hpa
          split at h
          · rename_i hcap
            simp only [Option.some.injEq, Prod.mk.injEq] at h; obtain ⟨rfl, rfl⟩ := h
            exact ⟨.pack hy hyl hty pa (capsB_sound hcap) (packClass_fits hd), sa (hD y (by simp [Rhs.vars]))⟩
          · cases h
        · cases h
      · cases h
    · cases h
  | _ => simp [packRhs] at h

/-- A2's `RhsT` for the core, data, lock, channel and closure forms, computed. -/
def inferRhs2p (P : Prog) (D : List Var) (Γ : Ctx) (F : List Var) (r : Rhs) : Option (Entry × Ctx) :=
  match packRhs P D Γ F r with
  | some p => some p
  | none => inferRhs2c D Γ F r

theorem inferRhs2p_ok {P : Prog} {D : List Var} {Γ : Ctx} {F : List Var} {r : Rhs} {E : Entry} {Γ1 : Ctx}
    (hs : Supported2 Γ D) (hD : ∀ v ∈ r.vars, v ∈ D) (h : inferRhs2p P D Γ F r = some (E, Γ1)) :
    RhsT Γ F r E Γ1 ∧ Supported2 Γ1 D := by
  unfold inferRhs2p at h
  split at h
  · rename_i p hp
    cases h
    exact packRhs_ok hs hD hp
  · exact inferRhs2c_ok hs hD h

end C
