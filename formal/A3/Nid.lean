import A3.BorFree

/-! A3.0 — what one thread's step does to the others: it moves the shared
`nid` up, and nothing else they see.  A2's per-thread facts survive that:
the only one that mentions `nid` is `HeapOK.alloc`, which bounds owned
addresses from above. -/

namespace A3
open A2

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
  blk := BlkOwn.of_none fun k bl hk => by
    rw [hb] at hk; exact ⟨hh.bpay k bl hk, Nat.lt_of_lt_of_le (hh.bkey k bl hk) hn⟩
  bpay k bl hk := hh.bpay k bl (by rw [← hb]; exact hk)

theorem CatchOK.of_st {m m' : Mem} (hst : m'.st = m.st) (hnv : m.nv ≤ m'.nv) (hb : BlkLe m.blk m'.blk) :
    ∀ {s : Stmt}, CatchOK m s → CatchOK m' s
  | .seq a _, h => CatchOK.of_st hst hnv hb (s := a) h
  | .scope _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .scopeD _ _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .rbind _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .frozen _ k, h => CatchOK.of_st hst hnv hb (s := k) h
  | .catchR x m0 k, h => by
    obtain ⟨h1, h2, h3, h4, h5⟩ := h
    exact ⟨fun v hv hx => by rw [hst]; exact h1 v hv hx, h2, Nat.le_trans h3 hnv, h4.trans hb,
      CatchOK.of_st hst hnv hb (s := k) h5⟩
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

theorem inv_of_st {m m' : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s)
    (hst : m'.st = m.st) (hnv : m'.nv = m.nv) (hh : HeapOK m') (hc : Covers m')
    (hb : m'.blk = m.blk := by rfl) : Inv m' Γ F s :=
  { toMInv := hi.toMInv.of_st hst hh (by rw [hnv]; exact Nat.le_refl _) hb
    nvS := fun v hv => by rw [hnv]; exact hi.nvS v hv
    nvF := fun v hv => by rw [hnv]; exact hi.nvF v hv
    anch := hi.anch, spineNd := hi.spineNd, spineDom := hi.spineDom
    catchOK := CatchOK.of_st hst (by rw [hnv]; exact Nat.le_refl _) (BlkLe.of_eq hb) hi.catchOK
    cover := hc, pinOut := hi.pinOut, pinIn := hi.pinIn, dtorOut := hi.dtorOut, dtorIn := hi.dtorIn }

/-- **Another thread allocated**: a later `nid` keeps every per-thread fact. -/
theorem inv_nid_le {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) {n : Nat}
    (hn : m.nid ≤ n) : Inv { m with nid := n } Γ F s :=
  inv_of_st hi rfl rfl (heapOK_grow hi.heap rfl (fun _ h => h) hn) (fun i h => hi.cover i h)

/-- What A2 knows of one thread, on the thread's own part of the address
    space: its statement is typed, the invariant holds, its packages' codes
    are typed, and every binding is in a run-time scope it is inside of. -/
def ThreadOK (P : Prog) (m : Mem) (s : Stmt) : Prop :=
  ∃ Γ F Δ, StmtT P Γ F s Δ ∧ Inv m Γ F s ∧ MemCodes P m ∧ s.codesOK P ∧ Closed Γ s

theorem ThreadOK.nid_le {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {n : Nat}
    (hn : m.nid ≤ n) : ThreadOK P { m with nid := n } s := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := h
  exact ⟨Γ, F, Δ, ht, inv_nid_le hi hn, hcd.of_st rfl, hsc, hc⟩

/-- A3.1: what the blocks of a store are, for every thread that reads them:
    well-formed payloads, which own no address, at keys below `nid`. -/
def BlocksAt (B : Nat → Option Blk) (n : Nat) : Prop :=
  ∀ k bl, B k = some bl → (bl.ty.ok = true ∧ bl.ty.holdsView = false ∧ WFv bl.ty bl.pay ∧
    SharesIn B bl.ty bl.pay) ∧ bl.pay.ids = [] ∧ k < n

/-- **Another thread allocated, or made a block**: a later `nid` and more
    blocks keep every per-thread fact. -/
theorem inv_grow {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt} (hi : Inv m Γ F s) {n : Nat}
    {B : Nat → Option Blk} (hn : m.nid ≤ n) (hb : BlkLe m.blk B) (hB : BlocksAt B n) :
    Inv { m with nid := n, blk := B } Γ F s :=
  { toMInv := hi.toMInv.grow rfl (HeapOK.mono hi.heap rfl (fun _ h => h) hn
        (BlkOwn.of_none fun k bl hk => (hB k bl hk).2) (fun k bl hk => (hB k bl hk).2.1))
      (Nat.le_refl _) hb (fun k bl hk => (hB k bl hk).1)
    nvS := hi.nvS, nvF := hi.nvF
    anch := hi.anch, spineNd := hi.spineNd, spineDom := hi.spineDom
    catchOK := CatchOK.of_st (m := m) (m' := { m with nid := n, blk := B }) rfl (Nat.le_refl _) hb hi.catchOK
    cover := fun i h => hi.cover i h, pinOut := hi.pinOut, pinIn := hi.pinIn, dtorOut := hi.dtorOut,
    dtorIn := hi.dtorIn }

theorem ThreadOK.grow {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {n : Nat}
    {B : Nat → Option Blk} (hn : m.nid ≤ n) (hb : BlkLe m.blk B) (hB : BlocksAt B n) :
    ThreadOK P { m with nid := n, blk := B } s := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := h
  exact ⟨Γ, F, Δ, ht, inv_grow hi hn hb hB, hcd.of_st rfl, hsc, hc⟩

/-- The blocks a thread's facts give. -/
theorem ThreadOK.blocksAt {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) : BlocksAt m.blk m.nid := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  exact fun k bl hk => ⟨hi.blocks k bl hk, hi.heap.bpay k bl hk, hi.heap.bkey k bl hk⟩

end A3
