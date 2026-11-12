import A3.BorFree

/-! A3.0 — what one thread's step does to the others: it moves the shared
`nid` up, and (A3.1) adds blocks, whose payloads the shared part of the
address space gains, and nothing else they see.  A2's per-thread facts
survive that (`ThreadOK.move`): `HeapOK.alloc` bounds owned addresses from
above, and a new payload holds none of the other threads' addresses.
(A3.2: a lock block's payload may also leave the shared part, checked out
to the stepping thread, or come back into it.) -/

namespace A3
open A2

/-- The same slots and blocks, more allocated and a later `nid`: every block
    still owns its payload. -/
theorem BlkOwn.grow {m m' : Mem} (h : BlkOwn m) (hst : m'.st = m.st) (hb : m'.blk = m.blk)
    (ha : ∀ i, m.alloc i = true → m'.alloc i = true) (hn : m.nid ≤ m'.nid) : BlkOwn m' := by
  intro k bl hk
  rw [hb] at hk
  obtain ⟨hkey, hnd, hall⟩ := h k bl hk
  refine ⟨Nat.lt_of_lt_of_le hkey hn, hnd, fun i hi => ?_⟩
  obtain ⟨ha1, hlt, hsl, hoth⟩ := hall i hi
  exact ⟨ha i ha1, Nat.lt_of_lt_of_le hlt hn,
    fun x T hT => hsl x T (by unfold OwnedAt at *; rw [← hst]; exact hT),
    fun k' bl' hk' hk'' => hoth k' bl' hk' (by rw [← hb]; exact hk'')⟩

/-- More allocated and a later `nid`: the same owned trees stay valid. -/
theorem heapOK_grow {m m' : Mem} (hh : HeapOK m) (hst : m'.st = m.st)
    (ha : ∀ i, m.alloc i = true → m'.alloc i = true) (hn : m.nid ≤ m'.nid) (hb : m'.blk = m.blk := by rfl) :
    HeapOK m' where
  nodup x t h := hh.nodup x t (by unfold OwnedAt at *; rw [← hst]; exact h)
  disj x y t u hne h1 h2 := hh.disj x y t u hne (by unfold OwnedAt at *; rw [← hst]; exact h1)
    (by unfold OwnedAt at *; rw [← hst]; exact h2)
  alloc x t h i hi := by
    have h' : OwnedAt m x t := by unfold OwnedAt at *; rw [← hst]; exact h
    obtain ⟨h1, h2⟩ := hh.alloc x t h' i hi
    exact ⟨ha i h1, Nat.lt_of_lt_of_le h2 hn⟩
  self x t h := hh.self x t (by unfold OwnedAt at *; rw [← hst]; exact h)
  blk := BlkOwn.grow hh.blk hst hb ha hn
  views := by rw [hb]; exact hh.views


/-- What A2 knows of one thread, on the thread's own part of the address
    space: its statement is typed, the invariant holds, its packages' codes
    are typed, and every binding is in a run-time scope it is inside of. -/
def ThreadOK (P : Prog) (m : Mem) (s : Stmt) : Prop :=
  ∃ Γ F Δ, StmtT P Γ F s Δ ∧ Inv m Γ F s ∧ MemCodes P m ∧ s.codesOK P ∧ Closed Γ s

/-- A3.1: an address the payload of a block of `B` owns. -/
def PayIn (B : Nat → Option Blk) (i : Nat) : Prop := ∃ k bl, B k = some bl ∧ i ∈ bl.tree.ids

open Classical in
/-- A3.1: the shared, read-only part of the address space: every address a
    live block's payload owns.  Every thread reads it (`ownView`); no step
    writes it while its block exists (`Step.blk`). -/
noncomputable def payPart (B : Nat → Option Blk) : Nat → Bool := fun i => decide (PayIn B i)

theorem payPart_iff {B : Nat → Option Blk} {i : Nat} : payPart B i = true ↔ PayIn B i := by
  simp [payPart]

theorem payPart_false {B : Nat → Option Blk} {i : Nat} : payPart B i = false ↔ ¬ PayIn B i := by
  simp [payPart]

/-- A3.1: what a block of the store `B` is, for every thread that reads it:
    a well-formed payload at a key below `n`, owning its addresses once,
    below `n` and apart from every other payload's. -/
structure BlockOK (B : Nat → Option Blk) (n k : Nat) (bl : Blk) : Prop where
  ok    : bl.ty.ok = true ∧ bl.ty.holdsView = false ∧
    (∀ p, bl.pay = some p → WFv bl.ty p ∧ SharesIn B bl.ty p) ∧ (bl.kind = .lock ∨ bl.ty.hasCell = false) ∧
    -- A2-drop.3d, Agora #610: a lock's or a view's payload owns no
    -- destructor value; an `arc` block's may be one at its top (Agora #755:
    -- or a drained `Vec` of them), and a `dead` block's is (`Blk.DtorOK`,
    -- `MInv.blocks`)
    bl.DtorOK
  key   : k < n
  nodup : bl.tree.ids.Nodup
  lt    : ∀ i ∈ bl.tree.ids, i < n
  apart : ∀ i ∈ bl.tree.ids, ∀ k' bl', k' ≠ k → B k' = some bl' → i ∉ bl'.tree.ids
  /-- A3.3: a view reads its lock block's payload (`ViewsAt`). -/
  view  : bl.kind = .view →
    ∃ k0 t p, bl = ⟨.prod (.lk t) t, .view, some (.pair (.lk k0) p)⟩ ∧ B k0 = some ⟨t, .lock, some p⟩

/-- A3.1: every block of `B` is as `BlockOK` says. -/
def BlocksAt (B : Nat → Option Blk) (n : Nat) : Prop := ∀ k bl, B k = some bl → BlockOK B n k bl

theorem BlocksAt.views {B : Nat → Option Blk} {n : Nat} (h : BlocksAt B n) : ViewsAt B :=
  fun k bl hk hv => (h k bl hk).view hv

/-- **Another thread stepped**: a later `nid`, the blocks kept as their
    holders see them (`BlkLe`: more blocks, and (A3.2) a lock block's payload
    checked out or back in), and the address space the thread sees being its
    owned trees and the blocks' payloads, which hold none of its
    addresses. -/
theorem inv_move {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) {A : Nat → Bool}
    {n : Nat} {B : Nat → Option Blk}
    (hown : ∀ x T, OwnedAt m x T → ∀ i ∈ T.ids, A i = true)
    (hA : ∀ i, A i = true → (∃ x T, OwnedAt m x T ∧ i ∈ T.ids) ∨ PayIn B i)
    (hpA : ∀ i, PayIn B i → A i = true)
    (hn : m.nid ≤ n) (hb : BlkLe m.blk B) (hB : BlocksAt B n)
    (hP : ∀ i, PayIn B i → ∀ x T, OwnedAt m x T → i ∉ T.ids) :
    Inv { m with alloc := A, nid := n, blk := B } Γ F s :=
  have hh : HeapOK { m with alloc := A, nid := n, blk := B } :=
    { nodup := hi.heap.nodup
      disj := hi.heap.disj
      alloc := fun x t h i hi' => ⟨hown x t h i hi', Nat.lt_of_lt_of_le (hi.heap.alloc x t h i hi').2 hn⟩
      self := hi.heap.self
      blk := fun k bl hk => ⟨(hB k bl hk).key, (hB k bl hk).nodup, fun i hi' =>
          ⟨hpA i ⟨k, bl, hk, hi'⟩, (hB k bl hk).lt i hi',
           fun x T hT => hP i ⟨k, bl, hk, hi'⟩ x T hT, (hB k bl hk).apart i hi'⟩⟩
      views := hB.views }
  { toMInv := hi.toMInv.grow rfl hh (Nat.le_refl _) hb (fun k bl hk => (hB k bl hk).ok)
    nvS := hi.nvS, nvF := hi.nvF
    anch := hi.anch, spineNd := hi.spineNd, spineDom := hi.spineDom
    catchOK := CatchOK.of_st (m := m) (m' := { m with alloc := A, nid := n, blk := B }) rfl (Nat.le_refl _) hb
      hi.catchOK
    cover := fun i h => by
      rcases hA i h with ⟨x, T, hT, hiT⟩ | h
      · exact Or.inl ⟨x, T, hT, hiT⟩
      · exact Or.inr h,
    pinOut := hi.pinOut, pinIn := hi.pinIn, dtorOut := hi.dtorOut,
    dtorIn := hi.dtorIn }

theorem ThreadOK.move {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {A : Nat → Bool} {n : Nat}
    {B : Nat → Option Blk} (hown : ∀ x T, OwnedAt m x T → ∀ i ∈ T.ids, A i = true)
    (hA : ∀ i, A i = true → (∃ x T, OwnedAt m x T ∧ i ∈ T.ids) ∨ PayIn B i)
    (hpA : ∀ i, PayIn B i → A i = true)
    (hn : m.nid ≤ n) (hb : BlkLe m.blk B) (hB : BlocksAt B n) (hBc : BlkCodes P B)
    (hP : ∀ i, PayIn B i → ∀ x T, OwnedAt m x T → i ∉ T.ids) :
    ThreadOK P { m with alloc := A, nid := n, blk := B } s := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := h
  exact ⟨Γ, F, Δ, ht, inv_move hi hown hA hpA hn hb hB hP, hcd.withBlk rfl hBc, hsc, hc⟩

/-- A3.5b: the packages the blocks hold, which a thread's facts give. -/
theorem ThreadOK.blkCodes {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) : BlkCodes P m.blk := by
  obtain ⟨_, _, _, _, _, hcd, _, _⟩ := h
  exact hcd.blk

/-- The blocks a thread's facts give. -/
theorem ThreadOK.blocksAt {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) : BlocksAt m.blk m.nid := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  intro k bl hk
  obtain ⟨hkey, hnd, hall⟩ := hi.heap.blk k bl hk
  exact ⟨hi.blocks k bl hk, hkey, hnd, fun i h => (hall i h).2.1, fun i h => (hall i h).2.2.2,
    fun hv => hi.heap.views k bl hk hv⟩

end A3
