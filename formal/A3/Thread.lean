import A3.Ghost

/-! A3.0 — A2's theorems, as facts about one thread on its own part of the
address space (`ThreadOK`), and the algebra of the parts. -/

namespace A3
open A2

/-- The program's start: the one thread, on the empty store. -/
theorem ThreadOK.init {P : Prog} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) : ThreadOK P (emptyMem nv) s :=
  ⟨fun _ => none, [], Δ, ht, inv_empty hs hv, codes_empty P nv, hsc, closed_empty s⟩

/-- A3.6: the empty store with the module globals `g` set, and none of their
    blocks yet: A2's `inv_empty`, which reads no global. -/
theorem inv_emptyGl {s : Stmt} {nv : Nat} (g : Nat → Option Val) (T : Nat → Bool) (hs : s.src = true)
    (hv : ∀ v ∈ s.vars, v < nv) : Inv { emptyMem nv with gl := g, taken := T } (fun _ => none) [] s where
  dom _ := rfl
  slot _ _ h := by cases h
  heap := ⟨fun _ _ h => (by cases h), fun _ _ _ _ _ h => (by cases h), fun _ _ h => (by cases h),
    fun _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h)⟩
  nvSt _ h := by cases h
  noInout _ _ _ h := by cases h
  wf := ⟨fun _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h),
    fun _ _ h => (by cases h)⟩
  rootbLive _ _ h := by cases h
  rootbLt _ _ h := by cases h
  names _ _ h := by cases h
  held _ _ _ _ h := by cases h
  pkgs _ _ _ h := by cases h
  armed _ _ _ h := by cases h
  shares _ _ _ _ h := by cases h
  blocks _ _ h := by cases h
  nvS := hv
  nvF _ h := by cases h
  anch _ _ h := by cases h
  spineNd := by rw [src_spine hs]; exact List.nodup_nil
  spineDom v h := by rw [src_spine hs] at h; cases h
  catchOK := catchOK_src hs
  cover _ h := by cases h
  pinOut _ _ h := by cases h
  pinIn := PinOK.of_spine_nil (src_spine hs)
  dtorOut _ _ h := by cases h
  dtorIn := DtorPinOK.of_spine_nil (src_spine hs)

/-- Agora #815: no global keeps lock and cell shares apart. -/
theorem GlobsKinds.empty : GlobsKinds Globs.empty :=
  ⟨fun _ => false, fun _ _ _ _ h => (by cases h), fun _ _ h => (by cases h)⟩

/-- A3.6: no global is a start the claim admits: A3.0–A3.5's. -/
theorem GlobsOK.empty {P : Prog} : GlobsOK P Globs.empty where
  sync _ _ h := by cases h
  inv := (inv_empty (s := .skip) (nv := 0) rfl (fun _ h => by cases h)).toMInv
  cover _ h := by cases h
  reach _ _ h := by cases h
  codes _ _ h := by cases h
  dtors _ _ h := by cases h
  cells _ _ _ h := by obtain ⟨_, _, h, _⟩ := h; cases h
  kinds := GlobsKinds.empty

/-- A3.6: the blocks the globals' `make`s left are as every thread's view
    needs them ... -/
theorem GlobsOK.blocksAt {P : Prog} {G : Globs} (hG : GlobsOK P G) : BlocksAt G.blk G.nid := by
  intro k bl hk
  obtain ⟨hkey, hnd, hall⟩ := hG.inv.heap.blk k bl hk
  exact ⟨hG.inv.blocks k bl hk, hkey, hnd, fun i h => (hall i h).2.1, fun i h => (hall i h).2.2.2,
    fun hv => hG.inv.heap.views k bl hk hv⟩

/-- Agora #610: no block the globals' `make`s left is `dead`: each is reached
    from a global (`GlobsOK.reach`), and nothing reaches an orphan
    (`Reached.not_dead`). -/
theorem GlobsOK.noDead {P : Prog} {G : Globs} (hG : GlobsOK P G) {k : Nat} {bl : Blk}
    (hk : G.blk k = some bl) : bl.kind ≠ .dead := by
  have hB : ∀ k bl p, G.blk k = some bl → bl.pay = some p → WFv bl.ty p ∧ SharesIn G.blk bl.ty p :=
    fun k bl p hk hp => (hG.inv.blocks k bl hk).2.2.1 p hp
  refine Reached.not_dead (fun v ⟨g, hg⟩ => ?_) hB (hG.reach k bl hk) hk
  obtain ⟨t, _, htok, hfit⟩ := hG.sync g v hg
  rcases hfit with ⟨u, k', o, rfl, rfl, hk'⟩ | ⟨u, k', p, rfl, rfl, hk'⟩
  · refine ⟨.lk u, WFv.lk, fun u' k'' p' ha => ?_⟩
    cases ha
    exact ⟨o, hk'⟩
  · have hwp : WFv u p ∧ u.holdsView = false := by
      have h := hk'.arc (Ty.isGuard_of_hasGuard (Ty.ok_arc_guard htok))
      exact ⟨((hB k' _ p h rfl).1), (hG.inv.blocks k' _ h).2.1⟩
    refine ⟨.arc u, WFv.arc hwp.1 hwp.2, fun u' k'' p' ha => ?_⟩
    cases ha
    exact hk'

/-- Agora #755 item 1: the reaps that end a thread's step leave no orphan. -/
theorem CSettle.noOrphan {P : Prog} {i : Nat} {C C' : Cfg} (h : CSettle P i C C') : ¬ C'.Orphan := by
  induction h with
  | done hn => exact hn
  | reap _ _ _ _ ih => exact ih

/-- Agora #610: **no configuration a run reaches has an orphan** (item 7 of
    #610's review): a thread's step ends with the reaps of every orphan its
    marking sweep left (Agora #755 item 1, `CSettle`), and a spawn changes no
    block.  So the hypothesis of the lock scope's end (`scopeL_end`) holds on
    every A3 run, and no thread ever sees another's mark. -/
theorem Reach.noOrphan {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (hr : Reach P spawn C C')
    (h : ¬ ∃ k n f u p, C.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩) :
    ¬ ∃ k n f u p, C'.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ := by
  induction hr with
  | refl => exact h
  | step hst _ ih =>
    apply ih
    cases hst with
    | thread _ _ _ hse => exact hse.noOrphan
    | spawn => exact h
    | spawnFail => exact h

/-- ... and none at the start the claim admits: no global's block is `dead`. -/
theorem GlobsOK.noOrphan {P : Prog} {G : Globs} (hG : GlobsOK P G) :
    ¬ ∃ k n f u p, G.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩ :=
  fun ⟨_, _, _, _, _, hk⟩ => hG.noDead hk rfl

/-- ... so the blocks' packages name code of their signature, and there is
    no orphan's destructor to check (`BlkCodes`). -/
theorem GlobsOK.blkCodes {P : Prog} {G : Globs} (hG : GlobsOK P G) : BlkCodes P G.blk :=
  ⟨hG.codes, hG.dtors⟩

/-- ... and every address they left live is a payload's. -/
theorem GlobsOK.alloc {P : Prog} {G : Globs} (hG : GlobsOK P G) (i : Nat) : G.alloc i = true ↔ PayIn G.blk i := by
  constructor
  · intro h
    rcases hG.cover i h with ⟨x, T, hT, _⟩ | hp
    · cases hT
    · exact hp
  · intro hp
    exact (hG.inv.heap.payAlloc hp).1

/-- **A3.6: the program's start, with its module globals set**: the one
    thread, with no binding, on the payloads of the blocks the globals'
    `make`s left (the empty store grown to them, `ThreadOK.move`). -/
theorem ThreadOK.start {P : Prog} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) {G : Globs} (hG : GlobsOK P G) :
    ThreadOK P { alloc := union (fun _ => false) (payPart G.blk), nid := G.nid, nv := nv,
                 st := fun _ => none, blk := G.blk, gl := G.gl, taken := G.taken } s := by
  have h0 : ThreadOK P { emptyMem nv with gl := G.gl, taken := G.taken } s :=
    ⟨fun _ => none, [], Δ, ht, inv_emptyGl G.gl G.taken hs hv,
      ⟨fun _ _ _ _ _ _ _ _ h => (by cases h), fun _ _ _ _ _ _ _ h => (by cases h),
        fun _ _ h => (by cases h)⟩, hsc, closed_empty s⟩
  exact h0.move (fun _ _ h => by cases h) (fun i hi => .inr (by simpa [union, payPart_iff] using hi))
    (fun i hi => by simp [union, payPart_iff, hi]) (Nat.zero_le _) (fun _ _ h => by cases h) hG.blocksAt
    hG.blkCodes (fun _ _ _ _ h => by cases h)

/-- A2's preservation, one step. -/
theorem ThreadOK.step {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {m : Mem} {s : Stmt}
    (h : ThreadOK P m s) {m' : Mem} {s' : Stmt} (hst : Step P m s (.ok m' s')) : ThreadOK P m' s' := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, hsc, hc⟩ := h
  obtain ⟨Γ', ht', hi', hc', hcd', hsc'⟩ := reach_ok0 hP hPc ht hcd hsc hi hc (Steps0.step hst Steps0.refl)
  exact ⟨Γ', F, Δ, ht', hi', hcd', hsc', hc'⟩

/-- A2's progress: a thread is finished, or (A3.2) waits for a lock, or it can step. -/
theorem ThreadOK.progress {P : Prog} (hP : ProgOK P) {m : Mem} {s : Stmt} (h : ThreadOK P m s) :
    s = .skip ∨ Blocked m s ∨ ∃ r, Step P m s r := by
  obtain ⟨Γ, F, Δ, ht, hi, hcd, _, _⟩ := h
  exact progress' hP ht hcd hi

/-- A3.2: waiting for a lock reads only the slots and the blocks. -/
theorem Blocked.of_eq {m m' : Mem} (hst : m'.st = m.st) (hb : m'.blk = m.blk) {s : Stmt} (h : Blocked m s) :
    Blocked m' s := by
  induction s with
  | letv _ r _ _ => exact RBlocked.of_eq hst hb (r := r) h
  | assign _ r => exact RBlocked.of_eq hst hb (r := r) h
  | letd _ _ r _ _ => exact RBlocked.of_eq hst hb (r := r) h
  | withLock a _ _ _ =>
    obtain ⟨k, t, h1, h2⟩ := h
    exact ⟨k, t, h1.of_st hst, hb ▸ h2⟩
  | seq _ _ ih _ => exact ih h
  | scope _ _ ih => exact ih h
  | rbind _ _ ih => exact ih h
  | frozen _ _ ih => exact ih h
  | catchR _ _ _ ih => exact ih h
  | scopeD _ _ _ ih => exact ih h
  | scopeL _ _ _ _ ih => exact ih h
  | _ => exact h

/-- A finished thread has no bindings. -/
theorem ThreadOK.skip_st {P : Prog} {m : Mem} (h : ThreadOK P m .skip) : ∀ x, m.st x = none := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, hc⟩ := h
  intro o
  cases ho : m.st o with
  | none => rfl
  | some sl =>
    have hd := hi.dom o
    rw [ho] at hd
    exact absurd (hc o hd) (by simp [Stmt.spine])

/-- A finished thread owns nothing: what is live on its view is the shared
    payloads. -/
theorem ThreadOK.no_leak {P : Prog} {m : Mem} (h : ThreadOK P m .skip) :
    ∀ i, m.alloc i = true → PayAddr m i := by
  have hst := h.skip_st
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  intro i ha
  rcases hi.cover i ha with ⟨o, T, hT, _⟩ | hp
  · unfold OwnedAt at hT; rw [hst o] at hT; cases hT
  · exact hp

/-- Every address live on a thread's part is below `nid`. -/
theorem ThreadOK.lt_nid {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) :
    ∀ i, m.alloc i = true → i < m.nid := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  intro i ha
  rcases hi.cover i ha with ⟨o, T, hT, hiT⟩ | hp
  · exact (hi.heap.alloc o T hT i hiT).2
  · exact (hi.heap.payAlloc hp).2

/-- Every address of a thread's owned trees is on its part. -/
theorem ThreadOK.owned {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) :
    ∀ i, OwnedId m i → m.alloc i = true := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  rintro i ⟨o, T, hT, hiT⟩
  exact (hi.heap.alloc o T hT i hiT).1

/-- Every live address of a thread's view is in an owned tree or a payload. -/
theorem ThreadOK.cover {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) : Covers m := by
  obtain ⟨Γ, F, Δ, _, hi, _, _, _⟩ := h
  exact hi.cover

/-- A thread's facts: no owned tree holds a payload address ... -/
theorem ThreadOK.notPay {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {i : Nat} (hi : OwnedId m i) :
    ¬ PayAddr m i := by
  obtain ⟨Γ, F, Δ, _, hinv, _, _, _⟩ := h
  obtain ⟨x, T, hT, hiT⟩ := hi
  exact hinv.heap.notPay hT hiT

/-- ... every payload address is live ... -/
theorem ThreadOK.payAlloc {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {i : Nat} (hi : PayAddr m i) :
    m.alloc i = true := by
  obtain ⟨Γ, F, Δ, _, hinv, _, _, _⟩ := h
  exact (hinv.heap.payAlloc hi).1

/-- ... and one payload owns each payload address. -/
theorem ThreadOK.pay_unique {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {k k' : Nat} {bl bl' : Blk}
    (hk : m.blk k = some bl) (hk' : m.blk k' = some bl') {i : Nat} (hi : i ∈ bl.tree.ids)
    (hi' : i ∈ bl'.tree.ids) : k = k' :=
  Classical.byContradiction fun hne => (h.blocksAt k bl hk).apart i hi k' bl' (Ne.symm hne) hk' hi'

/-! ### Parts -/

theorem minus_minus {a b : Nat → Bool} (h : ∀ i, b i = true → a i = true) : minus a (minus a b) = b := by
  funext i
  simp only [minus]
  cases hb : b i <;> cases ha : a i <;> simp_all

theorem union_minus {a b : Nat → Bool} (h : ∀ i, b i = true → a i = true) : union b (minus a b) = a := by
  funext i
  simp only [union, minus]
  cases hb : b i <;> cases ha : a i <;> simp_all

theorem minus_disj {a b : Nat → Bool} : ∀ i, b i = true → minus a b i = false := by
  intro i h; simp [minus, h]

theorem minus_le {a b : Nat → Bool} : ∀ i, minus a b i = true → a i = true := by
  intro i h; simp only [minus, Bool.and_eq_true] at h; exact h.1

end A3
