import A2.Unfresh

/-! # Agora #916: each new premise holds with the held-freshness bit off

AGORA-916 added `Entry.heldFresh` and premises that read it:
- the bit of `RhsT.view` (`HeldSrc` when set);
- `EntryWeaker.heldFresh`.

Each is met by choosing the bit off. That is what this file proves, premise by premise:
- `RhsT.view_unheld`: the rule with the bit off asks nothing of the source.
- `EntryWeaker.heldFresh_of_not`: the weakening premise holds when the weaker entry's bit is off.
- `weaker_unheldC`: clearing every held-freshness bit is a weakening.
- `StmtT.unheld`: the result side: any typing still holds with its result's bits cleared.

And it proves the negative side (claude-formal's condition 3): what a borrowed parameter holds is its
caller's memory, and no rule makes a view of one held-fresh (`heldSrc_not_rootb`, `view_rootb_not_heldFresh`).

What is NOT proven here is a translation from the typing relation as it stood before AGORA-916. The claim
that every program it typed is typed now rests on the lemmas above: an old derivation is a new one with
every bit off, and each new premise of it is one of the cases above. -/

namespace A2

/-- An entry with its held-freshness bit cleared: only a borrow carries one
    that matters (a fixed entry is never a borrow, and stays as it is). -/
def Entry.unheld (E : Entry) : Entry := if E.mode = .bor then { E with heldFresh := false } else E

/-- A context with every held-freshness bit cleared. -/
def unheldC (Γ : Ctx) : Ctx := fun v => (Γ v).map Entry.unheld

section
variable (E : Entry)
@[simp] theorem Entry.unheld_ty : E.unheld.ty = E.ty := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_mode : E.unheld.mode = E.mode := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_live : E.unheld.live = E.live := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_path : E.unheld.path = E.path := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_held : E.unheld.held = E.held := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_dtor : E.unheld.dtor = E.dtor := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_dbind : E.unheld.dbind = E.dbind := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_fresh : E.unheld.fresh = E.fresh := by unfold Entry.unheld; split <;> rfl
@[simp] theorem Entry.unheld_vdeps : E.unheld.vdeps = E.vdeps := by
  simp [Entry.vdeps]
end

theorem unheldC_some {Γ : Ctx} {v : Var} {E : Entry} (h : Γ v = some E) : unheldC Γ v = some E.unheld := by
  simp [unheldC, h]

theorem unheldC_inv {Γ : Ctx} {v : Var} {E : Entry} (h : unheldC Γ v = some E) :
    ∃ E0, Γ v = some E0 ∧ E = E0.unheld := by
  simp only [unheldC, Option.map_eq_some_iff] at h
  obtain ⟨E0, h0, rfl⟩ := h; exact ⟨E0, h0, rfl⟩

@[simp] theorem unheldC_none {Γ : Ctx} {v : Var} : unheldC Γ v = none ↔ Γ v = none := by
  simp [unheldC]

/-- No borrow of a cleared context is held-fresh. -/
theorem unheld_not_heldFresh (E : Entry) (hm : E.mode = .bor) : E.unheld.heldFresh = false := by
  simp [Entry.unheld, hm]

/-- **`EntryWeaker.heldFresh` holds whenever the weaker entry's bit is off.** -/
theorem EntryWeaker.heldFresh_of_not {E E' : Entry} (h : E'.heldFresh = false) :
    E'.ty ≠ .int → E'.mode = .bor → E'.heldFresh = true → E.heldFresh = true :=
  fun _ _ hf => absurd (h ▸ hf) Bool.false_ne_true

/-- Clearing an entry's held-freshness bit weakens it. -/
theorem EntryWeaker.unheld (E : Entry) : EntryWeaker E E.unheld := by
  unfold Entry.unheld
  split
  · rename_i hm
    refine ⟨rfl, rfl, fun hf => ?_, fun h => ⟨h, fun _ => List.Subset.refl _, List.Subset.refl _⟩,
      fun h => ⟨h, List.Subset.refl _⟩, rfl, (fun h => Or.inl h), fun _ _ _ _ _ => Iff.rfl,
      fun _ _ _ h => ⟨h, List.Subset.refl _⟩,
      EntryWeaker.heldFresh_of_not rfl⟩
    rcases hf with h | ⟨b, h, _⟩ <;> rw [hm] at h <;> cases h
  · exact EntryWeaker.refl E

theorem CtxWF.unheld {Γ : Ctx} (h : CtxWF Γ) : CtxWF (unheldC Γ) := by
  refine ⟨fun v E hv hl hk r hr => ?_, fun v E hv hd ho hk d hd' hn => ?_, fun v E hv hd => ?_,
    fun v E hv hd => ?_⟩
  · obtain ⟨E0, h0, rfl⟩ := unheldC_inv hv
    obtain ⟨Er, hr', hm⟩ := h.live v E0 h0 (by simpa using hl) (by simpa using hk) r (by simpa using hr)
    exact ⟨Er.unheld, unheldC_some hr', by simpa using hm⟩
  · obtain ⟨E0, h0, rfl⟩ := unheldC_inv hv
    obtain ⟨Er, hr', hm⟩ := h.dtor v E0 h0 (by simpa using hd) (by simpa using ho) (by simpa using hk) d
      (by simpa using hd') hn
    exact ⟨Er.unheld, unheldC_some hr', by simpa using hm⟩
  · obtain ⟨E0, h0, rfl⟩ := unheldC_inv hv
    simpa using h.arm v E0 h0 (by simpa using hd)
  · obtain ⟨E0, h0, rfl⟩ := unheldC_inv hv
    simpa using h.view v E0 h0 (by simpa using hd)

theorem NameWF.unheld {Γ : Ctx} (h : NameWF Γ) : NameWF (unheldC Γ) := by
  intro v E hv hl hk d hd b t hkd
  obtain ⟨E0, h0, rfl⟩ := unheldC_inv hv
  obtain ⟨Er, hr, hrest⟩ := h v E0 h0 (by simpa using hl) (by simpa using hk) d (by simpa using hd) b t hkd
  exact ⟨Er.unheld, unheldC_some hr, by simpa using hrest⟩

/-- **Clearing every held-freshness bit is a weakening.** -/
theorem weaker_unheldC {Γ : Ctx} (hw : CtxWF Γ) (hn : NameWF Γ) : Weaker Γ (unheldC Γ) := by
  refine ⟨fun v => ⟨unheldC_none.symm, fun E E' h1 h2 => ?_⟩, hw.unheld, hn.unheld⟩
  rw [unheldC_some h1] at h2; cases h2; exact EntryWeaker.unheld E

/-- **A view with the bit off asks nothing of its source.** -/
theorem RhsT.view_unheld {Γ : Ctx} {F : List Var} {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .vec t) (hv : t.holdsView = false) :
    RhsT Γ F (.view y) ⟨.slice t, .bor, true, derive y E .view, E.held, false, false, false, false⟩ Γ :=
  RhsT.view hy hl ht hv (fun h => by cases h) (fun h => by cases h)

/-- **The result side** (Agora #916): any typing of a source statement from a
    well-formed context still holds when its result has every held-freshness
    bit cleared.  This is a weakening of the result, not a translation of
    derivations: see the module comment for what the per-premise lemmas
    above add. -/
theorem StmtT.unheld {P : Prog} (hP : ProgOK P) {ξ : Exits} {Γ Δ : Ctx} {F : List Var} {s : Stmt}
    (ht : StmtT P ξ Γ F s Δ) (hsrc : s.src = true) (hw : CtxWF Γ) (hn : NameWF Γ) :
    StmtT P ξ Γ F s (unheldC Δ) :=
  StmtT.weakenOut hw hn ht (Or.inr (weaker_unheldC (ht.wf hP hw) (ht.names hP hsrc hn)))

/-! ### A witness: the rule fires -/

/-- **A held-fresh view**: a view of a local `Vec int` (an owner of a type that
    holds no views) may carry the bit; its `held` is the owner's, `[]`. -/
theorem heldFresh_view_witness {F : List Var} :
    RhsT (upd (fun _ => none) 0 (some ⟨.vec .int, .own, true, [], [], false, false, false, false⟩)) F
      (.view 0) ⟨.slice .int, .bor, true, [⟨0, .view⟩], [], false, false, false, true⟩
      (upd (fun _ => none) 0 (some ⟨.vec .int, .own, true, [], [], false, false, false, false⟩)) := by
  have h := RhsT.view (Γ := upd (fun _ => none) 0 (some ⟨.vec .int, .own, true, [], [], false, false, false, false⟩))
    (F := F) (y := 0) (E := ⟨.vec .int, .own, true, [], [], false, false, false, false⟩) (t := .int) (f := false)
    (h := true) (by simp [upd]) rfl rfl rfl (fun h => by cases h)
    (fun _ => ⟨⟨.vec .int, .own, true, [], [], false, false, false, false⟩, by simp [upd],
      Or.inl ⟨rfl, by simp [Ty.holdsView]⟩⟩)
  simpa [derive, Mode.isRoot, rootKind] using h

/-! ### The negative side: a borrowed parameter's holdings are its caller's -/

/-- **A borrowed parameter is no held-fresh source**: what it holds, in
    memory, is its caller's, which the callee cannot see. -/
theorem heldSrc_not_rootb {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E) (hm : E.mode = .rootb) :
    ¬ HeldSrc Γ y := by
  rintro ⟨E0, h0, hc⟩
  rw [hy] at h0; cases h0
  rcases hc with ⟨hos, _⟩ | ⟨hb, _, _⟩
  · rw [hm] at hos; cases hos
  · rw [hm] at hb; cases hb

/-- **... so no view of one is held-fresh.** -/
theorem view_rootb_not_heldFresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E Ev : Entry}
    (hy : Γ y = some E) (hm : E.mode = .rootb) (hr : RhsT Γ F (.view y) Ev Γ1) : Ev.heldFresh = false := by
  cases hr with
  | @view _ _ _ _ h hy' _ _ _ _ hh =>
    cases h with
    | false => rfl
    | true => exact absurd (hh rfl) (heldSrc_not_rootb hy hm)

/-- **Nor is a view of a borrow that is not itself held-fresh.** -/
theorem view_bor_not_heldFresh {Γ Γ1 : Ctx} {F : List Var} {y : Var} {E Ev : Entry}
    (hy : Γ y = some E) (hm : E.mode = .bor) (hf : E.heldFresh = false) (hr : RhsT Γ F (.view y) Ev Γ1) :
    Ev.heldFresh = false := by
  cases hr with
  | @view _ _ _ _ h hy' _ _ _ _ hh =>
    cases h with
    | false => rfl
    | true =>
      obtain ⟨E0, h0, hc⟩ := hh rfl
      rw [hy] at h0; cases h0
      rcases hc with ⟨hos, _⟩ | ⟨_, hf', _⟩
      · rw [hm] at hos; cases hos
      · rw [hf] at hf'; cases hf'

end A2
