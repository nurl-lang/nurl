import A2.CapClause
import A2.Basic
import A2.Steps

/-! A2 — AGORA-969 (AGORA-963 step 3, the store half): **the store part of
the closure-capture clause, kept by the store operations a step makes.**

`HeldCapsInp` (CapClause.lean) asks, of every held anchor's root `w` that is
not lent out, that no package in the store captures `w` other than `.inp`.
Its store part is `CapsInpAt m w`, and `HeldCapsInp` is restated through it
(`heldCapsInp_iff`). The lemmas here keep `CapsInpAt` across `Mem.set` of a
value whose packages capture `w` only `.inp`, `Mem.remove`, a store with the
same slots (`of_st`, `withBlk`), `BindParams` and `Release`, as
`MemCodes.set` / `remove` / `of_st` / `withBlk` / `BindParams.codes` /
`Release.codes` keep `MemCodes` (Codes.lean). The step-level preservation is
AGORA-963's (claude-expert). By claude-accurate. -/

namespace A2

theorem CapsInpAt.slot {m : Mem} {w : Var} (h : CapsInpAt m w) {x : Var} {o : Bool} {V : Val}
    (hx : m.st x = some ⟨o, some V⟩) : ValCapsInp V w :=
  h.1 x o V hx

theorem CapsInpAt.pay {m : Mem} {w : Var} (h : CapsInpAt m w) {k : Nat} {bl : Blk} {V : Val}
    (hk : m.blk k = some bl) (hp : bl.pay = some V) : ValCapsInp V w :=
  h.2 k bl V hk hp

/-- `HeldCapsInp` is its premises on the held anchor and `LiveCaps` of its
    root. -/
theorem heldCapsInp_iff {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} :
    HeldCapsInp m Γ F s ↔
      ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine →
      ∀ d ∈ E.vdeps, d.kind.bound = .none → HeldAnch E d → d.root ∉ F → LiveCaps m Γ d.root :=
  Iff.rfl

/-- `HeldCapsInp` from `LiveCaps` of every root it asks about. -/
theorem HeldCapsInp.of_caps {m m' : Mem} {Γ : Ctx} {F : List Var} {s : Stmt}
    (h : HeldCapsInp m Γ F s) (hc : ∀ w, LiveCaps m Γ w → LiveCaps m' Γ w) : HeldCapsInp m' Γ F s :=
  fun p E hp hm hps d hd hb hh hF => hc _ (h p E hp hm hps d hd hb hh hF)

/-- ... carried to a step's result where the borrowed parameters outside the
    new running scopes are old ones, outside the old scopes, and the store
    keeps every root's clause. -/
theorem HeldCapsInp.step_of {m m' : Mem} {Γ Γ' : Ctx} {F : List Var} {s s' : Stmt}
    (h : HeldCapsInp m Γ F s)
    (hrb : ∀ p E, Γ' p = some E → E.mode = .rootb → p ∉ s'.spine → Γ p = some E ∧ p ∉ s.spine)
    (hc : ∀ w, LiveCaps m Γ w → LiveCaps m' Γ' w) : HeldCapsInp m' Γ' F s' :=
  fun p E hp hm hps d hd hb hh hF => by
    obtain ⟨h0, hps0⟩ := hrb p E hp hm hps
    exact hc _ (h p E h0 hm hps0 d hd hb hh hF)

/-! ### The store operations -/

theorem CapsInpAt.set {m : Mem} {w : Var} (h : CapsInpAt m w) {x : Var} {o : Bool} {v : Option Val}
    (hv : ∀ V, v = some V → ValCapsInp V w) : CapsInpAt (m.set x ⟨o, v⟩) w := by
  refine ⟨fun y o' V hy => ?_, fun k bl V hk hp => h.pay hk hp⟩
  by_cases hyx : y = x
  · subst hyx; simp at hy; obtain ⟨_, rfl⟩ := hy; exact hv V rfl
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

/-- A slot emptied of its value: no premise. -/
theorem CapsInpAt.set_none {m : Mem} {w : Var} (h : CapsInpAt m w) (x : Var) (o : Bool) :
    CapsInpAt (m.set x ⟨o, none⟩) w :=
  h.set (fun _ e => by cases e)

theorem CapsInpAt.remove {m : Mem} {w : Var} (h : CapsInpAt m w) (x : Var) : CapsInpAt (m.remove x) w := by
  refine ⟨fun y o' V hy => ?_, fun k bl V hk hp => h.pay hk hp⟩
  by_cases hyx : y = x
  · subst hyx; simp at hy
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

/-- The slots of one store, blocks that are some of the other's. -/
theorem CapsInpAt.withBlk {m m' : Mem} {w : Var} (h : CapsInpAt m w) (hst : m'.st = m.st)
    (hb : ∀ k bl V, m'.blk k = some bl → bl.pay = some V → ValCapsInp V w) : CapsInpAt m' w :=
  ⟨fun x o V hx => h.slot (hst ▸ hx), hb⟩

/-- A block updated to a payload whose packages are clean. -/
theorem CapsInpAt.updBlk {m : Mem} {w : Var} (h : CapsInpAt m w) {k : Nat} {bl : Blk}
    (hbl : ∀ V, bl.pay = some V → ValCapsInp V w) {m' : Mem} (hst : m'.st = m.st)
    (hb : m'.blk = upd m.blk k (some bl)) : CapsInpAt m' w := by
  refine h.withBlk hst fun k' bl' V hk hp => ?_
  rw [hb] at hk
  by_cases hkk : k' = k
  · subst hkk; simp at hk; subst hk; exact hbl V hp
  · simp [upd_ne _ _ hkk] at hk; exact h.pay hk hp

/-! ### Lent values -/

/-- A package inside a lent value is a package of the value, with the same
    captures (its environment lent). -/
theorem sub_pkg_lendOf {fs : List Nat} {te : Ty} {ms : List Nat} {e : Val}
    {cs : List (Var × PMode × Ty)} :
    ∀ {V : Val}, Sub (.pkg fs te ms e cs) (lendOf V) → ∃ e', Sub (.pkg fs te ms e' cs) V
  | .int _, h => ⟨e, h⟩
  | .href _, h => ⟨e, h⟩
  | .view _ _ _, h => ⟨e, h⟩
  | .arc _ _, h => ⟨e, h⟩
  | .lk _, h => ⟨e, h⟩
  | .cell _, h => ⟨e, h⟩
  | .node _ _ _ _, h => by simp only [lendOf] at h; cases h
  | .pair v w, h => by
    simp only [lendOf] at h
    cases h with
    | fst h =>
      obtain ⟨e', h'⟩ := sub_pkg_lendOf h
      exact ⟨e', .fst h'⟩
    | snd h =>
      obtain ⟨e', h'⟩ := sub_pkg_lendOf h
      exact ⟨e', .snd h'⟩
  | .inl v, h => by
    simp only [lendOf] at h
    cases h with
    | inl h =>
      obtain ⟨e', h'⟩ := sub_pkg_lendOf h
      exact ⟨e', .inl h'⟩
  | .inr v, h => by
    simp only [lendOf] at h
    cases h with
    | inr h =>
      obtain ⟨e', h'⟩ := sub_pkg_lendOf h
      exact ⟨e', .inr h'⟩
  | .pkg fs' te' ms' v cs', h => by
    simp only [lendOf] at h
    cases h with
    | refl => exact ⟨v, .refl _⟩
    | pkg h =>
      obtain ⟨e', h'⟩ := sub_pkg_lendOf h
      exact ⟨e', .pkg h'⟩

theorem ValCapsInp.lend {V : Val} {w : Var} (h : ValCapsInp V w) : ValCapsInp (lendOf V) w := by
  intro fs te ms e cs hs q hq hqw
  obtain ⟨e', hs'⟩ := sub_pkg_lendOf hs
  exact h fs te ms e' cs hs' q hq hqw

/-! ### Binding a call's parameters, and a lock scope's end -/

/-- The slot half of `CapsInpAt`. -/
def SlotsCaps (m : Mem) (w : Var) : Prop := ∀ x o V, m.st x = some ⟨o, some V⟩ → ValCapsInp V w

theorem SlotsCaps.slot {m : Mem} {w : Var} (h : SlotsCaps m w) {x : Var} {o : Bool} {V : Val}
    (hx : m.st x = some ⟨o, some V⟩) : ValCapsInp V w := h x o V hx

theorem SlotsCaps.set {m : Mem} {w : Var} (h : SlotsCaps m w) {x : Var} {o : Bool} {v : Option Val}
    (hv : ∀ V, v = some V → ValCapsInp V w) : SlotsCaps (m.set x ⟨o, v⟩) w := by
  intro y o' V hy
  by_cases hyx : y = x
  · subst hyx; simp at hy; obtain ⟨_, rfl⟩ := hy; exact hv V rfl
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

theorem SlotsCaps.set_none {m : Mem} {w : Var} (h : SlotsCaps m w) (x : Var) (o : Bool) :
    SlotsCaps (m.set x ⟨o, none⟩) w :=
  h.set (fun _ e => by cases e)

theorem BindParams.slotsCaps {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    {w : Var} (hb : BindParams m ps as base i m') (h : SlotsCaps m w) : SlotsCaps m' w := by
  induction hb with
  | nil => exact h
  | @inp m _ _ _ a _ _ _ sl v ha hl _ ih =>
    refine ih (h.set (fun V e => ?_))
    cases e
    obtain ⟨o, val⟩ := sl
    cases o <;> cases val <;> simp [lendSlot] at hl
    · subst hl; exact h.slot ha
    · subst hl; exact (h.slot ha).lend
  | sink ha _ ih => exact ih ((h.set_none _ _).set (fun V e => by cases e; exact h.slot ha))
  | inout _ ih => exact ih h

/-- ... and the blocks stay as they were. -/
theorem BindParams.capsInp {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    {w : Var} (hb : BindParams m ps as base i m') (h : CapsInpAt m w) : CapsInpAt m' w :=
  ⟨hb.slotsCaps h.1, fun k bl V hk hp => h.2 k bl V (hb.blk ▸ hk) hp⟩

/-- A lock scope's end gives `x`'s value back to the block, or drops it:
    the value goes from the slot into the block, or nowhere. -/
theorem Release.capsInp {m m' : Mem} {k : Nat} {t : Ty} {x : Var} {w : Var}
    (hrl : Release m k t x m') (h : CapsInpAt m w) : CapsInpAt m' w := by
  cases hrl with
  | @put o v hx _ _ _ =>
    exact (h.updBlk (bl := ⟨t, .lock, some v⟩) (m' := { m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) })
      (fun V e => by cases e; exact h.slot hx) rfl rfl).remove _
  | drop _ _ _ _ => exact (h.of_st rfl).remove _

end A2
