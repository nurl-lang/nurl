import A2.TypingFacts
import A2.NameWf
import A2.Wf

/-! # Agora #909: each new premise holds with the fresh bit off

Design (e) added `Entry.fresh` and premises that read it:
- the fresh bit of `RhsT.borrow` / `RhsT.at` (`FreshSrc` when set), and of the field and
  payload reads `RhsT.fst` / `snd` / `getl` / `getr` (AGORA-909: a frame binding of a
  view-free type that holds nothing, when set);
- `EntryWeaker.fresh`;
- `FreshOK` after `panic` / `exit` / `loop` and at a scope's end;
- `editB`'s `edit false` (a fresh borrow).

Each is met by choosing the bit off. That is what this file proves, premise by premise:
- `RhsT.borrow_unfresh`, `RhsT.at_unfresh`: the rules with the bit off ask nothing of the source.
- `RhsT.fst_unfresh`, `RhsT.snd_unfresh`, `RhsT.getl_unfresh`, `RhsT.getr_unfresh` (in
  `Typing.lean`, where A3 uses them): a field or payload read with the bit off is `projE`
  itself, as before AGORA-909.
- `EntryWeaker.fresh_of_not`: the weakening premise holds when the weaker entry is not fresh.
- `freshOK_of_noFresh`: a context with no fresh borrow is `FreshOK`.
- `freshOK_unfreshC`: the same holds of any context with every fresh bit cleared (`unfreshC`).
- `weaker_unfreshC`: clearing every fresh bit is a weakening.
- `unfreshC_panic`: the cleared context keeps every binding, mode, type and fixed entry.
- An `edit true` asks nothing of the bit (`editB`'s `hbf` is vacuous).

`StmtT.unfresh` is the result side: any typing still holds with its result's fresh bits cleared.

What is NOT proven here is a translation from the typing relation as it stood before design (e). That relation is no longer in the tree. The claim that every program it typed is typed now rests on the lemmas above: an old derivation is a new one with every bit off, and each new premise of it is one of the cases above. -/

namespace A2

/-- An entry with its fresh bit cleared: only a borrow carries one that
    matters (a fixed entry is never a borrow, and stays as it is). -/
def Entry.unfresh (E : Entry) : Entry := if E.mode = .bor then { E with fresh := false } else E

/-- A context with every fresh bit cleared. -/
def unfreshC (Γ : Ctx) : Ctx := fun v => (Γ v).map Entry.unfresh

section
variable (E : Entry)
@[simp] theorem Entry.unfresh_ty : E.unfresh.ty = E.ty := by unfold Entry.unfresh; split <;> rfl
@[simp] theorem Entry.unfresh_mode : E.unfresh.mode = E.mode := by unfold Entry.unfresh; split <;> rfl
@[simp] theorem Entry.unfresh_live : E.unfresh.live = E.live := by unfold Entry.unfresh; split <;> rfl
@[simp] theorem Entry.unfresh_path : E.unfresh.path = E.path := by unfold Entry.unfresh; split <;> rfl
@[simp] theorem Entry.unfresh_held : E.unfresh.held = E.held := by unfold Entry.unfresh; split <;> rfl
@[simp] theorem Entry.unfresh_dtor : E.unfresh.dtor = E.dtor := by unfold Entry.unfresh; split <;> rfl
@[simp] theorem Entry.unfresh_dbind : E.unfresh.dbind = E.dbind := by unfold Entry.unfresh; split <;> rfl
@[simp] theorem Entry.unfresh_vdeps : E.unfresh.vdeps = E.vdeps := by
  simp [Entry.vdeps]
end

theorem unfreshC_some {Γ : Ctx} {v : Var} {E : Entry} (h : Γ v = some E) : unfreshC Γ v = some E.unfresh := by
  simp [unfreshC, h]

theorem unfreshC_inv {Γ : Ctx} {v : Var} {E : Entry} (h : unfreshC Γ v = some E) :
    ∃ E0, Γ v = some E0 ∧ E = E0.unfresh := by
  simp only [unfreshC, Option.map_eq_some_iff] at h
  obtain ⟨E0, h0, rfl⟩ := h; exact ⟨E0, h0, rfl⟩

@[simp] theorem unfreshC_none {Γ : Ctx} {v : Var} : unfreshC Γ v = none ↔ Γ v = none := by
  simp [unfreshC]

/-- Clearing an entry's fresh bit weakens it. -/
theorem EntryWeaker.unfresh (E : Entry) : EntryWeaker E E.unfresh := by
  unfold Entry.unfresh
  split
  · rename_i hm
    refine ⟨rfl, rfl, fun hf => ?_, fun h => ⟨h, fun _ => List.Subset.refl _, List.Subset.refl _⟩,
      fun h => ⟨h, List.Subset.refl _⟩, (by simp_all), (fun _ => by simp_all), fun _ _ _ _ _ => Iff.rfl,
      fun _ _ _ h => (by cases h),
      fun _ _ hhf => by heldfresh_ew⟩
    rcases hf with h | ⟨b, h, _⟩ <;> rw [hm] at h <;> cases h
  · exact EntryWeaker.refl E

/-- No binding of a cleared context is fresh. -/
theorem unfreshC_not_fresh {Γ : Ctx} {v : Var} {E : Entry} (h : unfreshC Γ v = some E) (hm : E.mode = .bor) :
    E.fresh = false := by
  obtain ⟨E0, _, rfl⟩ := unfreshC_inv h
  simp at hm; simp [Entry.unfresh, hm]

/-- **A cleared context is `FreshOK`, vacuously.** -/
theorem freshOK_unfreshC (Γ : Ctx) : FreshOK (unfreshC Γ) := by
  intro v E h _ _ hm hf
  rw [unfreshC_not_fresh h hm] at hf; cases hf

theorem CtxWF.unfresh {Γ : Ctx} (h : CtxWF Γ) : CtxWF (unfreshC Γ) := by
  refine ⟨fun v E hv hl hk r hr => ?_, fun v E hv hd ho hk d hd' hn => ?_, fun v E hv hd => ?_,
    fun v E hv hd => ?_⟩
  · obtain ⟨E0, h0, rfl⟩ := unfreshC_inv hv
    obtain ⟨Er, hr', hm⟩ := h.live v E0 h0 (by simpa using hl) (by simpa using hk) r (by simpa using hr)
    exact ⟨Er.unfresh, unfreshC_some hr', by simpa using hm⟩
  · obtain ⟨E0, h0, rfl⟩ := unfreshC_inv hv
    obtain ⟨Er, hr', hm⟩ := h.dtor v E0 h0 (by simpa using hd) (by simpa using ho) (by simpa using hk) d
      (by simpa using hd') hn
    exact ⟨Er.unfresh, unfreshC_some hr', by simpa using hm⟩
  · obtain ⟨E0, h0, rfl⟩ := unfreshC_inv hv
    simpa using h.arm v E0 h0 (by simpa using hd)
  · obtain ⟨E0, h0, rfl⟩ := unfreshC_inv hv
    simpa using h.view v E0 h0 (by simpa using hd)

theorem NameWF.unfresh {Γ : Ctx} (h : NameWF Γ) : NameWF (unfreshC Γ) := by
  intro v E hv hl hk d hd b t hkd
  obtain ⟨E0, h0, rfl⟩ := unfreshC_inv hv
  obtain ⟨Er, hr, hrest⟩ := h v E0 h0 (by simpa using hl) (by simpa using hk) d (by simpa using hd) b t hkd
  exact ⟨Er.unfresh, unfreshC_some hr, by simpa using hrest⟩

/-- **Clearing every fresh bit is a weakening.** -/
theorem weaker_unfreshC {Γ : Ctx} (hw : CtxWF Γ) (hn : NameWF Γ) : Weaker Γ (unfreshC Γ) := by
  refine ⟨fun v => ⟨unfreshC_none.symm, fun E E' h1 h2 => ?_⟩, hw.unfresh, hn.unfresh⟩
  rw [unfreshC_some h1] at h2; cases h2; exact EntryWeaker.unfresh E

/-- **... that keeps what `panic` asks to keep**: every binding, with its mode
    and type, and every fixed entry as it was. -/
theorem unfreshC_panic (Γ : Ctx) :
    (∀ v, (Γ v).isSome = (unfreshC Γ v).isSome) ∧
    (∀ v E, unfreshC Γ v = some E → ∃ E0, Γ v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
      (E0.fixed → E = E0)) := by
  refine ⟨fun v => by cases h : Γ v <;> simp [unfreshC, h], fun v E h => ?_⟩
  obtain ⟨E0, h0, rfl⟩ := unfreshC_inv h
  exact ⟨E0, h0, by simp, by simp, (EntryWeaker.unfresh E0).fixed⟩


/-- **A context with no fresh borrow is `FreshOK`**: the premise `panic`,
    `exit`, `loop` and a scope's end ask holds of every context in which the
    bit was never set. -/
theorem freshOK_of_noFresh {Γ : Ctx} (h : ∀ v E, Γ v = some E → E.mode = .bor → E.fresh = false) :
    FreshOK Γ := by
  intro v E hv _ _ hm hf
  rw [h v E hv hm] at hf; cases hf

/-- **`EntryWeaker.fresh` holds whenever the weaker entry is not fresh.** -/
theorem EntryWeaker.fresh_of_not {E E' : Entry} (h : E'.fresh = false) :
    E'.live = true → E'.ty ≠ .int → E'.mode = .bor → E'.fresh = true → E.fresh = true ∧ E'.path ⊆ E.path :=
  fun _ _ _ hf => absurd (h ▸ hf) Bool.false_ne_true

/-- **A borrow with the bit off asks nothing of its source.** -/
theorem RhsT.borrow_unfresh {Γ : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .vec t) :
    RhsT Γ F (.borrow y) ⟨E.ty, .bor, true, derive y E .self, E.held, false, false, false, false⟩ Γ :=
  RhsT.borrow hy hl ht (fun h => by cases h)

/-- **Nor does an element borrow.** -/
theorem RhsT.at_unfresh {Γ : Ctx} {F : List Var} {y : Var} {i : Expr} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .vec t) (hi : ExprT Γ i) :
    RhsT Γ F (.at y i) { elemE y E t with fresh := false } Γ :=
  RhsT.at hy hl ht hi (fun h => by cases h)

/-- **The result side** (Agora #909, design (e)): any typing of a source
    statement from a well-formed context still holds when its result has
    every fresh bit cleared, a context that is `FreshOK` vacuously.  This is
    a weakening of the result, not a translation of derivations: see the
    module comment for what the per-premise lemmas above add. -/
theorem StmtT.unfresh {P : Prog} (hP : ProgOK P) {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {s : Stmt}
    (ht : StmtT P ξ Γ F s Δ) (hsrc : s.src = true) (hw : CtxWF Γ) (hn : NameWF Γ) :
    StmtT P ξ Γ F s (unfreshC Δ) ∧ FreshOK (unfreshC Δ) :=
  ⟨StmtT.weakenOut hw hn ht (Or.inr (weaker_unfreshC (ht.wf hP hw) (ht.names hP hsrc hn))),
    freshOK_unfreshC Δ⟩

end A2
