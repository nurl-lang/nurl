import A2.TypingFacts
import A2.NameWf
import A2.Wf

/-! # Agora #909: no new premise removes a typing

Design (e) added `Entry.fresh` and premises that read it: the fresh bit of
`RhsT.borrow` / `RhsT.at` (`FreshSrc` when set), `EntryWeaker.fresh`,
`FreshOK` after `panic` / `exit` / `loop` and at a scope's end, and `editB`'s
`edit false` (a fresh borrow).  None of them removes a typing: each is met by
choosing the fresh bit off.  The rules' own bits are the rule's choice; for
the rest, clearing every fresh bit of a context (`unfreshC`) is a weakening
(`weaker_unfreshC`) to a context that is `FreshOK` vacuously
(`freshOK_unfreshC`) and keeps every binding, mode, type and fixed entry
(`unfreshC_panic`).  So every typing still holds with its fresh bits off
(`StmtT.unfresh`): what the walk typed before design (e), it types now. -/

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
      fun _ _ _ h => by cases h⟩
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

/-- **No new premise removes a typing** (Agora #909, design (e)): any typing
    of a source statement from a well-formed context still holds when its
    result has every fresh bit cleared, a context that is `FreshOK`
    vacuously.  With the rules' own bits (`borrow`, `at`) chosen off, the
    fresh bits never set, and every premise that reads them holds: what was
    typed before is typed now. -/
theorem StmtT.unfresh {P : Prog} (hP : ProgOK P) {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {s : Stmt}
    (ht : StmtT P ξ Γ F s Δ) (hsrc : s.src = true) (hw : CtxWF Γ) (hn : NameWF Γ) :
    StmtT P ξ Γ F s (unfreshC Δ) ∧ FreshOK (unfreshC Δ) :=
  ⟨StmtT.weakenOut hw hn ht (Or.inr (weaker_unfreshC (ht.wf hP hw) (ht.names hP hsrc hn))),
    freshOK_unfreshC Δ⟩

end A2
