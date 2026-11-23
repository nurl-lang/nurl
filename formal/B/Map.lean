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
* `__map_grow` moves every entry once (`grow_ok`), and its search for an
  empty slot always finds one;
* `map_remove` takes the entry out once: its slot becomes a tombstone and
  the count of entries goes down by one.

The state byte's `frag` (seven bits of the hash) only spares a key
comparison. A slot holding the key always has the key's frag, so the model
compares keys directly. `__map_grow`'s rehash is covered too (`grow_ok`):
the new table holds exactly the old entries, each once. `HashMap_drop`'s release loop
is covered too (`release_ok`).
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

/-! ### `__map_grow`: the rehash moves every entry once

`__map_grow` takes the old buffers out (`mem_replace`) and installs fresh
zeroed ones (every slot empty). It then walks the old slots in order, and
moves each entry into the first empty slot from its hash in the new table
(`~ != state 0 { idx + 1 & mask }`). The entries of the new table are then
exactly the old ones, each once. None is lost (a leak), none is kept twice
(a double drop), and tombstones are gone. The search for an empty slot
always finds one, because fewer entries than slots have gone in. -/

omit [DecidableEq K] in
/-- The entries among the first `n` slots, in slot order. -/
def entriesUpTo (s : Nat → Slot K V) : Nat → List (K × V)
  | 0 => []
  | n + 1 => entriesUpTo s n ++ (match s n with | .full k v => [(k, v)] | _ => [])

/-- The table's entries. -/
def Tab.entries (t : Tab K V) : List (K × V) := entriesUpTo t.s t.cap

omit [DecidableEq K] in
theorem entriesUpTo_put_empty {s : Nat → Slot K V} {i : Nat} {e : K × V} (hs : s i = .empty) :
    ∀ n, i < n → (entriesUpTo (fun j => if j = i then .full e.1 e.2 else s j) n).Perm (e :: entriesUpTo s n) := by
  intro n
  induction n with
  | zero => intro h; omega
  | succ n ih =>
    intro h
    simp only [entriesUpTo]
    by_cases hin : n = i
    · subst hin
      have hz : ∀ m, m ≤ n → entriesUpTo (fun j => if j = n then .full e.1 e.2 else s j) m = entriesUpTo s m := by
        intro m
        induction m with
        | zero => intro _; rfl
        | succ m ihm =>
          intro hm
          simp only [entriesUpTo]
          rw [ihm (by omega), ite_eq_right (by omega)]
      rw [hz n (Nat.le_refl _), hs]
      simp only [↓reduceIte, List.append_nil]
      exact List.perm_append_singleton e _
    · rw [ite_eq_right hin]
      exact (ih (by omega)).append_right _ |>.trans (by simp)

omit [DecidableEq K] in
theorem entriesUpTo_ext {s s' : Nat → Slot K V} :
    ∀ n, (∀ j, j < n → s j = s' j) → entriesUpTo s n = entriesUpTo s' n := by
  intro n
  induction n with
  | zero => intro _; rfl
  | succ n ih =>
    intro h
    simp only [entriesUpTo]
    rw [ih (fun j hj => h j (by omega)), h n (by omega)]

omit [DecidableEq K] in
/-- An entry stored into an empty slot below `cap` adds exactly that entry. -/
theorem entries_put_empty {t : Tab K V} {i : Nat} {e : K × V} (hi : i < t.cap) (hs : t.s i = .empty) :
    (t.put i (.full e.1 e.2)).entries.Perm (e :: t.entries) :=
  entriesUpTo_put_empty hs t.cap hi

/-- The rehash's search: the first empty slot from `start`, `n` probes. -/
def findEmpty (t : Tab K V) (start : Nat) : Nat → Nat → Option Nat
  | _, 0 => none
  | p, n + 1 =>
    match t.s ((start + p) % t.cap) with
    | .empty => some ((start + p) % t.cap)
    | _ => findEmpty t start (p + 1) n

omit [DecidableEq K] in
theorem findEmpty_sound {t : Tab K V} {start : Nat} (hc : 0 < t.cap) :
    ∀ n p i, findEmpty t start p n = some i → i < t.cap ∧ t.s i = .empty := by
  intro n
  induction n with
  | zero => intro _ _ h; cases h
  | succ n ih =>
    intro p i h
    cases hs : t.s ((start + p) % t.cap) with
    | empty => simp [findEmpty, hs] at h; subst h; exact ⟨Nat.mod_lt _ hc, hs⟩
    | tomb => exact ih (p + 1) i (by simpa [findEmpty, hs] using h)
    | full _ _ => exact ih (p + 1) i (by simpa [findEmpty, hs] using h)

omit [DecidableEq K] in
theorem findEmpty_total {t : Tab K V} {start : Nat} :
    ∀ n p d, d < n → t.s ((start + (p + d)) % t.cap) = .empty → findEmpty t start p n ≠ none := by
  intro n
  induction n with
  | zero => intro _ _ hd; omega
  | succ n ih =>
    intro p d hd he
    cases hs : t.s ((start + p) % t.cap) with
    | empty => simp [findEmpty, hs]
    | tomb =>
      have hd0 : d ≠ 0 := by intro e; subst e; rw [Nat.add_zero, hs] at he; cases he
      have := ih (p + 1) (d - 1) (by omega) (by rw [show p + 1 + (d - 1) = p + d by omega]; exact he)
      simpa [findEmpty, hs] using this
    | full _ _ =>
      have hd0 : d ≠ 0 := by intro e; subst e; rw [Nat.add_zero, hs] at he; cases he
      have := ih (p + 1) (d - 1) (by omega) (by rw [show p + 1 + (d - 1) = p + d by omega]; exact he)
      simpa [findEmpty, hs] using this

/-- Move one entry into the new table: its first empty slot from its hash. -/
def moveIn (hash : K → Nat) (t : Tab K V) (e : K × V) : Option (Tab K V) :=
  (findEmpty t (hash e.1) 0 t.cap).map fun i => t.put i (.full e.1 e.2)

/-- The rehash loop over the old entries in slot order. -/
def moveAll (hash : K → Nat) : Tab K V → List (K × V) → Option (Tab K V)
  | t, [] => some t
  | t, e :: es => match moveIn hash t e with
    | none => none
    | some t1 => moveAll hash t1 es

omit [DecidableEq K] in
/-- A table with no tombstones (the fresh one and every one the rehash
    makes) has as many slots in use as entries. -/
theorem used_eq_len_of_no_tomb {t : Tab K V} (h : ∀ i, i < t.cap → t.s i ≠ .tomb) : t.used = t.len := by
  unfold Tab.used Tab.len
  apply List.countP_congr
  intro i hi
  have := h i (List.mem_range.mp hi)
  cases hs : t.s i with
  | empty => simp [Slot.used, Slot.isFull]
  | tomb => exact absurd hs this
  | full _ _ => simp [Slot.used, Slot.isFull]

omit [DecidableEq K] in
theorem len_eq_entries_length (t : Tab K V) : t.len = t.entries.length := by
  unfold Tab.len Tab.entries
  generalize t.cap = n
  induction n with
  | zero => rfl
  | succ n ih =>
    rw [List.range_succ, List.countP_append, ih]
    simp only [entriesUpTo, List.length_append]
    cases hs : t.s n <;> simp [Slot.isFull, hs]

omit [DecidableEq K] in
/-- The rehash into a table with no tombstones, with room for every entry
    (`entries + es < cap`): it succeeds, and its entries are the old ones
    and `es`, each once. -/
theorem moveAll_ok (hash : K → Nat) :
    ∀ (es : List (K × V)) (t : Tab K V), 0 < t.cap → (∀ i, i < t.cap → t.s i ≠ .tomb) →
      t.entries.length + es.length < t.cap + 1 → t.entries.length + es.length ≤ t.cap →
      ∃ t', moveAll hash t es = some t' ∧ t'.cap = t.cap ∧ t'.entries.Perm (es.reverse ++ t.entries) ∧
        (∀ i, i < t'.cap → t'.s i ≠ .tomb) := by
  intro es
  induction es with
  | nil => intro t _ hnt _ _; exact ⟨t, rfl, rfl, by simp, hnt⟩
  | cons e es ih =>
    intro t hc hnt _ hroom
    -- an empty slot exists: fewer entries than slots
    have hu : t.used < t.cap := by
      rw [used_eq_len_of_no_tomb hnt, len_eq_entries_length]; simp at hroom; omega
    obtain ⟨x, hx, hxe⟩ := exists_empty hu
    obtain ⟨d, hd, hde⟩ := probe_covers (start := hash e.1) hc hx
    have hf := findEmpty_total (t := t) (start := hash e.1) t.cap 0 d hd (by rw [Nat.zero_add, hde]; exact hxe)
    obtain ⟨i, hi⟩ := Option.ne_none_iff_exists'.mp hf
    obtain ⟨hil, hie⟩ := findEmpty_sound hc t.cap 0 i hi
    let t1 := t.put i (.full e.1 e.2)
    have hp := entries_put_empty (e := e) hil hie
    have hnt1 : ∀ j, j < t1.cap → t1.s j ≠ .tomb := by
      intro j hj
      show (if j = i then Slot.full e.1 e.2 else t.s j) ≠ .tomb
      split
      · exact fun h => by cases h
      · exact hnt j hj
    have hlen1 : t1.entries.length = t.entries.length + 1 := by rw [hp.length_eq]; simp
    obtain ⟨t', he', hcap', hperm', hnt'⟩ := ih t1 hc hnt1 (by
      simp at hroom; show t1.entries.length + es.length < t.cap + 1; rw [hlen1]; omega) (by
      simp at hroom; show t1.entries.length + es.length ≤ t.cap; rw [hlen1]; omega)
    refine ⟨t', ?_, hcap', ?_, hnt'⟩
    · simp only [moveAll, moveIn, hi, Option.map_some]; exact he'
    · refine hperm'.trans ?_
      rw [List.reverse_cons, List.append_assoc, List.singleton_append]
      exact List.Perm.append_left _ hp

/-- A fresh table of `n` empty slots (`raw_block_zero`). -/
def Tab.fresh (n : Nat) : Tab K V := { cap := n, s := fun _ => .empty }

omit [DecidableEq K] in
theorem fresh_entries (n : Nat) : (Tab.fresh n : Tab K V).entries = [] := by
  unfold Tab.entries Tab.fresh
  simp only
  generalize n = m
  induction m with
  | zero => rfl
  | succ m ih => simp only [entriesUpTo, ih]; rfl

omit [DecidableEq K] in
/-- `__map_grow` into `new_cap` slots, more than the old table has
    entries: it succeeds, and the new table holds exactly the old entries,
    each once, with no tombstones. -/
theorem grow_ok (hash : K → Nat) (t : Tab K V) {n : Nat} (hroom : t.entries.length < n) :
    ∃ t', moveAll hash (Tab.fresh n) t.entries = some t' ∧ t'.cap = n ∧ t'.entries.Perm t.entries ∧
      ∀ i, i < t'.cap → t'.s i ≠ .tomb := by
  have hc : 0 < n := by omega
  obtain ⟨t', he, hcap, hperm, hnt⟩ := moveAll_ok hash t.entries (Tab.fresh n) hc
    (fun _ _ h => by cases h) (by rw [fresh_entries]; simp; show _ < n + 1; omega)
    (by rw [fresh_entries]; simp; show _ ≤ n; omega)
  refine ⟨t', he, hcap, ?_, hnt⟩
  rw [fresh_entries, List.append_nil] at hperm
  exact hperm.trans (List.reverse_perm _)

/-! ### `__map_release`: every entry dropped once, the map honest throughout

Where dropping a key or a value runs program code, `HashMap_drop` goes
through `__map_release`. Each entry leaves the map before its key and value
are dropped: its slot becomes a tombstone, the count goes down, and `next`
moves past it. When a destructor runs, the map holds exactly the entries
still to go. A panic in one is resumed from `next`
(`MapRelease_drop`), so the entries after it are dropped and the one that
panicked is not dropped again. -/

omit [DecidableEq K] in
/-- The entry a slot holds, as a list of at most one. -/
def Slot.ent : Slot K V → List (K × V)
  | .full k v => [(k, v)]
  | _ => []

omit [DecidableEq K] in
/-- The entries of slots `[i, i + n)`, in order. -/
def entriesRange (s : Nat → Slot K V) : Nat → Nat → List (K × V)
  | _, 0 => []
  | i, n + 1 => (s i).ent ++ entriesRange s (i + 1) n

omit [DecidableEq K] in
theorem entriesUpTo_add (s : Nat → Slot K V) (i : Nat) :
    ∀ n, entriesUpTo s (i + n) = entriesUpTo s i ++ entriesRange s i n := by
  intro n
  induction n generalizing i with
  | zero => simp [entriesRange]
  | succ n ih =>
    rw [show i + (n + 1) = (i + 1) + n by omega, ih (i + 1)]
    simp only [entriesUpTo, entriesRange, List.append_assoc]
    cases s i <;> rfl

omit [DecidableEq K] in
theorem entriesRange_split (s : Nat → Slot K V) :
    ∀ a b i, entriesRange s i (a + b) = entriesRange s i a ++ entriesRange s (i + a) b := by
  intro a
  induction a with
  | zero => intro b i; simp [entriesRange]
  | succ a ih =>
    intro b i
    rw [show a + 1 + b = (a + b) + 1 by omega]
    simp only [entriesRange, List.append_assoc]
    rw [ih b (i + 1), show i + 1 + a = i + (a + 1) by omega]

omit [DecidableEq K] in
/-- One slot of the release: an entry leaves (its slot a tombstone) and is
    handed out to be dropped. -/
def relStep (t : Tab K V) (j : Nat) : Tab K V × List (K × V) :=
  match t.s j with
  | .full k v => (t.put j .tomb, [(k, v)])
  | _ => (t, [])

omit [DecidableEq K] in
/-- `__map_release`'s loop over slots `[i, i + n)`. -/
def relLoop : Tab K V → Nat → Nat → Tab K V × List (K × V)
  | t, _, 0 => (t, [])
  | t, i, n + 1 =>
    let r1 := relStep t i
    let r2 := relLoop r1.1 (i + 1) n
    (r2.1, r1.2 ++ r2.2)

omit [DecidableEq K] in
theorem relLoop_spec :
    ∀ n (t : Tab K V) i, (relLoop t i n).2 = entriesRange t.s i n ∧ (relLoop t i n).1.cap = t.cap ∧
      (∀ j, (j < i ∨ i + n ≤ j) → (relLoop t i n).1.s j = t.s j) ∧
      (∀ j, i ≤ j → j < i + n → ((relLoop t i n).1.s j).ent = []) := by
  intro n
  induction n with
  | zero => intro t i; refine ⟨rfl, rfl, fun _ _ => rfl, fun j h1 h2 => by omega⟩
  | succ n ih =>
    intro t i
    obtain ⟨hd, hc, hout, hin⟩ := ih (relStep t i).1 (i + 1)
    have hstep_s : ∀ j, j ≠ i → (relStep t i).1.s j = t.s j := by
      intro j hj; unfold relStep; split <;> simp [Tab.put, hj]
    have hstep_i : ((relStep t i).1.s i).ent = [] := by
      unfold relStep; split <;> simp_all [Tab.put, Slot.ent]
    have hstep_d : (relStep t i).2 = (t.s i).ent := by
      unfold relStep; split <;> simp_all [Slot.ent]
    have hstep_c : (relStep t i).1.cap = t.cap := by unfold relStep; split <;> rfl
    refine ⟨?_, ?_, ?_, ?_⟩
    · simp only [relLoop]
      rw [hd, hstep_d, entriesRange]
      congr 1
      -- the rest of the range sees the table as it was: only slot i changed
      have : ∀ m j, i < j → entriesRange (relStep t i).1.s j m = entriesRange t.s j m := by
        intro m
        induction m with
        | zero => intro _ _; rfl
        | succ m ihm =>
          intro j hj
          simp only [entriesRange]
          rw [hstep_s j (by omega), ihm (j + 1) (by omega)]
      exact this n (i + 1) (by omega)
    · simp only [relLoop]; rw [hc, hstep_c]
    · intro j hj
      simp only [relLoop]
      rw [hout j (by omega), hstep_s j (by omega)]
    · intro j h1 h2
      simp only [relLoop]
      by_cases hji : j = i
      · subst hji; rw [hout j (by omega)]; exact hstep_i
      · exact hin j (by omega) (by omega)

omit [DecidableEq K] in
/-- `__map_release` from slot 0 drops exactly the map's entries, in slot
    order, each once, and leaves no entry behind. And at any point after
    slot `j`, the table holds exactly the entries of slots past `j`, which
    a resume from `next = j + 1` (a panic's `MapRelease_drop`) then drops. -/
theorem release_ok (t : Tab K V) :
    (relLoop t 0 t.cap).2 = t.entries ∧ (relLoop t 0 t.cap).1.len = 0 ∧
      ∀ j, j < t.cap → (relLoop t 0 (j + 1)).1.entries = entriesRange t.s (j + 1) (t.cap - (j + 1)) ∧
        (relLoop t 0 (j + 1)).2 ++ (relLoop (relLoop t 0 (j + 1)).1 (j + 1) (t.cap - (j + 1))).2 = t.entries := by
  have hent : ∀ (u : Tab K V), u.entries = entriesRange u.s 0 u.cap := by
    intro u; unfold Tab.entries; have := entriesUpTo_add u.s 0 u.cap; simpa [entriesUpTo] using this
  obtain ⟨hd, hc, _, hin⟩ := relLoop_spec t.cap t 0
  refine ⟨by rw [hd, hent], ?_, fun j hj => ?_⟩
  · rw [len_eq_entries_length, hent, hc]
    have : ∀ m i, (∀ x, i ≤ x → x < i + m → ((relLoop t 0 t.cap).1.s x).ent = []) →
        entriesRange (relLoop t 0 t.cap).1.s i m = [] := by
      intro m
      induction m with
      | zero => intro _ _; rfl
      | succ m ihm =>
        intro i h
        simp only [entriesRange]
        rw [h i (by omega) (by omega), ihm (i + 1) (fun x h1 h2 => h x (by omega) (by omega))]
        rfl
    rw [this t.cap 0 (fun x _ h2 => hin x (by omega) (by omega))]
    rfl
  · obtain ⟨hd1, hc1, hout1, hin1⟩ := relLoop_spec (j + 1) t 0
    have hsplit : ∀ (u : Tab K V), u.cap = t.cap →
        entriesRange u.s 0 u.cap = entriesRange u.s 0 (j + 1) ++ entriesRange u.s (j + 1) (t.cap - (j + 1)) := by
      intro u hu
      rw [hu, show t.cap = (j + 1) + (t.cap - (j + 1)) by omega, entriesRange_split, Nat.zero_add]
      congr 2; omega
    let u := (relLoop t 0 (j + 1)).1
    have hzero : entriesRange u.s 0 (j + 1) = [] := by
      have : ∀ m i, i + m ≤ j + 1 → entriesRange u.s i m = [] := by
        intro m
        induction m with
        | zero => intro _ _; rfl
        | succ m ihm =>
          intro i h
          simp only [entriesRange]
          rw [hin1 i (by omega) (by omega), ihm (i + 1) (by omega)]
          rfl
      exact this (j + 1) 0 (by omega)
    have hrest : entriesRange u.s (j + 1) (t.cap - (j + 1)) = entriesRange t.s (j + 1) (t.cap - (j + 1)) := by
      have : ∀ m i, j + 1 ≤ i → entriesRange u.s i m = entriesRange t.s i m := by
        intro m
        induction m with
        | zero => intro _ _; rfl
        | succ m ihm =>
          intro i h
          simp only [entriesRange]
          rw [hout1 i (Or.inr (by omega)), ihm (i + 1) (by omega)]
      exact this _ _ (Nat.le_refl _)
    refine ⟨?_, ?_⟩
    · rw [hent, hsplit u hc1, hzero, List.nil_append, hrest]
    · obtain ⟨hd2, _, _, _⟩ := relLoop_spec (t.cap - (j + 1)) u (j + 1)
      rw [hd1, hd2, hrest, hent]
      have := hsplit t rfl
      rw [this]

end B
