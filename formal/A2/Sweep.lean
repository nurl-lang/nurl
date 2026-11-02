import A2.Heap

/-! A2 — A3.1's sweep: the blocks nothing reaches are removed, and their
payloads freed (`Mem.sweep`).  It touches nothing else: the slots, `nid` and
`nv` stay, every reached block stays as it was, and only the addresses of
the unreached payloads are freed — none of which an owned tree or a reached
payload holds (`HeapOK.sweep`). -/

namespace A2

@[simp] theorem Mem.sweep_st (m : Mem) : m.sweep.st = m.st := rfl
@[simp] theorem Mem.sweep_nv (m : Mem) : m.sweep.nv = m.nv := rfl
@[simp] theorem Mem.sweep_nid (m : Mem) : m.sweep.nid = m.nid := rfl
@[simp] theorem Mem.sweep_vals (m : Mem) : m.sweep.vals = m.vals := rfl

theorem sweepBlk_some {R : Val → Prop} {B : Nat → Option Blk} {k : Nat} {bl : Blk} :
    sweepBlk R B k = some bl ↔ B k = some bl ∧ Reached R B k := by
  unfold sweepBlk
  by_cases h : Reached R B k
  · simp [h]
  · simp [h]

theorem sweepAlloc_true {R : Val → Prop} {B : Nat → Option Blk} {a : Nat → Bool} {i : Nat} :
    sweepAlloc R B a i = true ↔ a i = true ∧ ¬ Unreached R B i := by
  unfold sweepAlloc
  by_cases h : Unreached R B i
  · simp [h]
  · simp [h]

/-- The swept store keeps exactly the reached blocks. -/
theorem Mem.sweep_blk {m : Mem} {k : Nat} {bl : Blk} :
    m.sweep.blk k = some bl ↔ m.blk k = some bl ∧ Reached m.vals m.blk k :=
  sweepBlk_some

/-- The swept store keeps every block it keeps as it was. -/
theorem Mem.sweep_blkLe (m : Mem) : BlkLe m.sweep.blk m.blk := fun _ _ h => (Mem.sweep_blk.mp h).1

/-- An address stays live unless an unreached payload owns it. -/
theorem Mem.sweep_alloc {m : Mem} {i : Nat} :
    m.sweep.alloc i = true ↔ m.alloc i = true ∧ ¬ Unreached m.vals m.blk i :=
  sweepAlloc_true

/-- What a block refers to through more blocks, it still refers to. -/
theorem Refers.grow {B B' : Nat → Option Blk} (hb : BlkLe B B') {v : Val} {k : Nat} (h : Refers B v k) :
    Refers B' v k := by
  rcases h with h | ⟨bl, hk, h⟩
  · exact Or.inl h
  · exact Or.inr ⟨bl, hb k bl hk, h⟩

/-- Reachability from more values, through more blocks. -/
theorem Reached.mono {R R' : Val → Prop} {B B' : Nat → Option Blk} (hR : ∀ v, R v → R' v)
    (hb : BlkLe B B') {k : Nat} (h : Reached R B k) : Reached R' B' k := by
  induction h with
  | root hv hr => exact .root (hR _ hv) (hr.grow hb)
  | pay _ hk hr ih => exact .pay ih (hb _ _ hk) (hr.grow hb)

/-- A block a slot's value refers to is reached. -/
theorem Reached.of_slot {m : Mem} {x : Var} {o : Bool} {v : Val} (hx : m.st x = some ⟨o, some v⟩)
    {k : Nat} (h : Refers m.blk v k) : Reached m.vals m.blk k :=
  .root ⟨x, o, hx⟩ h

/-- Reachability in the swept store: the chains run through reached blocks
    only, which it keeps. -/
theorem Reached.sweep {m : Mem} {k : Nat} (h : Reached m.vals m.blk k) :
    Reached m.sweep.vals m.sweep.blk k := by
  induction h with
  | root hv hr =>
    rename_i v k
    refine .root hv ?_
    rcases hr with h | ⟨bl, hk, h⟩
    · exact Or.inl h
    · exact Or.inr ⟨bl, Mem.sweep_blk.mpr ⟨hk, .root hv (Or.inr ⟨bl, hk, h⟩)⟩, h⟩
  | pay hr' hk hr ih =>
    rename_i k k' bl
    refine .pay ih (Mem.sweep_blk.mpr ⟨hk, hr'⟩) ?_
    rcases hr with h | ⟨bl', hk', h⟩
    · exact Or.inl h
    · exact Or.inr ⟨bl', Mem.sweep_blk.mpr ⟨hk', .pay hr' hk (Or.inr ⟨bl', hk', h⟩)⟩, h⟩

/-- **The sweep keeps the heap's invariant**: the owned trees are as they
    were, and their addresses, and the reached payloads', stay live — the
    sweep frees only what an unreached payload owns, which no owned tree and
    no other payload holds. -/
theorem HeapOK.sweep {m : Mem} (hh : HeapOK m) : HeapOK m.sweep where
  nodup x t h := hh.nodup x t h
  disj x y t u hne h1 h2 := hh.disj x y t u hne h1 h2
  alloc x t h i hi := by
    obtain ⟨ha, hlt⟩ := hh.alloc x t h i hi
    refine ⟨Mem.sweep_alloc.mpr ⟨ha, ?_⟩, hlt⟩
    rintro ⟨k, bl, hk, _, hik⟩
    exact hh.notPay h hi ⟨k, bl, hk, hik⟩
  self x t h := hh.self x t h
  blk k bl hk := by
    obtain ⟨hk0, hreach⟩ := Mem.sweep_blk.mp hk
    obtain ⟨hkey, hnd, hall⟩ := hh.blk k bl hk0
    refine ⟨hkey, hnd, fun i hi => ?_⟩
    obtain ⟨ha, hlt, hsl, hoth⟩ := hall i hi
    refine ⟨Mem.sweep_alloc.mpr ⟨ha, ?_⟩, hlt, hsl, fun k' bl' hk' hk'' => hoth k' bl' hk'
      (Mem.sweep_blk.mp hk'').1⟩
    rintro ⟨k', bl', hk', hnr, hik'⟩
    by_cases he : k' = k
    · subst he; rw [hk0] at hk'; cases hk'; exact hnr hreach
    · exact hoth k' bl' he hk' hik'
  bpay k bl hk := hh.bpay k bl (Mem.sweep_blk.mp hk).1

end A2
