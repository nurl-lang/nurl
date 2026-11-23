import A2.CapClause
import A2.Basic

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

/-- The packages in `V` capture `w` only `.inp`. -/
def ValCapsInp (V : Val) (w : Var) : Prop :=
  ∀ fs te ms e cs, Sub (.pkg fs te ms e cs) V → ∀ q ∈ cs, q.1 = w → q.2.1 = .inp

/-- The store part of `HeldCapsInp`: every package in a slot's value that
    captures `w` does so `.inp`. -/
def CapsInpAt (m : Mem) (w : Var) : Prop :=
  ∀ x o V fs te ms e cs, m.st x = some ⟨o, some V⟩ → Sub (.pkg fs te ms e cs) V →
    ∀ q ∈ cs, q.1 = w → q.2.1 = .inp

theorem CapsInpAt.slot {m : Mem} {w : Var} (h : CapsInpAt m w) {x : Var} {o : Bool} {V : Val}
    (hx : m.st x = some ⟨o, some V⟩) : ValCapsInp V w :=
  fun fs te ms e cs hs => h x o V fs te ms e cs hx hs

theorem capsInpAt_of_slots {m : Mem} {w : Var}
    (h : ∀ x o V, m.st x = some ⟨o, some V⟩ → ValCapsInp V w) : CapsInpAt m w :=
  fun x o V fs te ms e cs hx hs => h x o V hx fs te ms e cs hs

/-- `HeldCapsInp` is its premises on the held anchor and `CapsInpAt` of its
    root. -/
theorem heldCapsInp_iff {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} :
    HeldCapsInp m Γ F s ↔
      ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine →
      ∀ d ∈ E.vdeps, d.kind.bound = .none → HeldAnch E d → d.root ∉ F → CapsInpAt m d.root :=
  Iff.rfl

/-- `HeldCapsInp` from `CapsInpAt` of every root it asks about. -/
theorem HeldCapsInp.of_caps {m m' : Mem} {Γ : Ctx} {F : List Var} {s : Stmt}
    (h : HeldCapsInp m Γ F s) (hc : ∀ w, CapsInpAt m w → CapsInpAt m' w) : HeldCapsInp m' Γ F s :=
  heldCapsInp_iff.mpr fun p E hp hm hps d hd hb hh hF => hc _ (heldCapsInp_iff.mp h p E hp hm hps d hd hb hh hF)

/-! ### The store operations -/

theorem CapsInpAt.set {m : Mem} {w : Var} (h : CapsInpAt m w) {x : Var} {o : Bool} {v : Option Val}
    (hv : ∀ V, v = some V → ValCapsInp V w) : CapsInpAt (m.set x ⟨o, v⟩) w := by
  refine capsInpAt_of_slots fun y o' V hy => ?_
  by_cases hyx : y = x
  · subst hyx; simp at hy; obtain ⟨_, rfl⟩ := hy; exact hv V rfl
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

/-- A slot emptied of its value: no premise. -/
theorem CapsInpAt.set_none {m : Mem} {w : Var} (h : CapsInpAt m w) (x : Var) (o : Bool) :
    CapsInpAt (m.set x ⟨o, none⟩) w :=
  h.set (fun _ e => by cases e)

theorem CapsInpAt.remove {m : Mem} {w : Var} (h : CapsInpAt m w) (x : Var) : CapsInpAt (m.remove x) w := by
  refine capsInpAt_of_slots fun y o' V hy => ?_
  by_cases hyx : y = x
  · subst hyx; simp at hy
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

theorem CapsInpAt.of_st {m m' : Mem} {w : Var} (h : CapsInpAt m w) (hst : m'.st = m.st) :
    CapsInpAt m' w :=
  capsInpAt_of_slots fun y o V hy => h.slot (by rw [← hst]; exact hy)

/-- The slots of one store, the blocks of another: the clause reads no block. -/
theorem CapsInpAt.withBlk {m m' : Mem} {w : Var} (h : CapsInpAt m w) (hst : m'.st = m.st) :
    CapsInpAt m' w :=
  h.of_st hst

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

/-- The values `BindParams` writes are the arguments' values, an `in`
    argument's lent: they capture `w` as the store did. -/
theorem BindParams.capsInp {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    {w : Var} (hb : BindParams m ps as base i m') (h : CapsInpAt m w) : CapsInpAt m' w := by
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

/-- A lock scope's end gives `x`'s value back to the block, or drops it:
    either way the slot goes, and no slot gains a value. -/
theorem Release.capsInp {m m' : Mem} {k : Nat} {t : Ty} {x : Var} {w : Var}
    (hrl : Release m k t x m') (h : CapsInpAt m w) : CapsInpAt m' w := by
  cases hrl with
  | put _ _ _ => exact (h.withBlk rfl).remove _
  | drop _ _ _ _ => exact (h.of_st rfl).remove _

end A2
