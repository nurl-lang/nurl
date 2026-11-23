import B.Vec

/-!
# B4: the raw core of `HashMap` (AGORA-970)

`stdlib/std/hashmap.nu` keeps an open-addressed table in three raw blocks:
keys, values, and one state byte per slot. A state is 0 for empty, 1 for a
tombstone, and `128 | frag` for occupied. The entries move in and out
bitwise (`mem_take`, `mem_put_back`), so memory safety rests on the slot
code: which slot is read, which is written, and whether an entry is ever
written over, lost or kept twice.

This file models the table as its `cap` slots and the code of
`__map_probe_for`, `map_set`'s insert and `map_remove`. It proves:

* every slot the code touches is below `cap` (`idx & mask` is
  `idx % cap` for the power-of-two capacities `alloc_grow_pow2` makes);
* a probe's answer is sound. `found i` names a slot holding the key, and
  an insert slot is empty or a tombstone. So `map_set` never writes over
  an occupied slot's key and value (which would leak them, or drop them
  twice through the stale copy);
* a probe is total: with any empty slot in the table, it gives an answer.
  `map_set`'s 75 % load-factor check, whose count `len + tomb` is the
  number of slots in use, leaves one empty slot, so the `-1` answer
  ("table full"), which would make `map_set` write slot 0, never comes;
* `map_remove` takes the entry out once: its slot becomes a tombstone and
  the count of entries goes down by one.

The state byte's `frag` (seven bits of the hash) only spares a key
comparison. A slot holding the key always has the key's frag, so the model
compares keys directly. The rehash of `__map_grow` and the key and value
destructors are left for B4b.
-/

namespace B

/-- A slot: empty (state 0), a tombstone (state 1), or an entry. -/
inductive Slot (K V : Type) where
  | empty
  | tomb
  | full (k : K) (v : V)

variable {K V : Type} [DecidableEq K]

/-- A table of `cap` slots. -/
structure Tab (K V : Type) where
  cap : Nat
  s   : Nat → Slot K V

/-- What `__map_probe_for` answers: the key's slot, a slot to insert at,
    or `-1` (no slot). -/
inductive PRes where
  | found (i : Nat)
  | insert (i : Nat)
  | none

/-- `__map_probe_for`'s loop from probe `p` with `n` probes left and the
    first free slot seen so far `ff`. The slot is `(start + p) % cap`. -/
def probeLoop (t : Tab K V) (key : K) (start : Nat) : Nat → Nat → Option Nat → PRes
  | _, 0, ff => match ff with
    | some i => .insert i
    | none => .none
  | p, n + 1, ff =>
    match t.s ((start + p) % t.cap) with
    | .empty => .insert (ff.getD ((start + p) % t.cap))
    | .tomb => probeLoop t key start (p + 1) n (ff <|> some ((start + p) % t.cap))
    | .full k _ => if k = key then .found ((start + p) % t.cap) else probeLoop t key start (p + 1) n ff

/-- The probe for `key` with hash `h`: from slot `h % cap`, `cap` probes. -/
def probe (t : Tab K V) (key : K) (h : Nat) : PRes := probeLoop t key h 0 t.cap none

/-! ### Soundness: what a probe names is what the code then takes it for -/

theorem probeLoop_sound {t : Tab K V} {key : K} {start : Nat} (hc : 0 < t.cap) :
    ∀ n p ff, (∀ i, ff = some i → i < t.cap ∧ t.s i = .tomb) →
      (∀ i, probeLoop t key start p n ff = .found i → i < t.cap ∧ ∃ v, t.s i = .full key v) ∧
      (∀ i, probeLoop t key start p n ff = .insert i → i < t.cap ∧ (t.s i = .empty ∨ t.s i = .tomb)) := by
  intro n
  induction n with
  | zero =>
    intro p ff hff
    refine ⟨fun i h => ?_, fun i h => ?_⟩
    · cases ff <;> simp [probeLoop] at h
    · cases ff with
      | none => simp [probeLoop] at h
      | some j =>
        simp [probeLoop] at h; subst h
        exact ⟨(hff _ rfl).1, Or.inr (hff _ rfl).2⟩
  | succ n ih =>
    intro p ff hff
    have hlt : (start + p) % t.cap < t.cap := Nat.mod_lt _ hc
    cases hs : t.s ((start + p) % t.cap) with
    | empty =>
      refine ⟨fun i h => by simp [probeLoop, hs] at h, fun i h => ?_⟩
      simp only [probeLoop, hs, PRes.insert.injEq] at h
      cases ff with
      | none => simp at h; subst h; exact ⟨hlt, Or.inl hs⟩
      | some j => simp at h; subst h; exact ⟨(hff _ rfl).1, Or.inr (hff _ rfl).2⟩
    | tomb =>
      have hff' : ∀ i, (ff <|> some ((start + p) % t.cap)) = some i → i < t.cap ∧ t.s i = .tomb := by
        intro i hi
        cases ff with
        | none => simp at hi; subst hi; exact ⟨hlt, hs⟩
        | some j => simp at hi; subst hi; exact hff _ rfl
      obtain ⟨h1, h2⟩ := ih (p + 1) _ hff'
      exact ⟨fun i h => h1 i (by simpa [probeLoop, hs] using h), fun i h => h2 i (by simpa [probeLoop, hs] using h)⟩
    | full k v =>
      obtain ⟨h1, h2⟩ := ih (p + 1) ff hff
      by_cases hk : k = key
      · subst hk
        refine ⟨fun i h => ?_, fun i h => by simp [probeLoop, hs] at h⟩
        simp only [probeLoop, hs, ↓reduceIte, PRes.found.injEq] at h
        subst h; exact ⟨hlt, v, hs⟩
      · exact ⟨fun i h => h1 i (by simpa [probeLoop, hs, hk] using h),
               fun i h => h2 i (by simpa [probeLoop, hs, hk] using h)⟩

theorem probe_found {t : Tab K V} {key : K} {h i : Nat} (hc : 0 < t.cap) (hp : probe t key h = .found i) :
    i < t.cap ∧ ∃ v, t.s i = .full key v :=
  (probeLoop_sound hc t.cap 0 none (fun _ e => by cases e)).1 i hp

theorem probe_insert {t : Tab K V} {key : K} {h i : Nat} (hc : 0 < t.cap) (hp : probe t key h = .insert i) :
    i < t.cap ∧ (t.s i = .empty ∨ t.s i = .tomb) :=
  (probeLoop_sound hc t.cap 0 none (fun _ e => by cases e)).2 i hp

/-! ### Totality: an empty slot is always reached -/

/-- From probe `p`, with `n` probes left, an empty slot met at some probe
    `p + d` with `d < n` ends the loop with an answer. -/
theorem probeLoop_total {t : Tab K V} {key : K} {start : Nat} :
    ∀ n p ff d, d < n → t.s ((start + (p + d)) % t.cap) = .empty →
      probeLoop t key start p n ff ≠ .none := by
  intro n
  induction n with
  | zero => intro _ _ _ hd; omega
  | succ n ih =>
    intro p ff d hd he
    cases hs : t.s ((start + p) % t.cap) with
    | empty => simp [probeLoop, hs]
    | tomb =>
      have hd0 : d ≠ 0 := by intro e; subst e; rw [Nat.add_zero, hs] at he; cases he
      have := ih (p + 1) (ff <|> some ((start + p) % t.cap)) (d - 1) (by omega)
        (by rw [show p + 1 + (d - 1) = p + d by omega]; exact he)
      simpa [probeLoop, hs] using this
    | full k v =>
      by_cases hk : k = key
      · simp [probeLoop, hs, hk]
      · have hd0 : d ≠ 0 := by intro e; subst e; rw [Nat.add_zero, hs] at he; cases he
        have := ih (p + 1) ff (d - 1) (by omega)
          (by rw [show p + 1 + (d - 1) = p + d by omega]; exact he)
        simpa [probeLoop, hs, hk] using this

/-- Every slot below `cap` is some probe of the sequence from `start`. -/
theorem probe_covers {cap start e : Nat} (hc : 0 < cap) (he : e < cap) :
    ∃ d, d < cap ∧ (start + d) % cap = e := by
  refine ⟨(e + (cap - start % cap)) % cap, Nat.mod_lt _ hc, ?_⟩
  have hs : start % cap < cap := Nat.mod_lt _ hc
  rw [Nat.add_mod_mod]
  have hdm := Nat.div_add_mod start cap
  have : start + (e + (cap - start % cap)) = e + cap * (start / cap + 1) := by
    rw [Nat.mul_succ]; omega
  rw [this, Nat.add_mul_mod_self_left, Nat.mod_eq_of_lt he]

theorem probe_total {t : Tab K V} {key : K} {h e : Nat} (hc : 0 < t.cap) (he : e < t.cap)
    (hemp : t.s e = .empty) : probe t key h ≠ .none := by
  obtain ⟨d, hd, hde⟩ := probe_covers (start := h) hc he
  exact probeLoop_total t.cap 0 none d hd (by rw [Nat.zero_add, hde]; exact hemp)

/-! ### The count of slots in use, and the load factor -/

/-- Whether a slot is in use: an entry or a tombstone. -/
def Slot.used : Slot K V → Bool
  | .empty => false
  | _ => true

/-- The slots in use among the first `cap`: what `len + tomb` counts. -/
def Tab.used (t : Tab K V) : Nat := (List.range t.cap).countP fun i => (t.s i).used

omit [DecidableEq K] in
/-- With fewer slots in use than slots, one is empty. -/
theorem exists_empty {t : Tab K V} (hu : t.used < t.cap) : ∃ e, e < t.cap ∧ t.s e = .empty := by
  apply Classical.byContradiction
  intro hne
  have hall : ∀ i ∈ List.range t.cap, (t.s i).used = true := by
    intro i hi
    have hi' : i < t.cap := List.mem_range.mp hi
    cases hs : t.s i with
    | empty => exact absurd ⟨i, hi', hs⟩ hne
    | tomb => rfl
    | full _ _ => rfl
  have : t.used = t.cap := by
    unfold Tab.used
    rw [List.countP_eq_length.mpr (by simpa using hall), List.length_range]
  omega

/-- `map_set`'s check: after it (growing when `(len + tomb + 1)·4 ≥ cap·3`),
    `(used + 1)·4 < cap·3`. Then the probe for any key answers. The table
    is never full, and `-1` never reaches the insert. -/
theorem set_probe_answers {t : Tab K V} {key : K} {h : Nat} (hc : 0 < t.cap)
    (hload : (t.used + 1) * 4 < t.cap * 3) : probe t key h ≠ .none := by
  obtain ⟨e, he, hemp⟩ := exists_empty (t := t) (by omega)
  exact probe_total hc he hemp

/-- `idx & mask` with `mask = cap - 1` is `idx % cap` for the
    power-of-two capacities the map grows to (`alloc_grow_pow2`), so every
    slot index the code computes is below `cap`. -/
theorem mask_eq_mod (x n : Nat) : x &&& (2 ^ n - 1) = x % 2 ^ n := Nat.and_two_pow_sub_one_eq_mod x n

/-! ### `map_set` and `map_remove` on the slots -/

/-- One slot rewritten. -/
def Tab.put (t : Tab K V) (i : Nat) (x : Slot K V) : Tab K V :=
  { t with s := fun j => if j = i then x else t.s j }

/-- Whether a slot holds an entry: what `len` counts. -/
def Slot.isFull : Slot K V → Bool
  | .full _ _ => true
  | _ => false

/-- The entries among the first `cap` slots: `len`. -/
def Tab.len (t : Tab K V) : Nat := (List.range t.cap).countP fun i => (t.s i).isFull

omit [DecidableEq K] in
/-- A count over the slots after one slot below `cap` is rewritten: the
    old slot's share out, the new one's in. -/
theorem countP_put (t : Tab K V) (f : Slot K V → Bool) {i : Nat} (hi : i < t.cap) (x : Slot K V) :
    (List.range t.cap).countP (fun j => f ((t.put i x).s j)) + (if f (t.s i) then 1 else 0) =
      (List.range t.cap).countP (fun j => f (t.s j)) + (if f x then 1 else 0) := by
  have key : ∀ n, i < n → (List.range n).countP (fun j => f ((t.put i x).s j)) + (if f (t.s i) then 1 else 0) =
      (List.range n).countP (fun j => f (t.s j)) + (if f x then 1 else 0) := by
    intro n
    induction n with
    | zero => intro h; omega
    | succ n ih =>
      intro h
      rw [List.range_succ, List.countP_append, List.countP_append]
      by_cases hin : i = n
      · subst hin
        have hz : ∀ m, m ≤ i → (List.range m).countP (fun j => f ((t.put i x).s j)) =
            (List.range m).countP (fun j => f (t.s j)) := by
          intro m hm
          apply List.countP_congr
          intro j hj
          have : j ≠ i := by have := List.mem_range.mp hj; omega
          simp [Tab.put, this]
        rw [hz i (Nat.le_refl _)]
        simp [Tab.put]
        split <;> split <;> omega
      · have hjn : n ≠ i := fun e => hin e.symm
        have := ih (by omega)
        simp only [Tab.put] at this
        simp only [List.countP_singleton, Tab.put, hjn, ↓reduceIte]
        omega
  exact key t.cap hi

omit [DecidableEq K] in
/-- `map_set`'s insert at the probe's slot `i` (empty or a tombstone): the
    key and value stored, the state set. One entry more. The slots in use
    grow by one from an empty slot, and stay the same from a tombstone,
    which is `len + 1` with `tomb - 1`. Every other slot is as it was. -/
theorem mapInsert_ok {t : Tab K V} {key : K} {val : V} {i : Nat} (hi : i < t.cap)
    (hs : t.s i = .empty ∨ t.s i = .tomb) :
    (t.put i (.full key val)).len = t.len + 1 ∧
      (t.put i (.full key val)).used = t.used + (if (t.s i).used then 0 else 1) ∧
      ∀ j, j ≠ i → (t.put i (.full key val)).s j = t.s j := by
  have h1 := countP_put t Slot.isFull hi (.full key val)
  have h2 := countP_put t Slot.used hi (.full key val)
  refine ⟨?_, ?_, fun j hj => by simp [Tab.put, hj]⟩
  · unfold Tab.len
    rcases hs with hs | hs <;> rw [hs] at h1 <;> simp [Slot.isFull] at h1 <;> exact h1
  · show (List.range t.cap).countP (fun j => ((t.put i (.full key val)).s j).used) =
      (List.range t.cap).countP (fun j => (t.s j).used) + (if (t.s i).used then 0 else 1)
    rcases hs with hs | hs <;> rw [hs] at h2 ⊢ <;>
      simp only [Slot.used, Bool.false_eq_true, ↓reduceIte] at h2 ⊢ <;> omega

omit [DecidableEq K] in
/-- `map_set` on a key the probe found at `i`: the value there is moved
    out to the caller (`mem_take prev`) and the new one stored. The count
    of entries and of slots in use is the same. -/
theorem mapReplace_ok {t : Tab K V} {key : K} {val old : V} {i : Nat} (hi : i < t.cap)
    (hs : t.s i = .full key old) :
    (t.put i (.full key val)).len = t.len ∧ (t.put i (.full key val)).used = t.used ∧
      ∀ j, j ≠ i → (t.put i (.full key val)).s j = t.s j := by
  have h1 := countP_put t Slot.isFull hi (.full key val)
  have h2 := countP_put t Slot.used hi (.full key val)
  rw [hs] at h1 h2
  simp [Slot.isFull, Slot.used] at h1 h2
  exact ⟨h1, h2, fun j hj => by simp [Tab.put, hj]⟩

omit [DecidableEq K] in
/-- `map_remove` of a key the probe found at `i`: the value moved out to
    the caller, the slot a tombstone, so a probe path through it still
    runs on. One entry fewer, the same slots in use (`len - 1`,
    `tomb + 1`). -/
theorem mapRemove_ok {t : Tab K V} {key : K} {v : V} {i : Nat} (hi : i < t.cap)
    (hs : t.s i = .full key v) :
    (t.put i .tomb).len + 1 = t.len ∧ (t.put i .tomb).used = t.used ∧
      ∀ j, j ≠ i → (t.put i .tomb).s j = t.s j := by
  have h1 := countP_put t Slot.isFull hi .tomb
  have h2 := countP_put t Slot.used hi .tomb
  rw [hs] at h1 h2
  simp [Slot.isFull, Slot.used] at h1 h2
  exact ⟨h1, h2, fun j hj => by simp [Tab.put, hj]⟩

end B
