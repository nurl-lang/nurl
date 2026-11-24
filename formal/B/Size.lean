import B.Vec

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

/-- `vec_reserve` with its count checked, as the runtime does it:
    `alloc_count_add len n` panics (`none`) when `len + n` passes `iMax`,
    before the Vec changes; otherwise it is `reserve` (github#2242's
    review: `reserve` itself adds in `Nat`). -/
def reserveC {α : Type} (h : Heap α) (v : RVec) (n : Nat) : Option (Heap α × RVec) :=
  match countAdd v.len n with
  | none => none
  | some _ => reserve h v n

/-- A count past `iMax` panics, and nothing changes. -/
theorem reserveC_overflow {α : Type} {h : Heap α} {v : RVec} {n : Nat}
    (hc : (v.len : Int) + n > iMax) : reserveC h v n = none := by
  have : countAdd v.len n = none := by
    unfold countAdd
    split
    · rfl
    · omega
  simp [reserveC, this]

/-- A count that fits is `reserve_ok`'s. -/
theorem reserveC_ok {α : Type} {h : Heap α} {v : RVec} {es : List α} (n : Nat) (hw : h.WF) (hr : Rep h v es)
    (hfit : (v.len : Int) + n ≤ iMax) :
    ∃ h' v', reserveC h v n = some (h', v') ∧ Rep h' v' es ∧ h'.WF ∧ v.len + n ≤ v'.cap ∧
      v'.len = v.len := by
  have : countAdd v.len n = some (v.len + n) := by
    unfold countAdd
    split
    · omega
    · rfl
  simpa [reserveC, this] using reserve_ok n hw hr

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

end B
