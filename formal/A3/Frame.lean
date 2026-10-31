import A3.Defs

/-! A3.0 — a thread's step over its own part of the address space.

Every thread runs A2's step on the shared address space. Its own trees are
one part of it (`a1`), every other thread's the rest (`a2`): `Split`. A
step frees only what the thread owns and allocates only fresh addresses,
so it changes `a1` and leaves `a2` as it was. These lemmas are that
argument for each way A2's step changes `alloc`. -/

namespace A3
open A2

/-- The address space `a` is `a1` and `a2` together, sharing no address. -/
def Split (a a1 a2 : Nat → Bool) : Prop := ∀ i, a i = (a1 i || a2 i) ∧ (a1 i && a2 i) = false

theorem Split.left {a a1 a2 : Nat → Bool} (hs : Split a a1 a2) {i : Nat} (h : a1 i = true) :
    a i = true := by rw [(hs i).1, h]; rfl

theorem Split.not_right {a a1 a2 : Nat → Bool} (hs : Split a a1 a2) {i : Nat} (h : a1 i = true) :
    a2 i = false := by have := (hs i).2; rw [h] at this; simpa using this

/-- Freeing one of the thread's own trees frees it in the thread's part. -/
theorem frees_split {a a1 a2 a' a1' : Nat → Bool} {T : Val} (hs : Split a a1 a2) (hf : Frees a T a')
    (hf1 : Frees a1 T a1') (hown : ∀ i ∈ T.ids, a1 i = true) : Split a' a1' a2 := by
  intro i
  by_cases hi : i ∈ T.ids
  · rw [hf.freed hi, hf1.freed hi, hs.not_right (hown i hi)]; exact ⟨rfl, rfl⟩
  · rw [hf.other hi, hf1.other hi]; exact hs i

/-- Allocating a fresh address puts it in the thread's part. -/
theorem split_alloc {a a1 a2 : Nat → Bool} (hs : Split a a1 a2) {n : Nat} (h2 : a2 n = false) :
    Split (upd a n true) (upd a1 n true) a2 := by
  intro i
  by_cases hin : i = n
  · subst hin; simp [upd, h2]
  · simp only [upd, ite_eq_right hin]; exact hs i

/-- Freeing one of the thread's own addresses frees it in the thread's part. -/
theorem split_free {a a1 a2 : Nat → Bool} (hs : Split a a1 a2) {n : Nat} (h1 : a1 n = true) :
    Split (upd a n false) (upd a1 n false) a2 := by
  intro i
  by_cases hin : i = n
  · subst hin; simp [upd, hs.not_right h1]
  · simp only [upd, ite_eq_right hin]; exact hs i

end A3
