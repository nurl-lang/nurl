module

@[expose] public section

/-!
# Duplicate-free dependency lists (AGORA-988)

A1's and A2's typing rules build dependency lists by concatenation: a push
appends what the pushed value depends on, a call appends what its arguments
hold, in every kind. The checkers compute those contexts exactly, so a
dependency already listed is listed again. github#2242's review showed the
growth is geometric: a slice read from a `Vec` of slices and pushed back,
15 times over, leaves 14,348,907 entries for one dependency.

Every clause of `Weaker` is stated by membership, so an entry with the
duplicates dropped from its lists is weaker than the entry it came from
(`EntryWeaker.dedup2` for A2, `EntryWeaker.dedup1` for A1). The checkers
drop them where a push or a call makes them, and justify it with one `sub`
step: on the context the call's continuation starts from (`C.settleL2`,
`C.settleL1`), or on the context a push ends in (`C.settleOutL2`,
`C.settleOutL1`), once the checker has decided that the result is well
formed. No typing rule changes.

This file holds the parts that know nothing of A1 or A2: `dedupL`, which
keeps each element at its first occurrence, and the tables (`tblOf`,
`ctxOfTbl`) a checker reads a context into once, over its finite domain.
-/

namespace C

/-- `l` with each element kept at its first occurrence. -/
def dedupL {α : Type} [DecidableEq α] : List α → List α
  | [] => []
  | a :: l => a :: (dedupL l).filter (fun b => !decide (b = a))

theorem mem_dedupL {α : Type} [DecidableEq α] {a : α} : ∀ {l : List α}, a ∈ dedupL l ↔ a ∈ l
  | [] => by simp [dedupL]
  | b :: l => by
    have ih := @mem_dedupL α _ a l
    simp only [dedupL, List.mem_cons, List.mem_filter, ih, Bool.not_eq_true', decide_eq_false_iff_not]
    constructor
    · rintro (h | ⟨h, _⟩)
      · exact Or.inl h
      · exact Or.inr h
    · rintro (h | h)
      · exact Or.inl h
      · by_cases e : a = b
        · exact Or.inl e
        · exact Or.inr ⟨h, e⟩

theorem dedupL_sub {α : Type} [DecidableEq α] {l : List α} : dedupL l ⊆ l := fun _ h => mem_dedupL.mp h

theorem sub_dedupL {α : Type} [DecidableEq α] {l : List α} : l ⊆ dedupL l := fun _ h => mem_dedupL.mpr h

/-- A context over the finite domain `D`, read once into a table: each slot
    of `D` with what `g` gives it. A checker builds it once and passes on
    `ctxOfTbl` of it, so a later read is one scan of `D` and never replays
    how `g` was computed (as `joinTbl`: contexts are functions, and one
    built by a chain of calls and kills recomputes the chain on every
    read). It is a `List`, so the compiler cannot turn it back into a
    function that rebuilds it on every read. -/
def tblOf {β : Type} (D : List Nat) (g : Nat → Option β) : List (Nat × Option β) :=
  D.map fun v => (v, g v)

/-- The context a table gives: the listed entry, none for a slot it does not
    list. -/
def ctxOfTbl {β : Type} (L : List (Nat × Option β)) : Nat → Option β := fun v =>
  match L.lookup v with
  | some e => e
  | none => none

theorem ctxOfTbl_tblOf {β : Type} (g : Nat → Option β) (v : Nat) :
    ∀ D : List Nat, ctxOfTbl (tblOf D g) v = if v ∈ D then g v else none
  | [] => by simp [ctxOfTbl, tblOf]
  | a :: D => by
    have ih := ctxOfTbl_tblOf g v D
    by_cases h : v = a
    · subst h; simp [ctxOfTbl, tblOf]
    · have hb : (v == a) = false := by simpa using h
      simp only [ctxOfTbl, tblOf, List.map_cons, List.lookup_cons, hb] at ih ⊢
      simp only [List.mem_cons, h, false_or]
      exact ih

/-- A context that names nothing outside `D`, read into a table over `D`,
    is itself. -/
theorem ctxOfTbl_self {β : Type} {D : List Nat} {Γ : Nat → Option β} (hs : ∀ v, v ∉ D → Γ v = none) :
    ctxOfTbl (tblOf D Γ) = Γ := by
  funext v
  rw [ctxOfTbl_tblOf]
  split
  · rfl
  · rename_i h; exact (hs v h).symm

/-- `Γ`'s entries of `vs` changed by `f`, the rest as they are. -/
def mapAt {β : Type} (f : β → β) (vs : List Nat) (Γ : Nat → Option β) : Nat → Option β := fun v =>
  if v ∈ vs then (Γ v).map f else Γ v

/-- A read of the table of `mapAt` is the context's own entry, or `f` of it. -/
theorem ctxOfTbl_mapAt {β : Type} {D : List Nat} {Γ : Nat → Option β} (hs : ∀ v, v ∉ D → Γ v = none)
    (f : β → β) (vs : List Nat) (v : Nat) :
    ctxOfTbl (tblOf D (mapAt f vs Γ)) v = Γ v ∨ ctxOfTbl (tblOf D (mapAt f vs Γ)) v = (Γ v).map f := by
  rw [ctxOfTbl_tblOf]
  split
  · unfold mapAt; split
    · exact Or.inr rfl
    · exact Or.inl rfl
  · rename_i h; exact Or.inl (hs v h).symm

/-- The table names nothing outside `D`. -/
theorem ctxOfTbl_none {β : Type} {D : List Nat} (g : Nat → Option β) {v : Nat} (h : v ∉ D) :
    ctxOfTbl (tblOf D g) v = none := by
  rw [ctxOfTbl_tblOf]; simp [h]

end C
