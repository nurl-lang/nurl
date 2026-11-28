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

/-- A binary radix tree mapping `Nat` to `Option β`: `0` is at the root;
    `n > 0` branches on `n % 2` (`1` left, `0` right) with key `(n - 1) / 2`.
    Lookup and insert take `O(log n)` steps in the kernel (`Nat` division and
    mod are kernel primitives), rather than scanning a linear list. -/
inductive CtxT (β : Type) where
  | empty
  | node (val : Option β) (l r : CtxT β)

def CtxT.get {β : Type} : CtxT β → Nat → Option β
  | .empty, _ => none
  | .node val l r, n =>
    if n == 0 then val
    else if n % 2 == 1 then l.get ((n - 1) / 2)
    else r.get ((n - 1) / 2)

def CtxT.mkNode {β : Type} (val : Option β) (l r : CtxT β) : CtxT β :=
  match val, l, r with
  | none, .empty, .empty => .empty
  | _, _, _ => .node val l r

theorem CtxT.get_mkNode {β : Type} (val : Option β) (l r : CtxT β) (n : Nat) :
    (CtxT.mkNode val l r).get n = (CtxT.node val l r).get n := by
  unfold CtxT.mkNode
  split
  · simp only [CtxT.get]; split
    · rfl
    · split <;> rfl
  · rfl

def CtxT.setGo {β : Type} : Nat → CtxT β → Nat → Option β → CtxT β
  | 0, t, _, _ => t
  | fuel + 1, t, n, v =>
    if n == 0 then
      match t with
      | .empty => CtxT.mkNode v .empty .empty
      | .node _ l r => CtxT.mkNode v l r
    else if n % 2 == 1 then
      match t with
      | .empty =>
        match v with
        | none => .empty
        | some _ => CtxT.mkNode none (setGo fuel .empty ((n - 1) / 2) v) .empty
      | .node val l r => CtxT.mkNode val (setGo fuel l ((n - 1) / 2) v) r
    else
      match t with
      | .empty =>
        match v with
        | none => .empty
        | some _ => CtxT.mkNode none .empty (setGo fuel .empty ((n - 1) / 2) v)
      | .node val l r => CtxT.mkNode val l (setGo fuel r ((n - 1) / 2) v)

def CtxT.set {β : Type} (t : CtxT β) (n : Nat) (v : Option β) : CtxT β :=
  CtxT.setGo (n + 1) t n v

theorem CtxT.get_setGo {β : Type} : ∀ (fuel : Nat) (t : CtxT β) (n m : Nat) (v : Option β),
    n < fuel → (CtxT.setGo fuel t n v).get m = if m = n then v else t.get m
  | 0, _, _, _, _, h => by omega
  | fuel + 1, t, n, m, v, h => by
    unfold CtxT.setGo
    by_cases hn : n = 0
    · subst hn
      simp only [beq_self_eq_true, ↓reduceIte]
      cases t with
      | empty =>
        rw [CtxT.get_mkNode]
        by_cases hm : m = 0
        · subst hm; simp [CtxT.get]
        · have hm0 : (m == 0) = false := by simpa using hm
          simp only [CtxT.get, hm0, Bool.false_eq_true, ↓reduceIte, hm]
          split <;> rfl
      | node val l r =>
        rw [CtxT.get_mkNode]
        by_cases hm : m = 0
        · subst hm; simp [CtxT.get]
        · have hm0 : (m == 0) = false := by simpa using hm
          simp only [CtxT.get, hm0, Bool.false_eq_true, ↓reduceIte, hm]
    · have hn0 : (n == 0) = false := by simpa using hn
      simp only [hn0, Bool.false_eq_true, ↓reduceIte]
      have hlt : (n - 1) / 2 < fuel := by omega
      by_cases hnp : n % 2 = 1
      · have hnpb : (n % 2 == 1) = true := by simpa using hnp
        simp only [hnpb, ↓reduceIte]
        cases t with
        | empty =>
          cases v with
          | none =>
            simp only [CtxT.get]; split <;> rfl
          | some e =>
            rw [CtxT.get_mkNode]
            by_cases hm : m = 0
            · subst hm; simp [CtxT.get, Ne.symm hn]
            · have hm0 : (m == 0) = false := by simpa using hm
              by_cases hmp : m % 2 = 1
              · have hmpb : (m % 2 == 1) = true := by simpa using hmp
                simp only [CtxT.get, hm0, hmpb, Bool.false_eq_true, ↓reduceIte]
                rw [CtxT.get_setGo fuel .empty ((n - 1) / 2) ((m - 1) / 2) (some e) hlt]
                have heq : ((m - 1) / 2 = (n - 1) / 2) ↔ (m = n) := by omega
                simp [heq, CtxT.get]
              · have hmpb : (m % 2 == 1) = false := by simpa using hmp
                have hne : m ≠ n := by omega
                simp [CtxT.get, hm0, hmpb, hne]
        | node val l r =>
          rw [CtxT.get_mkNode]
          by_cases hm : m = 0
          · subst hm; simp [CtxT.get, Ne.symm hn]
          · have hm0 : (m == 0) = false := by simpa using hm
            by_cases hmp : m % 2 = 1
            · have hmpb : (m % 2 == 1) = true := by simpa using hmp
              simp only [CtxT.get, hm0, hmpb, Bool.false_eq_true, ↓reduceIte]
              rw [CtxT.get_setGo fuel l ((n - 1) / 2) ((m - 1) / 2) v hlt]
              have heq : ((m - 1) / 2 = (n - 1) / 2) ↔ (m = n) := by omega
              simp [heq]
            · have hmpb : (m % 2 == 1) = false := by simpa using hmp
              have hne : m ≠ n := by omega
              simp [CtxT.get, hm0, hmpb, hne]
      · have hnpb : (n % 2 == 1) = false := by simpa using hnp
        simp only [hnpb, Bool.false_eq_true, ↓reduceIte]
        cases t with
        | empty =>
          cases v with
          | none =>
            simp only [CtxT.get]; split <;> rfl
          | some e =>
            rw [CtxT.get_mkNode]
            by_cases hm : m = 0
            · subst hm; simp [CtxT.get, Ne.symm hn]
            · have hm0 : (m == 0) = false := by simpa using hm
              by_cases hmp : m % 2 = 1
              · have hmpb : (m % 2 == 1) = true := by simpa using hmp
                have hne : m ≠ n := by omega
                simp [CtxT.get, hm0, hmpb, hne]
              · have hmpb : (m % 2 == 1) = false := by simpa using hmp
                simp only [CtxT.get, hm0, hmpb, Bool.false_eq_true, ↓reduceIte]
                rw [CtxT.get_setGo fuel .empty ((n - 1) / 2) ((m - 1) / 2) (some e) hlt]
                have heq : ((m - 1) / 2 = (n - 1) / 2) ↔ (m = n) := by omega
                simp [heq, CtxT.get]
        | node val l r =>
          rw [CtxT.get_mkNode]
          by_cases hm : m = 0
          · subst hm; simp [CtxT.get, Ne.symm hn]
          · have hm0 : (m == 0) = false := by simpa using hm
            by_cases hmp : m % 2 = 1
            · have hmpb : (m % 2 == 1) = true := by simpa using hmp
              have hne : m ≠ n := by omega
              simp [CtxT.get, hm0, hmpb, hne]
            · have hmpb : (m % 2 == 1) = false := by simpa using hmp
              simp only [CtxT.get, hm0, hmpb, Bool.false_eq_true, ↓reduceIte]
              rw [CtxT.get_setGo fuel r ((n - 1) / 2) ((m - 1) / 2) v hlt]
              have heq : ((m - 1) / 2 = (n - 1) / 2) ↔ (m = n) := by omega
              simp [heq]

theorem CtxT.get_set {β : Type} (t : CtxT β) (n m : Nat) (v : Option β) :
    (t.set n v).get m = if m = n then v else t.get m :=
  CtxT.get_setGo (n + 1) t n m v (Nat.lt_succ_self n)

def CtxT.map {β : Type} (f : β → β) : CtxT β → CtxT β
  | .empty => .empty
  | .node val l r => .node (val.map f) (l.map f) (r.map f)

theorem CtxT.get_map {β : Type} (f : β → β) : ∀ (t : CtxT β) (n : Nat),
    (t.map f).get n = (t.get n).map f
  | .empty, _ => rfl
  | .node val l r, n => by
    simp only [CtxT.map, CtxT.get]
    split
    · rfl
    · split
      · exact CtxT.get_map f l _
      · exact CtxT.get_map f r _

def CtxT.allNone {β : Type} : CtxT β → Bool
  | .empty => true
  | .node val l r => val.isNone && l.allNone && r.allNone

theorem CtxT.allNone_sound {β : Type} : ∀ {t : CtxT β}, t.allNone = true → ∀ v, t.get v = none
  | .empty, _, _ => rfl
  | .node val l r, h, v => by
    simp only [CtxT.allNone, Bool.and_eq_true, Option.isNone_iff_eq_none] at h
    unfold CtxT.get
    split
    · exact h.1.1
    · split
      · exact CtxT.allNone_sound h.1.2 _
      · exact CtxT.allNone_sound h.2 _

def CtxT.eq {β : Type} [BEq β] : CtxT β → CtxT β → Bool
  | .empty, .empty => true
  | .empty, t => t.allNone
  | t, .empty => t.allNone
  | .node va la ra, .node vb lb rb => (va == vb) && la.eq lb && ra.eq rb

theorem CtxT.eq_sound {β : Type} [BEq β] [LawfulBEq β] : ∀ {t1 t2 : CtxT β},
    t1.eq t2 = true → t1.get = t2.get
  | .empty, .empty, _ => rfl
  | .empty, .node vb lb rb, h => by
    funext v; exact (CtxT.allNone_sound h v).symm
  | .node va la ra, .empty, h => by
    funext v; exact CtxT.allNone_sound h v
  | .node va la ra, .node vb lb rb, h => by
    simp only [CtxT.eq, Bool.and_eq_true, beq_iff_eq] at h
    have hl := CtxT.eq_sound h.1.2
    have hr := CtxT.eq_sound h.2
    funext v
    unfold CtxT.get
    split
    · exact h.1.1
    · split
      · exact congrFun hl _
      · exact congrFun hr _

def CtxT.all {β : Type} (p : β → Bool) : CtxT β → Bool
  | .empty => true
  | .node val l r =>
    (match val with | some e => p e | none => true) && l.all p && r.all p

theorem CtxT.all_sound {β : Type} {p : β → Bool} : ∀ {t : CtxT β},
    t.all p = true → ∀ v e, t.get v = some e → p e = true
  | .empty, _, _, _, h => by cases h
  | .node val l r, hall, v, e, hget => by
    simp only [CtxT.all, Bool.and_eq_true] at hall
    unfold CtxT.get at hget
    split at hget
    · rw [hget] at hall; exact hall.1.1
    · split at hget
      · exact CtxT.all_sound hall.1.2 _ _ hget
      · exact CtxT.all_sound hall.2 _ _ hget

/-- A context over the finite domain `D`, read once into a radix tree: each
    slot of `D` with what `g` gives it. A checker builds it once and passes on
    `ctxOfTbl` of it, so a later read takes `O(bit-length of key)` steps
    (bounded by the tree depth) and never replays how `g` was computed. -/
def tblOf {β : Type} (D : List Nat) (g : Nat → Option β) : CtxT β :=
  D.foldr (fun v t => t.set v (g v)) .empty

/-- The context a tree gives: the stored entry, none for an absent slot. -/
def ctxOfTbl {β : Type} (T : CtxT β) : Nat → Option β := T.get

theorem ctxOfTbl_tblOf {β : Type} (g : Nat → Option β) (v : Nat) :
    ∀ D : List Nat, ctxOfTbl (tblOf D g) v = if v ∈ D then g v else none
  | [] => by simp [ctxOfTbl, tblOf, CtxT.get]
  | a :: D => by
    have ih := ctxOfTbl_tblOf g v D
    simp only [ctxOfTbl, tblOf, List.foldr_cons] at ih ⊢
    rw [CtxT.get_set]
    by_cases h : v = a
    · subst h; simp
    · simp [h, ih]

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
