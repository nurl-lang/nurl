module

@[expose] public section

/-!
# B7: the cycle collector's criterion (AGORA-970)

`Rc` blocks whose payload can reach an `Rc` are collected by the runtime's
synchronous cycle collector (`stdlib/runtime_core.c`, Bacon & Rajan's trial
deletion, docs/MEMORY.md §7.7). From the buffered possible roots it walks
the candidates `S` (the roots and what they reach), subtracts from each
candidate's strong count the handles other candidates hold on it ("mark
gray"), and then restores everything reachable from a candidate whose
count stayed above zero ("scan" / "mark black"). What is left white is
freed.

This file proves the criterion that makes the free safe, on an abstract
heap. A block's strong count is its outside handles (`ext`: the strong
handles not represented in the edges, such as locals and globals) plus one
for each handle a block holds on it (the edges, which include the fields of
non-candidates): the two must not overlap, so each strong handle is counted
once. Then every white block has no outside handle, and every handle
held on it comes from another white block. Freeing the white blocks'
payloads together leaves no strong handle anywhere that points into them.
(A `Weak` may remain on a white block: its payload is dropped, and its
block stays allocated until the weak count reaches zero.) The collector's own walks (iterative, one context, no lock) are the
runtime's C, phase D's to check against this.
-/

namespace B

/-- The heap as the collector sees it: the handles blocks hold on blocks
    (`src, dst` pairs, one per handle), and each block's outside handles. -/
structure RcGraph where
  edges : List (Nat × Nat)
  ext   : Nat → Nat

/-- A block's strong count: its outside handles and the handles blocks hold
    on it. -/
def RcGraph.count (g : RcGraph) (n : Nat) : Nat :=
  g.ext n + g.edges.countP fun e => e.2 = n

/-- The handles candidates in `S` hold on `n`: what "mark gray" takes off. -/
def RcGraph.inside (g : RcGraph) (S : List Nat) (n : Nat) : Nat :=
  g.edges.countP fun e => e.2 = n ∧ e.1 ∈ S

/-- The count after trial deletion. -/
def RcGraph.trial (g : RcGraph) (S : List Nat) (n : Nat) : Nat := g.count n - g.inside S n

/-- Black: a candidate whose trial count is above zero, and every candidate
    a black one holds a handle on (`scan` / `mark black`). -/
inductive Black (g : RcGraph) (S : List Nat) : Nat → Prop
  | pos {n : Nat} : n ∈ S → 0 < g.trial S n → Black g S n
  | step {m n : Nat} : Black g S m → (m, n) ∈ g.edges → n ∈ S → Black g S n

/-- White: a candidate that is not black. These are what the collector frees. -/
def White (g : RcGraph) (S : List Nat) (n : Nat) : Prop := n ∈ S ∧ ¬ Black g S n

theorem countP_split (l : List (Nat × Nat)) (n : Nat) (S : List Nat) :
    l.countP (fun e => e.2 = n) =
      l.countP (fun e => e.2 = n ∧ e.1 ∈ S) + l.countP (fun e => e.2 = n ∧ e.1 ∉ S) := by
  induction l with
  | nil => rfl
  | cons e l ih =>
    simp only [List.countP_cons]
    rw [ih]
    by_cases h2 : e.2 = n <;> by_cases h1 : e.1 ∈ S <;> simp [h1, h2] <;> omega

/-- The trial count is the outside handles plus the handles that blocks
    outside `S` hold. -/
theorem trial_eq (g : RcGraph) (S : List Nat) (n : Nat) :
    g.trial S n = g.ext n + g.edges.countP (fun e => e.2 = n ∧ e.1 ∉ S) := by
  unfold RcGraph.trial RcGraph.count RcGraph.inside
  rw [countP_split g.edges n S]
  omega

/-- The collector's criterion is sound. A white block has no outside
    handle, and every handle held on it is held by a white block. -/
theorem white_closed {g : RcGraph} {S : List Nat} {n : Nat} (hw : White g S n) :
    g.ext n = 0 ∧ ∀ m, (m, n) ∈ g.edges → White g S m := by
  obtain ⟨hn, hnb⟩ := hw
  have ht : g.trial S n = 0 := by
    apply Classical.byContradiction
    intro h
    exact hnb (Black.pos hn (by omega))
  rw [trial_eq] at ht
  have hout : g.edges.countP (fun e => e.2 = n ∧ e.1 ∉ S) = 0 := by omega
  refine ⟨by omega, fun m hm => ?_⟩
  have hmS : m ∈ S := by
    apply Classical.byContradiction
    intro hmS
    have : 0 < g.edges.countP (fun e => e.2 = n ∧ e.1 ∉ S) :=
      List.countP_pos_iff.mpr ⟨(m, n), hm, by simp [hmS]⟩
    omega
  exact ⟨hmS, fun hmb => hnb (Black.step hmb hm hn)⟩

/-- Freeing the white blocks together leaves no strong handle into them.
    Every strong handle the heap still holds after the free (an outside
    handle, or a handle a surviving block holds) points at a block that is
    not freed. (Weak handles are not covered.) -/
theorem collect_safe {g : RcGraph} {S : List Nat} :
    (∀ n, White g S n → g.ext n = 0) ∧
    (∀ m n, (m, n) ∈ g.edges → ¬ White g S m → ¬ White g S n) := by
  refine ⟨fun n hw => (white_closed hw).1, fun m n he hm hn => hm ((white_closed hn).2 m he)⟩

end B
