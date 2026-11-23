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

end B
