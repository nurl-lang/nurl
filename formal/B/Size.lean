module

public import B.Vec

@[expose] public section

/-!
# B8: allocation sizes never wrap (AGORA-970)

Every byte size the library allocates for a caller's count goes through
`alloc_size` / `alloc_count_add` (`stdlib/core/vec.nu`). A size that wrapped
in 64 bits would hand back a tiny buffer that the count then writes past.
This file proves that never happens. Either the check panics, or the
product or sum is the true one and fits in an `i64` (at most `2^63 - 1`).
The signed 64-bit arithmetic is modelled exactly: a result is computed in
`Int` and is the machine's value only when it lies in range, which is what
the theorems show.

`vec_reserve` checks two things on its growth path, in this order: the
count `len + n` (`alloc_count_add`) and the byte size of the capacity the
growth rounds that count up to (`alloc_size` in `__vec_grow`). `reserveC`
models the first only; `reserveZ` models both, and `reserveC_size_gap`
shows a reserve that the first check passes and the second refuses.
-/

namespace B

/-- `i64`'s largest value. -/
def iMax : Int := 9223372036854775807

/-- `alloc_size size n`: the fast path for both under `2^31`, else the
    panic (`none`) for a negative count or a product past `iMax`, else the
    product. `size` is a type's size, never negative. -/
def allocSize (size : Nat) (n : Int) : Option Int :=
  if 0 ≤ n ∧ n < 2147483648 ∧ (size : Int) < 2147483648 then some (size * n)
  else if n < 0 ∨ (0 < size ∧ n > iMax / size) then none
  else some (size * n)

/-- `alloc_count_add a b`: the panic for a negative count or a sum past
    `iMax`, else the sum. -/
def countAdd (a b : Int) : Option Int :=
  if a < 0 ∨ b < 0 ∨ a > iMax - b then none else some (a + b)

theorem allocSize_ok (size : Nat) (n : Int) :
    ∀ p, allocSize size n = some p → p = size * n ∧ 0 ≤ p ∧ p ≤ iMax := by
  intro p hp
  unfold allocSize at hp
  split at hp
  · rename_i h
    obtain ⟨h0, h1, h2⟩ := h
    simp at hp; subst hp
    refine ⟨rfl, Int.mul_nonneg (by omega) h0, ?_⟩
    have : (size : Int) * n ≤ 2147483648 * 2147483648 :=
      Int.mul_le_mul (by omega) (by omega) h0 (by omega)
    unfold iMax; omega
  · split at hp
    · cases hp
    · rename_i _ h
      simp at hp; subst hp
      have hn : 0 ≤ n := by omega
      refine ⟨rfl, Int.mul_nonneg (by omega) hn, ?_⟩
      rcases Nat.eq_zero_or_pos size with hs | hs
      · subst hs; simp [iMax]
      · have hle : n ≤ iMax / size := by omega
        have hsz : (0 : Int) < size := by omega
        have := Int.mul_le_of_le_ediv hsz hle
        rw [Int.mul_comm] at this
        exact this

theorem countAdd_ok (a b : Int) : ∀ p, countAdd a b = some p → p = a + b ∧ 0 ≤ p ∧ p ≤ iMax := by
  intro p hp
  unfold countAdd at hp
  split at hp
  · cases hp
  · rename_i h
    simp at hp; subst hp
    refine ⟨rfl, by omega, by omega⟩

/-- `vec_reserve` with its count checked, as the runtime does it: only on
    the growth path (`n > 0` and less room than `n`) does it call
    `alloc_count_add len n`, which panics (`none`) when `len + n` passes
    `iMax`, before the Vec changes; every other path is `reserve`'s
    (github#2242's review: `reserve` itself adds in `Nat`). It checks the
    count only, not the byte size of the capacity the growth rounds up to:
    for 8-byte elements, an empty `Vec` and `n = 2^60 - 1` it is `some`
    while the runtime's `alloc_size` panics (`reserveC_size_gap`).
    `reserveZ` below is the whole check. -/
def reserveC {α : Type} (h : Heap α) (v : RVec) (n : Nat) : Option (Heap α × RVec) :=
  if n > 0 ∧ v.cap - v.len < n then
    match countAdd v.len n with
    | none => none
    | some _ => reserve h v n
  else reserve h v n

/-- On the growth path, a count past `iMax` panics, and nothing changes. -/
theorem reserveC_overflow {α : Type} {h : Heap α} {v : RVec} {n : Nat}
    (hg : n > 0 ∧ v.cap - v.len < n) (hc : (v.len : Int) + n > iMax) : reserveC h v n = none := by
  have : countAdd v.len n = none := by
    unfold countAdd
    split
    · rfl
    · omega
  unfold reserveC
  rw [ite_eq_left hg, this]

/-- Off the growth path `reserveC` is `reserve`, whatever the counts. -/
theorem reserveC_room {α : Type} {h : Heap α} {v : RVec} {n : Nat}
    (hg : ¬ (n > 0 ∧ v.cap - v.len < n)) : reserveC h v n = reserve h v n := by
  unfold reserveC
  rw [ite_eq_right hg]

/-- A count that fits is `reserve_ok`'s. -/
theorem reserveC_ok {α : Type} {h : Heap α} {v : RVec} {es : List α} (n : Nat) (hw : h.WF) (hr : Rep h v es)
    (hfit : (v.len : Int) + n ≤ iMax) :
    ∃ h' v', reserveC h v n = some (h', v') ∧ Rep h' v' es ∧ h'.WF ∧ v.len + n ≤ v'.cap ∧
      v'.len = v.len := by
  have : countAdd v.len n = some ((v.len : Int) + n) := by
    unfold countAdd
    split
    · omega
    · rfl
  have hR : reserveC h v n = reserve h v n := by
    unfold reserveC
    split
    · simp only [this]
    · rfl
  rw [hR]
  exact reserve_ok n hw hr

/-- The doubling of `alloc_grow_cap` stops below twice what is needed: from
    a start `c > 0`, it ends at `c` itself (already enough) or below
    `2 * need`. -/
theorem doubleTo_le {need : Nat} : ∀ c, 0 < c → doubleTo c need ≤ max c (2 * need - 1) := by
  intro c
  induction c using doubleTo.induct (need := need) with
  | case1 c h ih =>
    intro _
    rw [doubleTo]; simp only [h, and_self, ↓reduceIte]
    have := ih (by omega)
    omega
  | case2 c h =>
    intro _
    rw [doubleTo]; simp only [h, ↓reduceIte]; omega

/-- `__vec_grow_to` multiplies the new capacity by the element size with no
    check (vec.nu: `need` counts elements that exist, so `need · Z < 2^58`).
    This is the bound it rests on: below `2^62`, the capacity
    `alloc_grow_cap` picks is the old one, 4, or below `2 * need`. -/
theorem growCap_le (cap need : Nat) (hn : need ≤ 4611686018427387904) :
    growCap cap need ≤ max (if 0 < cap then cap else 4) (2 * need - 1) := by
  unfold growCap
  dsimp only
  rw [ite_eq_right (by omega)]
  exact doubleTo_le _ (by split <;> omega)

/-- `__vec_grow_to`'s capacity: a growth sets it to `alloc_grow_cap`'s. -/
theorem growTo_cap {α : Type} {h h1 : Heap α} {v v1 : RVec} {need : Nat} (hc : v.cap < need)
    (he : growTo h v need = some (h1, v1)) : v1.cap = growCap v.cap need := by
  unfold growTo at he
  rw [ite_eq_left hc] at he
  cases hd : v.data with
  | none =>
    simp only [hd, Option.some.injEq, Prod.mk.injEq] at he
    rw [← he.2]
  | some d =>
    simp only [hd] at he
    cases hr : h.realloc d (growCap v.cap need) with
    | none => rw [hr] at he; exact absurd he (by simp)
    | some q =>
      rw [hr, Option.map_some, Option.some.injEq, Prod.mk.injEq] at he
      rw [← he.2]

/-- `vec_reserve` for elements of `z` bytes, as the runtime runs it. On the
    growth path (`n > 0`, less room than `n`): `alloc_count_add len n`
    (the panic, `none`, past `iMax`), then `__vec_grow`: `__vec_grow_cap`
    picks `alloc_grow_cap cap need` (the owned `cap < need` case: an
    `RVec`'s capacity is never negative, so the view case does not arise),
    and `alloc_size z` of that ROUNDED capacity is checked (the panic,
    `none`) before `__vec_place` allocates; then `reserve`'s growth. Every
    other path is `reserve`'s, with no check. The runtime computes the
    capacity in `i64`; for a count `need ≤ iMax` the doubling stays below
    `2^63` (`alloc_grow_cap` doubles only below `2^62`), so `growCap` in
    `Nat` is that value. -/
def reserveZ {α : Type} (z : Nat) (h : Heap α) (v : RVec) (n : Nat) : Option (Heap α × RVec) :=
  if n > 0 ∧ v.cap - v.len < n then
    match countAdd v.len n with
    | none => none
    | some _ =>
      match allocSize z (growCap v.cap (v.len + n)) with
      | none => none
      | some _ => reserve h v n
  else reserve h v n

/-- Off the growth path `reserveZ` is `reserve`, whatever the counts. -/
theorem reserveZ_room {α : Type} {h : Heap α} {v : RVec} {n : Nat} (z : Nat)
    (hg : ¬ (n > 0 ∧ v.cap - v.len < n)) : reserveZ z h v n = reserve h v n := by
  unfold reserveZ
  rw [ite_eq_right hg]

/-- On the growth path, a count past `iMax` panics, and nothing changes. -/
theorem reserveZ_count_overflow {α : Type} {h : Heap α} {v : RVec} {n : Nat} (z : Nat)
    (hg : n > 0 ∧ v.cap - v.len < n) (hc : (v.len : Int) + n > iMax) : reserveZ z h v n = none := by
  have : countAdd v.len n = none := by
    unfold countAdd
    split
    · rfl
    · omega
  unfold reserveZ
  rw [ite_eq_left hg, this]

/-- On the growth path, a rounded capacity whose byte size `alloc_size`
    refuses panics, and nothing changes. -/
theorem reserveZ_size_overflow {α : Type} {h : Heap α} {v : RVec} {n : Nat} (z : Nat)
    (hg : n > 0 ∧ v.cap - v.len < n) (hs : allocSize z (growCap v.cap (v.len + n)) = none) :
    reserveZ z h v n = none := by
  unfold reserveZ
  rw [ite_eq_left hg]
  cases countAdd v.len n with
  | none => rfl
  | some _ =>
    generalize allocSize z (growCap v.cap (v.len + n)) = A at hs
    subst hs; rfl

/-- A count that fits and, on the growth path, a rounded capacity whose
    byte size fits: `reserve_ok`'s result, and on the growth path the new
    capacity is `alloc_grow_cap`'s and its byte size `z * cap` is the true
    product, at most `iMax`. -/
theorem reserveZ_ok {α : Type} {h : Heap α} {v : RVec} {es : List α} (z n : Nat) (hw : h.WF) (hr : Rep h v es)
    (hfit : (v.len : Int) + n ≤ iMax)
    (hsz : n > 0 ∧ v.cap - v.len < n → allocSize z (growCap v.cap (v.len + n)) ≠ none) :
    ∃ h' v', reserveZ z h v n = some (h', v') ∧ Rep h' v' es ∧ h'.WF ∧ v.len + n ≤ v'.cap ∧
      v'.len = v.len ∧
      (n > 0 ∧ v.cap - v.len < n → v'.cap = growCap v.cap (v.len + n) ∧ (z : Int) * v'.cap ≤ iMax) := by
  obtain ⟨h', v', he, hr', hw', hroom, hlen⟩ := reserve_ok n hw hr
  refine ⟨h', v', ?_, hr', hw', hroom, hlen, fun hg => ?_⟩
  · unfold reserveZ
    by_cases hg : n > 0 ∧ v.cap - v.len < n
    · rw [ite_eq_left hg]
      have hca : countAdd v.len n = some ((v.len : Int) + n) := by
        unfold countAdd
        rw [ite_eq_right (by omega)]
      obtain ⟨b, hb⟩ := Option.ne_none_iff_exists'.mp (hsz hg)
      rw [hca]
      generalize allocSize z (growCap v.cap (v.len + n)) = A at hb
      subst hb; exact he
    · rw [ite_eq_right hg]; exact he
  · have hc : v.cap < v.len + n := by omega
    have he' : growTo h v (v.len + n) = some (h', v') := by
      unfold reserve at he; rwa [ite_eq_left hg] at he
    have hcap := growTo_cap hc he'
    refine ⟨hcap, ?_⟩
    obtain ⟨b, hb⟩ := Option.ne_none_iff_exists'.mp (hsz hg)
    obtain ⟨e, -, hle⟩ := allocSize_ok z _ b hb
    rw [hcap]; rw [← e]; exact hle

/-- The gap `reserveC` leaves (github#2242's review): an empty `Vec` of
    8-byte elements, `vec_reserve v (2^60 - 1)`. The count fits, so
    `reserveC` grows and answers `some`. But the growth rounds the capacity
    up to `2^60`, whose byte size `8 * 2^60 = 2^63` is past `iMax`, and the
    runtime's `alloc_size` panics: `reserveZ` is `none`. -/
theorem reserveC_size_gap {α : Type} (h : Heap α) :
    (reserveC h ⟨none, 0, 0⟩ (2 ^ 60 - 1)).isSome = true ∧ growCap 0 (2 ^ 60 - 1) = 2 ^ 60 ∧
      reserveZ 8 h ⟨none, 0, 0⟩ (2 ^ 60 - 1) = none := by
  have hg : growCap 0 (2 ^ 60 - 1) = 2 ^ 60 := by
    unfold growCap
    simp only [Nat.lt_irrefl, ↓reduceIte, Nat.reducePow, Nat.reduceSub, Nat.reduceLT, gt_iff_lt]
    repeat (rw [doubleTo]; simp only [Nat.reduceMul, Nat.reduceLT, and_self, and_false, ↓reduceIte])
  refine ⟨?_, hg, ?_⟩
  · simp [reserveC, countAdd, reserve, growTo, iMax]
  · apply reserveZ_size_overflow 8 (by decide)
    simp only [Nat.zero_add]
    rw [hg]
    simp [allocSize, iMax]

end B
