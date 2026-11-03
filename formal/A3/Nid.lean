import A3.BorFree

/-! A3.0 — what one thread's step does to the others: it moves the shared
`nid` up, and (A3.1) adds blocks, whose payloads the shared part of the
address space gains, and nothing else they see.  A2's per-thread facts
survive that (`ThreadOK.grow`): `HeapOK.alloc` bounds owned addresses from
above, and a new payload holds none of the other threads' addresses. -/

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

theorem CatchOK.of_st {m m' : Mem} (hst : m'.st = m.st) (hnv : m.nv ≤ m'.nv) (hb : BlkLe m.blk m'.blk) :
    ∀ {s : Stmt}, CatchOK m s → CatchOK m' s
  | .seq a _, h => CatchOK.of_st hst hnv hb (s := a) h
  | .scope _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .scopeD _ _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .rbind _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .frozen _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .catchR x m0 k, h => by
    obtain ⟨h1, h2, h3, h4, h5⟩ := h
    exact ⟨fun v hv hx => by rw [hst]; exact h1 v hv hx, h2, Nat.le_trans h3 hnv,
      fun k' bl hk hr => hb k' bl (h4 k' bl hk hr), CatchOK.of_st hst hnv hb (s := k) h5⟩
  | .skip, _ => trivial
  | .letv .., _ => trivial
  | .letcall .., _ => trivial
  | .assign .., _ => trivial
  | .ite .., _ => trivial
  | .while .., _ => trivial
  | .push .., _ => trivial
  | .free .., _ => trivial
  | .panic, _ => trivial
  | .letrec .., _ => trivial
  | .unpair .., _ => trivial
  | .callc .., _ => trivial
  | .letd .., _ => trivial
  | .edit .., _ => trivial

/-- What A2 knows of one thread, on the thread's own part of the address
    space: its statement is typed, the invariant holds, its packages' codes
    are typed, and every binding is in a run-time scope it is inside of. -/
def ThreadOK (P : Prog) (m : Mem) (s : Stmt) : Prop :=
  ∃ Γ F Δ, StmtT P Γ F s Δ ∧ Inv m Γ F s ∧ MemCodes P m ∧ s.codesOK P ∧ Closed Γ s

/-- A3.1: an address the payload of a block of `B` owns. -/
def PayIn (B : Nat → Option Blk) (i : Nat) : Prop := ∃ k bl, B k = some bl ∧ i ∈ bl.pay.ids

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
  ok    : bl.ty.ok = true ∧ bl.ty.holdsView = false ∧ WFv bl.ty bl.pay ∧ SharesIn B bl.ty bl.pay
  key   : k < n
  nodup : bl.pay.ids.Nodup
  lt    : ∀ i ∈ bl.pay.ids, i < n
  apart : ∀ i ∈ bl.pay.ids, ∀ k' bl', k' ≠ k → B k' = some bl' → i ∉ bl'.pay.ids

/-- A3.1: every block of `B` is as `BlockOK` says. -/
def BlocksAt (B : Nat → Option Blk) (n : Nat) : Prop := ∀ k bl, B k = some bl → BlockOK B n k bl

/-- **Another thread allocated, or made a block**: a later `nid`, more blocks,
    and the address space grown by their payloads keep every per-thread
    fact, when the new payloads hold none of the thread's addresses. -/
theorem inv_grow {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) {A : Nat → Bool}
    {n : Nat} {B : Nat → Option Blk} (ha : ∀ i, m.alloc i = true → A i = true)
    (hA : ∀ i, A i = true → m.alloc i = true ∨ PayIn B i) (hpA : ∀ i, PayIn B i → A i = true)
    (hn : m.nid ≤ n) (hb : BlkLe m.blk B) (hB : BlocksAt B n) (hP : ∀ i, PayIn B i → ∀ x T, OwnedAt m x T → i ∉ T.ids) :
    Inv { m with alloc := A, nid := n, blk := B } Γ F s :=
  { toMInv := hi.toMInv.grow rfl (HeapOK.mono hi.heap rfl ha hn
        (fun k bl hk => ⟨(hB k bl hk).key, (hB k bl hk).nodup, fun i hi' =>
          ⟨hpA i ⟨k, bl, hk, hi'⟩, (hB k bl hk).lt i hi',
           fun x T hT => hP i ⟨k, bl, hk, hi'⟩ x T hT, (hB k bl hk).apart i hi'⟩⟩))
      (Nat.le_refl _) hb (fun k bl hk => (hB k bl hk).ok)
    nvS := hi.nvS, nvF := hi.nvF
    anch := hi.anch, spineNd := hi.spineNd, spineDom := hi.spineDom
    catchOK := CatchOK.of_st (m := m) (m' := { m with alloc := A, nid := n, blk := B }) rfl (Nat.le_refl _) hb
      hi.catchOK
    cover := fun i h => by
      rcases hA i h with h | h
      · exact (hi.cover i h).imp id (fun ⟨k, bl, hk, hik⟩ => ⟨k, bl, hb k bl hk, hik⟩)
      · exact Or.inr h,
    pinOut := hi.pinOut, pinIn := hi.pinIn, dtorOut := hi.dtorOut,
    dtorIn := hi.dtorIn }

theorem ThreadOK.grow {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {A : Nat → Bool} {n : Nat}
    {B : Nat → Option Blk} (ha : ∀ i, m.alloc i = true → A i = true)
    (hA : ∀ i, A i = true → m.alloc i = true ∨ PayIn B i) (hpA : ∀ i, PayIn B i → A i = true)
    (hn : m.nid ≤ n) (hb : BlkLe m.blk B) (hB : BlocksAt B n) (hP : ∀ i, PayIn B i → ∀ x T, OwnedAt m x T → i ∉ T.ids) :
    ThreadOK P { m with alloc := A, nid := n, blk := B } s := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := h
  exact ⟨Γ, F, Δ, ht, inv_grow hi ha hA hpA hn hb hB hP, hcd.of_st rfl, hsc, hc⟩

/-- The blocks a thread's facts give. -/
theorem ThreadOK.blocksAt {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) : BlocksAt m.blk m.nid := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  intro k bl hk
  obtain ⟨hkey, hnd, hall⟩ := hi.heap.blk k bl hk
  exact ⟨hi.blocks k bl hk, hkey, hnd, fun i h => (hall i h).2.1, fun i h => (hall i h).2.2.2⟩

end A3
