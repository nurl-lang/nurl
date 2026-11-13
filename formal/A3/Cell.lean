import A3.Pres
import A3.Mark
import A3.SpawnOld

/-! A3.5 — library handles whose copies are one state: confinement.

A library handle (a `PNCounter`, a `TcpConn`, a `Cell`) is a cell: a lock
block whose shares are cell shares (`Val.cell`), which the library changes
in place, through any share, with no lock.  So it is Send but not Sync: its
shares may be in one place only.  The invariant says so (`CellInv`): a
cell's owners are in one thread's owned slots, or (A3.5's second cut) in one
lock block's payload — a lock's, a cell's state, a channel's queue — never
split.  A3.5's third cut: a borrow of a handle holds the share too (a lent
cell share is the share, `lendOf`), and is not counted: a live one's owner is
on its thread (`MInv.cell_owned`, `cellAt_of_live`), and a dead one, bound
until its scope ends after its owner moved away, is never read.

A thread's own step keeps it (`Step.cellKeep`), because a step moves a
cell's owners only whole: a value going into a lock block passed the
crossing check (`SendCheck`: no owner left behind holds a share of a cell it
holds), one coming out leaves none of them behind (a check-out and a take
empty the block; a receive's head shares no cell with the rest of the
queue, `RecvCheck`); what is lent is a borrow, no owner; a borrowed value
handed on into an owner holds no cell share (`TakeVal.bor`); and a copy of a
borrowed handle is made only where an owner of it is (`EvalR.cellClone`).  A
new cell's key is taken from `nid`, which no share names yet.  A spawn keeps
it because of the crossing check too: a cell the moved values hold a share of
keeps no owner in the spawner.  So two threads never change one cell's
state at once (`CellInv.cellRaceFree`): each would hold an owner's share or a
live borrow, whose owner is on its thread. -/

namespace A3
open A2

/-! ### A cell share in a store

A3.5's third cut: what is counted is an owner's share, one in an owned slot's
tree.  A borrow of a library handle holds the share too (a lent cell share is
the share, `lendOf`), but a live borrow's owner is in the same store
(`MInv.cell_owned`), so the owners say where a cell is.  A dead borrow's slot,
still bound after its owner moved away, is never read, and is not counted, as
the runtime's count of owners does not count it. -/

/-- An owned slot of the store holds a share of cell `k` (A2's `OwnedCell`). -/
def CellAt (m : Mem) (k : Nat) : Prop := ∃ y v, m.st y = some ⟨true, some v⟩ ∧ Sub (.cell k) v

theorem CellAt.of_owned {m : Mem} {k : Nat} (h : OwnedCell m k) : CellAt m k := h

theorem CellAt.of_slot {m : Mem} {y : Var} {v : Val} (h : m.st y = some ⟨true, some v⟩) {k : Nat}
    (hs : Sub (.cell k) v) : CellAt m k := ⟨y, v, h, hs⟩

theorem CellAt.of_st {m m' : Mem} (hst : m'.st = m.st) {k : Nat} (h : CellAt m' k) : CellAt m k := by
  obtain ⟨y, v, hy, hs⟩ := h
  exact ⟨y, v, by rw [← hst]; exact hy, hs⟩

/-- A slot set: the share is in its new value, owned, or it was in an owned
    slot before. -/
theorem CellAt.set_own {m : Mem} {x : Var} {sl : Slot} {k : Nat} (h : CellAt (m.set x sl) k) :
    (∃ v, sl = ⟨true, some v⟩ ∧ Sub (.cell k) v) ∨ CellAt m k := by
  obtain ⟨y, v, hy, hs⟩ := h
  simp only [Mem.set, upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy; exact .inl ⟨v, rfl, hs⟩
  · rw [ite_eq_right hyx] at hy; exact .inr ⟨y, v, hy, hs⟩

/-- ... so the share is in its new value, or it was in an owned slot before. -/
theorem CellAt.set {m : Mem} {x : Var} {sl : Slot} {k : Nat} (h : CellAt (m.set x sl) k) :
    (∃ v, sl.val = some v ∧ Sub (.cell k) v) ∨ CellAt m k :=
  (CellAt.set_own h).imp (fun ⟨v, hv, hs⟩ => ⟨v, by rw [hv], hs⟩) id

/-- A borrowed slot set: no owner more. -/
theorem CellAt.set_bor {m : Mem} {x : Var} {o : Option Val} {k : Nat} (h : CellAt (m.set x ⟨false, o⟩) k) :
    CellAt m k :=
  (CellAt.set_own h).elim (fun ⟨_, h, _⟩ => by cases h) id

theorem CellAt.set_none {m : Mem} {x : Var} {o : Bool} {k : Nat} (h : CellAt (m.set x ⟨o, none⟩) k) :
    CellAt m k :=
  (CellAt.set h).elim (fun ⟨_, h, _⟩ => by cases h) id

theorem CellAt.of_upd {m m' : Mem} {x : Var} (hst : m'.st = upd m.st x none) {k : Nat} (h : CellAt m' k) :
    CellAt m k := by
  obtain ⟨y, v, hy, hs⟩ := h
  rw [hst] at hy
  simp only [upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy
  · rw [ite_eq_right hyx] at hy; exact ⟨y, v, hy, hs⟩

theorem CellAt.remove {m : Mem} {x : Var} {k : Nat} (h : CellAt (m.remove x) k) : CellAt m k :=
  CellAt.of_upd rfl h

/-- A node's cell shares are its elements'. -/
theorem sub_cell_node {t : Ty} {c d : Nat} {es : List Val} {k : Nat} (h : Sub (.cell k) (.node t c d es)) :
    ∃ e ∈ es, Sub (.cell k) e := by
  cases h with
  | child he hs => exact ⟨_, he, hs⟩

/-- ... so a node with fewer elements holds fewer. -/
theorem sub_cell_node_sub {t t' : Ty} {c d c' d' : Nat} {es es' : List Val} {k : Nat}
    (h : Sub (.cell k) (.node t c d es)) (hsub : ∀ e ∈ es, e ∈ es') : Sub (.cell k) (.node t' c' d' es') := by
  obtain ⟨e, he, hs⟩ := sub_cell_node h
  exact Sub.child (hsub e he) hs

/-- A tree with one node rewritten: a cell share it holds was the old tree's,
    or is in the new node. -/
theorem _root_.A2.Repl.cell {n n' T T' : Val} (h : Repl n n' T T') {k : Nat} (hs : Sub (.cell k) T') :
    Sub (.cell k) T ∨ Sub (.cell k) n' := by
  induction h with
  | here => exact .inr hs
  | @elem t c d pre post e e' _ ih =>
    obtain ⟨x, hx, hsx⟩ := sub_cell_node hs
    simp only [List.mem_append, List.mem_cons] at hx
    rcases hx with hx | rfl | hx
    · exact .inl (Sub.child (by simp [hx]) hsx)
    · rcases ih hsx with h | h
      · exact .inl (Sub.child (by simp) h)
      · exact .inr h
    · exact .inl (Sub.child (by simp [hx]) hsx)
  | fst _ ih =>
    cases hs with
    | fst h => exact (ih h).imp Sub.fst id
    | snd h => exact .inl (Sub.snd h)
  | snd _ ih =>
    cases hs with
    | fst h => exact .inl (Sub.fst h)
    | snd h => exact (ih h).imp Sub.snd id
  | inl _ ih => cases hs with | inl h => exact (ih h).imp Sub.inl id
  | inr _ ih => cases hs with | inr h => exact (ih h).imp Sub.inr id
  | pkg _ ih => cases hs with | pkg h => exact (ih h).imp Sub.pkg id

/-! ### What a step hands on -/

/-- Handing a value on: what is handed on was an owner's (a borrowed value
    handed on holds no cell share, `TakeVal.bor`), and no slot gains a share. -/
theorem _root_.A2.TakeVal.cell {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) {k : Nat} :
    (Sub (.cell k) v → CellAt m k) ∧ (CellAt m1 k → CellAt m k) := by
  cases h with
  | own hy => exact ⟨fun hs => .of_slot hy hs, CellAt.set_none⟩
  | bor _ hnc => exact ⟨fun hs => absurd hs (hnc k), id⟩

/-- Evaluating a right-hand side leaves the slots as they were but for what
    it takes. -/
theorem _root_.A2.EvalR.cellSt {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1)) {k : Nat}
    (hc : CellAt m1 k) : CellAt m k := by
  cases h with
  | moveOwn _ => exact CellAt.set_none hc
  | takel _ => exact CellAt.set_none hc
  | taker _ => exact CellAt.set_none hc
  | pop hy _ _ =>
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      exact .of_slot hy (sub_cell_node_sub hs fun e he => List.mem_append_left _ he)
    · exact hc
  | remove _ hy _ _ _ =>
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      exact .of_slot hy (sub_cell_node_sub hs fun e he => List.mem_of_mem_eraseIdx he)
    · exact hc
  | pair h1 h2 => exact h1.cell.2 (h2.cell.2 hc)
  | inl h1 => exact h1.cell.2 hc
  | inr h1 => exact h1.cell.2 hc
  | pack h1 => exact h1.cell.2 hc
  | arcNew h1 _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | lockNew h1 _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | cellNew h1 _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | chanSend _ h1 _ _ _ _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | chanSendClosed _ h1 _ _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | lockRestore _ h1 _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | _ => exact CellAt.of_st rfl hc

/-- Binding parameters hands each a value an argument held (an `in`
    parameter is a borrow, which holds no owner's share). -/
theorem _root_.A2.BindParams.cellSt {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : ∀ {k : Nat}, CellAt m' k → CellAt m k := by
  induction h with
  | nil => exact id
  | inp _ _ _ ih => exact fun hc => CellAt.set_bor (ih hc)
  | sink ha _ ih =>
    intro k hc
    rcases CellAt.set (ih hc) with ⟨w, hw, hs⟩ | hc
    · cases hw; exact .of_slot ha hs
    · exact CellAt.set_none hc
  | inout _ ih => exact ih

/-- A package's environment, lent: a borrow, no owner's share. -/
theorem CellAt.envMem {m : Mem} {env : Val} {k : Nat} (h : CellAt (envMem m env) k) : CellAt m k :=
  CellAt.set_bor (m := m) (CellAt.of_st rfl h)

/-! ### A3.5's second cut: where a cell's shares are, and what a step does to them

A cell share is in a slot, or in a lock block's payload while the payload is
in the block (`LockHolds`): a lock's, a cell's state, a channel's queue.  An
`arc` block's payload holds none (`RhsT.arcNew` asks the Sync question), nor
does a view's (`RhsT.rwRead` asks it too), so neither is a place the shares
are.  What is lent out of a slot or a block is a borrow, which is no place
either (A3.5's third cut: its owner is the place, `MInv.cell_owned`).

`OnePlace m k`: cell `k`'s shares in the store are in one place — the slots,
with no lock block holding one, or one lock block's payload, with no slot
holding one.  Every step keeps it (`Step.cellKeep`), because a step moves a
cell's shares only whole:
- a value going into a lock block (`locked_new`, a cell's constructor,
  `locked_restore`, the give-back, `chan_send`) passed the crossing check:
  no slot left behind holds a share of a cell it holds (`CellKeep.moveIn`);
- a value coming out of one (a check-out, a take, a receive) leaves none in
  the block: a check-out and a take empty it, and a receive's head shares
  no cell with the rest of the queue, `RecvCheck` (`CellKeep.moveOut`);
- everything else moves shares between slots, or drops them. -/

/-- The store holds a share of cell `k`: in a slot, or in a lock block's payload. -/
def Holds (m : Mem) (k : Nat) : Prop := CellAt m k ∨ ∃ k', LockHolds m.blk k' k

/-- Cell `k`'s shares in the store are in one place: the slots, or one lock
    block's payload. -/
def OnePlace (m : Mem) (k : Nat) : Prop :=
  (∀ k', ¬ LockHolds m.blk k' k) ∨
    (¬ CellAt m k ∧ ∀ k1 k2, LockHolds m.blk k1 k → LockHolds m.blk k2 k → k1 = k2)

/-- Every cell share the store holds names a key taken from `nid`. -/
def CellsBelow (m : Mem) : Prop := ∀ k, Holds m k → k < m.nid

/-- **What a step does to the cells' shares**: a share it leaves the store
    held before, or is a new cell's, at a key taken from `nid` in the step;
    and the shares of each cell stay in one place. -/
structure CellKeep (m m' : Mem) : Prop where
  nid   : m.nid ≤ m'.nid
  holds : ∀ k, Holds m' k → Holds m k ∨ (m.nid ≤ k ∧ k < m'.nid)
  one   : CellsBelow m → ∀ k, OnePlace m k → OnePlace m' k

theorem CellKeep.below {m m' : Mem} (h : CellKeep m m') (hb : CellsBelow m) : CellsBelow m' := by
  intro k hk
  rcases h.holds k hk with h1 | h1
  · exact Nat.lt_of_lt_of_le (hb k h1) h.nid
  · exact h1.2

theorem CellKeep.refl (m : Mem) : CellKeep m m := ⟨Nat.le_refl _, fun _ h => .inl h, fun _ _ h => h⟩

theorem CellKeep.trans {m1 m2 m3 : Mem} (h1 : CellKeep m1 m2) (h2 : CellKeep m2 m3) : CellKeep m1 m3 := by
  refine ⟨Nat.le_trans h1.nid h2.nid, fun k hk => ?_, fun hb k hk => h2.one (h1.below hb) k (h1.one hb k hk)⟩
  rcases h2.holds k hk with h | h
  · rcases h1.holds k h with h' | h'
    · exact .inl h'
    · exact .inr ⟨h'.1, Nat.lt_of_lt_of_le h'.2 h2.nid⟩
  · exact .inr ⟨Nat.le_trans h1.nid h.1, h.2⟩

/-- `CellKeep` reads the slots, the blocks and `nid` only. -/
theorem CellKeep.congr {m m1 m2 : Mem} (h : CellKeep m m1) (hst : m2.st = m1.st) (hb : m2.blk = m1.blk)
    (hn : m2.nid = m1.nid) : CellKeep m m2 := by
  have hc : ∀ k, CellAt m2 k → CellAt m1 k := fun k => CellAt.of_st hst
  refine ⟨hn ▸ h.nid, fun k hk => ?_, fun hbl k hk => ?_⟩
  · have hk1 : Holds m1 k := by
      rcases hk with hk | ⟨k', hk'⟩
      · exact .inl (hc k hk)
      · exact .inr ⟨k', hb ▸ hk'⟩
    exact (h.holds k hk1).imp_right fun h' => ⟨h'.1, hn ▸ h'.2⟩
  · have h1 := h.one hbl k hk
    unfold OnePlace at h1 ⊢
    rw [hb]
    rcases h1 with h1 | ⟨h1, h2⟩
    · exact .inl h1
    · exact .inr ⟨fun h3 => h1 (hc k h3), h2⟩

theorem LockHolds.of_blk {B B' : Nat → Option Blk} (hb : B' = B) {k' k : Nat} (h : LockHolds B' k' k) :
    LockHolds B k' k := hb ▸ h

/-- A block replaced: what it holds is the new block's payload's. -/
theorem LockHolds.upd {B : Nat → Option Blk} {k0 : Nat} {b : Option Blk} {k' k : Nat}
    (h : LockHolds (upd B k0 b) k' k) :
    (k' ≠ k0 ∧ LockHolds B k' k) ∨ (k' = k0 ∧ ∃ t p, b = some ⟨t, .lock, some p⟩ ∧ Sub (.cell k) p) := by
  obtain ⟨t, p, hk, hs⟩ := h
  by_cases he : k' = k0
  · subst he; simp only [A2.upd] at hk; exact .inr ⟨rfl, t, p, hk, hs⟩
  · rw [upd_ne _ _ he] at hk; exact .inl ⟨he, t, p, hk, hs⟩

/-- No more places than before: a cell's shares stay in one place. -/
theorem OnePlace.shrink {m m' : Mem} (hbl : CellsBelow m) {k : Nat}
    (hst : CellAt m' k → CellAt m k ∨ m.nid ≤ k)
    (hb : ∀ k', LockHolds m'.blk k' k → LockHolds m.blk k' k) (h : OnePlace m k) : OnePlace m' k := by
  by_cases hL : ∃ k', LockHolds m'.blk k' k
  · obtain ⟨k1, hk1⟩ := hL
    have hm1 := hb k1 hk1
    have hlt : k < m.nid := hbl k (.inr ⟨k1, hm1⟩)
    rcases h with h | ⟨hnc, huniq⟩
    · exact absurd hm1 (h k1)
    · refine .inr ⟨fun hc => ?_, fun a b ha hb' => huniq a b (hb a ha) (hb b hb')⟩
      rcases hst hc with h' | h'
      · exact hnc h'
      · exact absurd hlt (Nat.not_lt.mpr h')
  · exact .inl fun k' hk' => hL ⟨k', hk'⟩

/-- A step that only drops shares or moves them between slots (or makes a
    new cell's, at a fresh key, in a slot). -/
theorem CellKeep.shrink {m m' : Mem} (hn : m.nid ≤ m'.nid)
    (hst : ∀ k, CellAt m' k → CellAt m k ∨ (m.nid ≤ k ∧ k < m'.nid))
    (hb : ∀ k' k, LockHolds m'.blk k' k → LockHolds m.blk k' k) : CellKeep m m' := by
  refine ⟨hn, fun k hk => ?_, fun hbl k h => OnePlace.shrink hbl (fun hc => (hst k hc).imp_right And.left)
    (hb · k) h⟩
  rcases hk with hk | ⟨k', hk'⟩
  · exact (hst k hk).imp_left .inl
  · exact .inl (.inr ⟨k', hb k' k hk'⟩)

/-- ... the same, with the blocks unchanged. -/
theorem CellKeep.slots {m m' : Mem} (hn : m.nid ≤ m'.nid)
    (hst : ∀ k, CellAt m' k → CellAt m k ∨ (m.nid ≤ k ∧ k < m'.nid)) (hb : m'.blk = m.blk) :
    CellKeep m m' :=
  CellKeep.shrink hn hst fun _ _ h => LockHolds.of_blk hb h

/-- **A value goes into lock block `k0`**, from a slot, having passed the
    crossing check: no slot left holds a share of a cell it holds (but a new
    cell's, at a fresh key: a cell's constructor's own share). -/
theorem CellKeep.moveIn {m m' : Mem} (k0 : Nat) (v : Val) (hn : m.nid ≤ m'.nid)
    (hst : ∀ k, CellAt m' k → CellAt m k ∨ (m.nid ≤ k ∧ k < m'.nid))
    (hb : ∀ k' k, LockHolds m'.blk k' k → LockHolds m.blk k' k ∨ (k' = k0 ∧ Sub (.cell k) v))
    (hv : ∀ k, Sub (.cell k) v → CellAt m k) (hck : ∀ k, Sub (.cell k) v → CellAt m' k → m.nid ≤ k) :
    CellKeep m m' := by
  refine ⟨hn, fun k hk => ?_, fun hbl k h => ?_⟩
  · rcases hk with hk | ⟨k', hk'⟩
    · exact (hst k hk).imp_left .inl
    · rcases hb k' k hk' with h | ⟨_, h⟩
      · exact .inl (.inr ⟨k', h⟩)
      · exact .inl (.inl (hv k h))
  · by_cases hvk : Sub (.cell k) v
    · have hc := hv k hvk
      have hlt : k < m.nid := hbl k (.inl hc)
      rcases h with h | ⟨hnc, _⟩
      · refine .inr ⟨fun hc' => absurd hlt (Nat.not_lt.mpr (hck k hvk hc')), fun a b ha hb' => ?_⟩
        rcases hb a k ha with ha' | ⟨rfl, _⟩
        · exact absurd ha' (h a)
        rcases hb b k hb' with hb'' | ⟨rfl, _⟩
        · exact absurd hb'' (h b)
        rfl
      · exact absurd hc hnc
    · exact OnePlace.shrink hbl (fun hc => (hst k hc).imp_right And.left)
        (fun k' hk' => (hb k' k hk').resolve_right fun ⟨_, h'⟩ => hvk h') h

/-- **A value comes out of lock block `k0`** into a slot, leaving none of
    the shares of the cells it holds in the block. -/
theorem CellKeep.moveOut {m m' : Mem} (k0 : Nat) (v : Val) (hn : m.nid ≤ m'.nid)
    (hst : ∀ k, CellAt m' k → CellAt m k ∨ Sub (.cell k) v ∨ (m.nid ≤ k ∧ k < m'.nid))
    (hb : ∀ k' k, LockHolds m'.blk k' k → LockHolds m.blk k' k ∧ (k' = k0 → ¬ Sub (.cell k) v))
    (hv : ∀ k, Sub (.cell k) v → LockHolds m.blk k0 k) : CellKeep m m' := by
  refine ⟨hn, fun k hk => ?_, fun hbl k h => ?_⟩
  · rcases hk with hk | ⟨k', hk'⟩
    · rcases hst k hk with h | h | h
      · exact .inl (.inl h)
      · exact .inl (.inr ⟨k0, hv k h⟩)
      · exact .inr h
    · exact .inl (.inr ⟨k', (hb k' k hk').1⟩)
  · by_cases hvk : Sub (.cell k) v
    · have h0 := hv k hvk
      rcases h with h | ⟨_, huniq⟩
      · exact absurd h0 (h k0)
      · refine .inl fun k' hk' => ?_
        obtain ⟨hm', hne⟩ := hb k' k hk'
        exact hne (huniq k' k0 hm' h0) hvk
    · refine OnePlace.shrink hbl (fun hc => ?_) (fun k' hk' => (hb k' k hk').1) h
      rcases hst k hc with h' | h' | h'
      · exact .inl h'
      · exact absurd h' hvk
      · exact .inr h'.1

/-- A value set in a slot, the blocks and the other slots as `EvalR` left
    them: the slots' shares were the start's slots', and so were the value's
    if it is an owner's (a borrow is no owner, A3.5's third cut). -/
theorem CellKeep.setVal {m m1 : Mem} {v : Val} (x : Var) (o : Bool) (hn : m.nid ≤ m1.nid)
    (hst : ∀ k, CellAt m1 k → CellAt m k) (hv : o = true → ∀ k, Sub (.cell k) v → CellAt m k)
    (hb : ∀ k' k, LockHolds m1.blk k' k → LockHolds m.blk k' k) : CellKeep m (m1.set x ⟨o, some v⟩) := by
  refine CellKeep.shrink hn (fun k hc => ?_) (fun k' k h => hb k' k h)
  rcases CellAt.set_own hc with ⟨w, hw, hs⟩ | hc
  · cases hw; exact .inl (hv rfl k hs)
  · exact .inl (hst k hc)

theorem TakeVal.nid_eq {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) : m1.nid = m.nid := by
  cases h <;> rfl

/-- A value no cell share is in. -/
theorem noCell_int {n k : Nat} : ¬ Sub (.cell k) (.int n) := fun h => by cases h

/-- **What a right-hand side does**, its value set in a slot, an owner or a
    borrow as the right-hand side says. -/
theorem _root_.A2.EvalR.cellKeep {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    (x : Var) : CellKeep m (m1.set x ⟨o, some v⟩) := by
  have hst : ∀ k, CellAt m1 k → CellAt m k := fun k hc => h.cellSt hc
  have hn : m.nid ≤ m1.nid := (EvalR.grows h).nid
  cases h with
  | expr _ => exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun _ _ h => h)
  | new => exact CellKeep.setVal x _ hn hst (fun _ _ hs => absurd (sub_cell_node hs) (by simp)) (fun _ _ h => h)
  | moveOwn hy => exact CellKeep.setVal x _ hn hst (fun _ _ hs => .of_slot hy hs) (fun _ _ h => h)
  | copy _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | borrowOwn _ => exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun _ _ h => h)
  | borrowBor _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | «at» _ _ _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | view _ => exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun _ _ h => h)
  | sat _ _ _ _ _ _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | pop hy _ _ =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => .of_slot hy (Sub.child (by simp) hs)) (fun _ _ h => h)
  | remove hn' hy _ _ _ =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => .of_slot hy (Sub.child (List.getElem_mem hn') hs))
      (fun _ _ h => h)
  | pair h1 h2 =>
    refine CellKeep.setVal x _ hn hst (fun _ _ hs => ?_)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk h1) (LockHolds.of_blk (TakeVal.blk h2) h))
    cases hs with
    | fst hs => exact h1.cell.1 hs
    | snd hs => exact h1.cell.2 (h2.cell.1 hs)
  | fst _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | snd _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | inl h1 =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs with | inl hs => exact h1.cell.1 hs)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk h1) h)
  | inr h1 =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs with | inr hs => exact h1.cell.1 hs)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk h1) h)
  | getl _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | getr _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | takel hy => exact CellKeep.setVal x _ hn hst (fun _ _ hs => .of_slot hy (Sub.inl hs)) (fun _ _ h => h)
  | taker hy => exact CellKeep.setVal x _ hn hst (fun _ _ hs => .of_slot hy (Sub.inr hs)) (fun _ _ h => h)
  | pack h1 =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs with | pkg hs => exact h1.cell.1 hs)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk h1) h)
  | @arcNew t y w m2 h1 _ =>
    -- a new `arc` block: no place of a cell's shares
    refine CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun k' k hk => ?_)
    rcases LockHolds.upd hk with ⟨_, hk⟩ | ⟨_, _, _, hb, _⟩
    · exact LockHolds.of_blk (TakeVal.blk h1) hk
    · cases hb
  | arcClone _ => exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun _ _ h => h)
  | arcGet _ _ => exact CellKeep.setVal x _ hn hst (fun h => nomatch h) (fun _ _ h => h)
  | @lockNew t y w m2 h1 _ hck =>
    -- the payload goes into a new lock block, past the crossing check
    refine CellKeep.moveIn m2.nid w hn (fun k hc => ?_) (fun k' k hk => ?_) (fun k hs => h1.cell.1 hs)
      (fun k hs hc => ?_)
    · rcases CellAt.set hc with ⟨u, hu, hs⟩ | hc
      · cases hu; cases hs
      · exact .inl (hst k hc)
    · rcases LockHolds.upd hk with ⟨_, hk⟩ | ⟨rfl, _, _, hb, hs⟩
      · exact .inl (LockHolds.of_blk (TakeVal.blk h1) hk)
      · cases hb; exact .inr ⟨rfl, hs⟩
    · rcases CellAt.set hc with ⟨u, hu, hs'⟩ | ⟨y', u, hy', hs'⟩
      · cases hu; cases hs'
      · exact absurd hs' (hck.1 k ⟨w, List.mem_singleton_self _, hs⟩ y' u hy')
  | lockClone _ => exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun _ _ h => h)
  | @cellNew t y w m2 h1 _ hck =>
    -- the state goes into a new lock block, past the crossing check; the new
    -- cell's one share is the value
    have hn2 : m2.nid = m.nid := TakeVal.nid_eq h1
    refine CellKeep.moveIn m2.nid w hn (fun k hc => ?_) (fun k' k hk => ?_) (fun k hs => h1.cell.1 hs)
      (fun k hs hc => ?_)
    · rcases CellAt.set hc with ⟨u, hu, hs⟩ | hc
      · cases hu; cases hs
        exact .inr ⟨Nat.le_of_eq hn2.symm, Nat.lt_succ_self _⟩
      · exact .inl (hst k hc)
    · rcases LockHolds.upd hk with ⟨_, hk⟩ | ⟨rfl, _, _, hb, hs⟩
      · exact .inl (LockHolds.of_blk (TakeVal.blk h1) hk)
      · cases hb; exact .inr ⟨rfl, hs⟩
    · rcases CellAt.set hc with ⟨u, hu, hs'⟩ | ⟨y', u, hy', hs'⟩
      · cases hu; cases hs'; exact Nat.le_of_eq hn2.symm
      · exact absurd hs' (hck.1 k ⟨w, List.mem_singleton_self _, hs⟩ y' u hy')
  | cellClone _ ho =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs; exact .of_owned ho) (fun _ _ h => h)
  | atomic _ hk _ _ _ =>
    refine CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun k' k hk' => ?_)
    rcases LockHolds.upd hk' with ⟨_, hk'⟩ | ⟨_, _, _, hb, hs⟩
    · exact hk'
    · cases hb; cases hs
  | @chanSend a y o0 k0 t u c d es w m2 _ h1 hk _ _ _ hck =>
    -- the value goes to the back of the queue, past the crossing check
    refine CellKeep.moveIn k0 w hn (fun k hc => ?_) (fun k' k hk' => ?_) (fun k hs => h1.cell.1 hs)
      (fun k hs hc => ?_)
    · rcases CellAt.set hc with ⟨u', hu, hs⟩ | hc
      · cases hu; cases hs
      · exact .inl (hst k hc)
    · rcases LockHolds.upd hk' with ⟨_, hk'⟩ | ⟨rfl, _, _, hb, hs⟩
      · exact .inl (LockHolds.of_blk (TakeVal.blk h1) hk')
      · cases hb
        cases hs with
        | fst hs =>
          obtain ⟨e, he, hse⟩ := sub_cell_node hs
          rcases List.mem_append.mp he with he | he
          · exact .inl ⟨t, _, by rw [← TakeVal.blk h1]; exact hk, Sub.fst (Sub.child he hse)⟩
          · rw [List.mem_singleton] at he; subst he; exact .inr ⟨rfl, hse⟩
        | snd hs => cases hs
    · rcases CellAt.set hc with ⟨u', hu, hs'⟩ | ⟨y', u', hy', hs'⟩
      · cases hu; cases hs'
      · exact absurd hs' (hck.1 k ⟨w, List.mem_singleton_self _, hs⟩ y' u' hy')
  | @chanSendClosed _ _ _ _ _ _ _ _ w m2 _ h1 _ _ _ hck =>
    -- Agora #755: the value a closed channel does not queue goes into a new
    -- lock block, past the crossing check (as `locked_new`'s)
    refine CellKeep.moveIn m2.nid w hn (fun k hc => ?_) (fun k' k hk => ?_) (fun k hs => h1.cell.1 hs)
      (fun k hs hc => ?_)
    · rcases CellAt.set hc with ⟨u, hu, hs⟩ | hc
      · cases hu; cases hs
      · exact .inl (hst k hc)
    · rcases LockHolds.upd hk with ⟨_, hk⟩ | ⟨rfl, _, _, hb, hs⟩
      · exact .inl (LockHolds.of_blk (TakeVal.blk h1) hk)
      · cases hb; exact .inr ⟨rfl, hs⟩
    · rcases CellAt.set hc with ⟨u, hu, hs'⟩ | ⟨y', u, hy', hs'⟩
      · cases hu; cases hs'
      · exact absurd hs' (hck.1 k ⟨w, List.mem_singleton_self _, hs⟩ y' u hy')
  | @chanRecv w a o0 k0 t u c d f hd es _ hk _ _ _ hck =>
    -- the head comes out of the queue, sharing no cell with the rest
    refine CellKeep.moveOut k0 hd hn (fun k hc => ?_) (fun k' k hk' => ?_)
      (fun k hs => ⟨t, _, hk, Sub.fst (Sub.child (List.mem_cons_self ..) hs)⟩)
    · rcases CellAt.set hc with ⟨u', hu, hs⟩ | hc
      · cases hu; cases hs with | inr hs => exact .inr (.inl hs)
      · exact .inl hc
    · rcases LockHolds.upd hk' with ⟨hne, hk'⟩ | ⟨rfl, _, _, hb, hs⟩
      · exact ⟨hk', fun e => absurd e hne⟩
      · cases hb
        cases hs with
        | fst hs =>
          obtain ⟨e, he, hse⟩ := sub_cell_node hs
          exact ⟨⟨t, _, hk, Sub.fst (Sub.child (List.mem_cons_of_mem _ he) hse)⟩,
            fun _ hh => hck k hh e he hse⟩
        | snd hs => cases hs
  | chanRecvNone _ _ _ _ =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs with | inl hs => cases hs) (fun _ _ h => h)
  | chanClose _ hk _ =>
    refine CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun k' k hk' => ?_)
    rcases LockHolds.upd hk' with ⟨_, hk'⟩ | ⟨rfl, _, _, hb, hs⟩
    · exact hk'
    · cases hb
      cases hs with
      | fst hs => exact ⟨_, _, hk, Sub.fst hs⟩
      | snd hs => cases hs
  | rwRead _ _ _ =>
    -- a new view: no place of a cell's shares
    refine CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs) (fun k' k hk' => ?_)
    rcases LockHolds.upd hk' with ⟨_, hk'⟩ | ⟨_, _, _, hb, _⟩
    · exact hk'
    · cases hb
  | rwTryRead _ _ _ =>
    -- A3.3: `rw_read`'s new view, the guard as `some`
    refine CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs with | inr hs => cases hs)
      (fun k' k hk' => ?_)
    rcases LockHolds.upd hk' with ⟨_, hk'⟩ | ⟨_, _, _, hb, _⟩
    · exact hk'
    · cases hb
  | rwTryReadNone _ _ | rwTryWriteNone _ _ =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs with | inl hs => cases hs) (fun _ _ h => h)
  | rwTryWrite _ _ _ =>
    exact CellKeep.setVal x _ hn hst (fun _ _ hs => by cases hs with | inr hs => cases hs) (fun _ _ h => h)
  | glob _ hf =>
    refine CellKeep.setVal x _ hn hst (fun _ _ hs => ?_) (fun _ _ h => h)
    rcases hf with ⟨_, _, _, _, rfl, _⟩ | ⟨_, _, _, _, rfl, _⟩ <;> cases hs
  | @lockTake a o0 k0 t _ _ hk _ =>
    -- the payload comes out, the block left empty
    refine CellKeep.moveOut k0 v hn (fun k hc => ?_) (fun k' k hk' => ?_) (fun k hs => ⟨t, v, hk, hs⟩)
    · rcases CellAt.set hc with ⟨u', hu, hs⟩ | hc
      · cases hu; exact .inr (.inl hs)
      · exact .inl hc
    · rcases LockHolds.upd hk' with ⟨hne, hk'⟩ | ⟨rfl, _, _, hb, _⟩
      · exact ⟨hk', fun e => absurd e hne⟩
      · cases hb
  | @lockRestore a y o0 k0 t w m2 _ h1 hk hck =>
    -- the value goes back into the block, past the crossing check
    refine CellKeep.moveIn k0 w hn (fun k hc => ?_) (fun k' k hk' => ?_) (fun k hs => h1.cell.1 hs)
      (fun k hs hc => ?_)
    · rcases CellAt.set hc with ⟨u', hu, hs⟩ | hc
      · cases hu; cases hs
      · exact .inl (hst k hc)
    · rcases LockHolds.upd hk' with ⟨_, hk'⟩ | ⟨rfl, _, _, hb, hs⟩
      · exact .inl (LockHolds.of_blk (TakeVal.blk h1) hk')
      · cases hb; exact .inr ⟨rfl, hs⟩
    · rcases CellAt.set hc with ⟨u', hu, hs'⟩ | ⟨y', u', hy', hs'⟩
      · cases hu; cases hs'
      · exact absurd hs' (hck.1 k ⟨w, List.mem_singleton_self _, hs⟩ y' u' hy')

/-- **A lock scope's end**: what goes back passed the crossing check
    (`Release.put`), or `x`'s slot is dropped. -/
theorem _root_.A2.Release.cellKeep {m m' : Mem} {k0 : Nat} {t : Ty} {x : Var} (h : Release m k0 t x m') :
    CellKeep m m' := by
  cases h with
  | @put o v hx hg hk hck =>
    -- what goes back is an owner's tree, or an integer (`Giveable`)
    have hv : ∀ k, Sub (.cell k) v → CellAt m k := fun k hs => by
      cases o with
      | true => exact .of_slot hx hs
      | false => cases v <;> simp [Giveable] at hg; cases hs
    refine CellKeep.moveIn k0 v (Nat.le_refl _) (fun k hc => .inl (CellAt.remove (CellAt.of_st rfl hc)))
      (fun k' k hk' => ?_) hv (fun k hs hc => ?_)
    · rcases LockHolds.upd hk' with ⟨_, hk'⟩ | ⟨rfl, _, _, hb, hs⟩
      · exact .inl hk'
      · cases hb; exact .inr ⟨rfl, hs⟩
    · obtain ⟨y', u', hy', hs'⟩ := hc
      exact absurd hs' ((hck v rfl).1 k ⟨v, List.mem_singleton_self _, hs⟩ y' u' hy')
  | drop _ _ _ =>
    exact CellKeep.slots (Nat.le_refl _) (fun k hc => .inl (CellAt.remove (CellAt.of_st rfl hc))) rfl

/-- **A step keeps each cell's shares in one place**, and makes a share only
    of a new cell. -/
theorem _root_.A2.Step.cellKeep {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) :
    CellKeep m r.mem := by
  induction h with
  | seqSkip => exact CellKeep.refl _
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he => exact he.cellKeep _
  | letvP _ => exact CellKeep.refl _
  | letcall _ _ hbp =>
    exact CellKeep.shrink (BindParams.grows hbp).nid
      (fun _ hc => .inl (hbp.cellSt (CellAt.set_none (CellAt.set_none (CellAt.of_st rfl hc)))))
      (fun _ _ h => LockHolds.of_blk (BindParams.blk hbp) h)
  | scopeSkip _ _ => exact CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.remove (CellAt.of_st rfl hc))) rfl
  | scopeIn _ ih => exact ih
  | scopeP _ _ _ ih =>
    exact ih.trans (CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.remove (CellAt.of_st rfl hc))) rfl)
  | rbindSkip _ => exact CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.remove hc)) rfl
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact ih.trans (CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.remove hc)) rfl)
  | frozenSkip => exact CellKeep.refl _
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ _ => exact (he.cellKeep _).congr rfl rfl rfl
  | assignP _ => exact CellKeep.refl _
  | iteT _ _ => exact CellKeep.refl _
  | iteF _ => exact CellKeep.refl _
  | «while» => exact CellKeep.refl _
  | push ht hx _ _ =>
    refine CellKeep.shrink (Nat.le_of_eq (TakeVal.nid_eq ht).symm) (fun k hc => .inl ?_)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk ht) h)
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      obtain ⟨e, he, hse⟩ := sub_cell_node hs
      rcases List.mem_append.mp he with he | he
      · exact ht.cell.2 (.of_slot hx (Sub.child he hse))
      · rw [List.mem_singleton] at he; subst he; exact ht.cell.1 hse
    · exact ht.cell.2 hc
  | withElem hn hv _ _ _ _ =>
    refine CellKeep.slots (Nat.le_refl _) (fun k hc => .inl ?_) rfl
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; exact .of_slot hv (Sub.child (List.getElem_mem hn) hs)
    · rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
      · cases hw
        obtain ⟨e, he, hse⟩ := sub_cell_node hs
        rcases List.mem_append.mp he with he | he
        · exact .of_slot hv (Sub.child (List.mem_of_mem_take he) hse)
        · exact .of_slot hv (Sub.child (List.mem_of_mem_drop he) hse)
      · exact hc
  | withElemOOB _ _ _ _ => exact CellKeep.refl _
  | insert _ ht hx _ _ =>
    refine CellKeep.shrink (Nat.le_of_eq (TakeVal.nid_eq ht).symm) (fun k hc => .inl ?_)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk ht) h)
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      obtain ⟨e, he, hse⟩ := sub_cell_node hs
      rcases List.mem_append.mp ((perm_insert _ _ _).symm.subset he) with he | he
      · exact ht.cell.2 (.of_slot hx (Sub.child he hse))
      · rw [List.mem_singleton] at he; subst he; exact ht.cell.1 hse
    · exact ht.cell.2 hc
  | pushRealloc ht hx _ _ =>
    refine CellKeep.shrink (by show _ ≤ _ + 1; rw [TakeVal.nid_eq ht]; omega) (fun k hc => .inl ?_)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk ht) h)
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      obtain ⟨e, he, hse⟩ := sub_cell_node hs
      rcases List.mem_append.mp he with he | he
      · exact ht.cell.2 (.of_slot hx (Sub.child he hse))
      · rw [List.mem_singleton] at he; subst he; exact ht.cell.1 hse
    · exact ht.cell.2 (CellAt.of_st rfl hc)
  | editPush ht hn hr =>
    refine CellKeep.shrink (Nat.le_of_eq (TakeVal.nid_eq ht).symm) (fun k hc => .inl ?_)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk ht) h)
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact ht.cell.2 (.of_slot hn.2.2.1 h)
      · obtain ⟨e, he, hse⟩ := sub_cell_node h
        rcases List.mem_append.mp he with he | he
        · exact ht.cell.2 (.of_slot hn.2.2.1 ((Sub.child he hse).trans hr.sub))
        · rw [List.mem_singleton] at he; subst he; exact ht.cell.1 hse
    · exact ht.cell.2 hc
  | editPushRealloc ht hn hr =>
    refine CellKeep.shrink (by show _ ≤ _ + 1; rw [TakeVal.nid_eq ht]; omega) (fun k hc => .inl ?_)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk ht) h)
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact ht.cell.2 (.of_slot hn.2.2.1 h)
      · obtain ⟨e, he, hse⟩ := sub_cell_node h
        rcases List.mem_append.mp he with he | he
        · exact ht.cell.2 (.of_slot hn.2.2.1 ((Sub.child he hse).trans hr.sub))
        · rw [List.mem_singleton] at he; subst he; exact ht.cell.1 hse
    · exact ht.cell.2 (CellAt.of_st rfl hc)
  | editTrunc _ hn _ hr =>
    refine CellKeep.slots (Nat.le_refl _) (fun k hc => .inl ?_) rfl
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact .of_slot hn.2.2.1 h
      · exact .of_slot hn.2.2.1 ((sub_cell_node_sub h fun e he => List.mem_of_mem_take he).trans hr.sub)
    · exact CellAt.of_st rfl hc
  | editSet _ _ ht hn _ hr =>
    refine CellKeep.shrink (Nat.le_of_eq (TakeVal.nid_eq ht).symm) (fun k hc => .inl ?_)
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk ht) h)
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact ht.cell.2 (.of_slot hn.2.2.1 h)
      · obtain ⟨e, he, hse⟩ := sub_cell_node h
        rcases List.mem_or_eq_of_mem_set he with he | rfl
        · exact ht.cell.2 (.of_slot hn.2.2.1 ((Sub.child he hse).trans hr.sub))
        · exact ht.cell.1 hse
    · exact ht.cell.2 (CellAt.of_st rfl hc)
  | editSetOOB _ ht _ _ _ =>
    exact CellKeep.shrink (Nat.le_of_eq (TakeVal.nid_eq ht).symm) (fun _ hc => .inl (ht.cell.2 (CellAt.of_st rfl hc)))
      (fun _ _ h => LockHolds.of_blk (TakeVal.blk ht) h)
  | free _ _ =>
    exact CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.of_st rfl (CellAt.set_none hc))) rfl
  | panic => exact CellKeep.refl _
  | waitPanic _ => exact CellKeep.refl _
  | letrec _ _ _ =>
    exact CellKeep.slots (Nat.le_refl _)
      (fun _ hc => .inl (CellAt.set_none (CellAt.set_none (CellAt.of_st rfl hc)))) rfl
  | catchIn _ ih => exact ih
  | catchSkip => exact CellKeep.refl _
  | unpair hy _ _ _ =>
    refine CellKeep.slots (Nat.le_refl _) (fun k hc => .inl ?_) rfl
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; exact .of_slot hy (Sub.snd hs)
    · rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
      · cases hw; exact .of_slot hy (Sub.fst hs)
      · exact CellAt.set_none hc
  | callc _ _ _ _ hbp =>
    exact CellKeep.shrink (BindParams.grows hbp).nid
      (fun _ hc => .inl (CellAt.envMem (hbp.cellSt (CellAt.set_none (CellAt.set_none (CellAt.of_st rfl hc))))))
      (fun _ _ h => LockHolds.of_blk (BindParams.blk hbp) h)
  | callcE hc _ _ _ =>
    -- A2-envhand: the environment's shares move to its binding
    refine CellKeep.slots (Nat.le_refl _) (fun k hc' => .inl ?_) rfl
    rcases CellAt.set (CellAt.set_none (CellAt.of_st rfl hc')) with ⟨w, hw, hs⟩ | hc'
    · cases hw; exact .of_slot hc (Sub.pkg hs)
    · exact CellAt.set_none hc'
  | callcD hc _ _ _ _ =>
    refine CellKeep.slots (Nat.le_refl _) (fun k hc' => .inl ?_) rfl
    rcases CellAt.set (CellAt.set_none (CellAt.of_st rfl hc')) with ⟨w, hw, hs⟩ | hc'
    · cases hw; exact .of_slot hc (Sub.pkg hs)
    · exact CellAt.set_none hc'
  | catchP _ _ ih =>
    refine ih.trans (CellKeep.slots (Nat.le_refl _) (fun k hc => .inl ?_) rfl)
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; cases hs
    · exact hc
  | letd _ he => exact he.cellKeep _
  | letdP _ => exact CellKeep.refl _
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ _ | scopeDDrain _ =>
    exact CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.of_st rfl hc)) rfl
  | scopeDEmpty _ => exact CellKeep.refl _
  | scopeDMoved _ => exact CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.remove hc)) rfl
  | scopeDPDrain _ _ ih => exact ih
  | scopeDP _ _ _ ih =>
    exact ih.trans (CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.of_st rfl hc)) rfl)
  | scopeDPMoved _ _ ih => exact ih.trans (CellKeep.slots (Nat.le_refl _) (fun _ hc => .inl (CellAt.remove hc)) rfl)
  | @reap r0 k0 n f u p _ hk hnc =>
    -- Agora #610: an orphan's payload, which holds no cell share, moves to a slot
    refine CellKeep.shrink (Nat.le_refl _) (fun k hc => ?_) (fun k' k hk' => ?_)
    · rcases CellAt.set (m := m) (x := m.nv) (sl := ⟨true, some p⟩) hc with ⟨w, hw, hs⟩ | hc
      · cases hw; exact absurd hs (hnc k)
      · exact .inl hc
    · rcases LockHolds.upd hk' with ⟨hne, hk'⟩ | ⟨rfl, _, _, hb, _⟩
      · exact hk'
      · cases hb
  | @withLock a x s0 k0 t v _ hk _ _ =>
    -- the payload is checked out, the block left empty
    refine CellKeep.moveOut k0 v (Nat.le_refl _) (fun k hc => ?_) (fun k' k hk' => ?_)
      (fun k hs => ⟨t, v, hk, hs⟩)
    · rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
      · cases hw; exact .inr (.inl hs)
      · exact .inl (CellAt.of_st rfl hc)
    · rcases LockHolds.upd hk' with ⟨hne, hk'⟩ | ⟨rfl, _, _, hb, _⟩
      · exact ⟨hk', fun e => absurd e hne⟩
      · cases hb
  | scopeLIn _ ih => exact ih
  | scopeLSkip hrl _ => exact hrl.cellKeep
  | scopeLFail _ _ => exact CellKeep.refl _
  | scopeLP _ hrl ih => exact ih.trans hrl.cellKeep

/-! ### Lists of threads, and the arguments a spawn moves -/

theorem MoveArgs.slot {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (h : MoveArgs st as vs st') : ∀ y sl, st' y = some sl → st y = some sl ∨ sl = ⟨true, none⟩ := by
  induction h with
  | nil => exact fun _ _ h => .inl h
  | cons _ _ ih =>
    intro y sl hy
    rcases ih y sl hy with h | h
    · simp only [upd] at h
      split at h
      · cases h; exact .inr rfl
      · exact .inl h
    · exact .inr h

/-- A3.1: a value a spawner's slot held is still there after the arguments
    move out, or it is one of the moved ones. -/
theorem MoveArgs.keep {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (h : MoveArgs st as vs st') :
    ∀ y o v, st y = some ⟨o, some v⟩ → st' y = some ⟨o, some v⟩ ∨ v ∈ vs := by
  induction h with
  | nil => exact fun _ _ _ h => .inl h
  | @cons st st' a as v vs ha _ ih =>
    intro y o w hy
    by_cases hya : y = a
    · subst hya; rw [ha] at hy; cases hy; exact .inr (List.mem_cons_self ..)
    · have hy' : upd st a (some ⟨true, none⟩) y = some ⟨o, some w⟩ := by
        show (if y = a then _ else st y) = _
        rw [ite_eq_right hya]; exact hy
      rcases ih y o w hy' with h | h
      · exact .inl h
      · exact .inr (List.mem_cons_of_mem _ h)

theorem list_append_get {α : Type} {l : List α} {y : α} {j : Nat} :
    (l ++ [y])[j]? = if j < l.length then l[j]? else if j = l.length then some y else none := by
  by_cases h : j < l.length
  · rw [ite_eq_left h, List.getElem?_append_left h]
  · rw [ite_eq_right h, List.getElem?_append_right (by omega)]
    by_cases he : j = l.length
    · subst he; simp
    · rw [ite_eq_right he]; simp; omega

/-- A list with one element replaced and one appended, by index. -/
theorem get_set_append {α : Type} {l : List α} {i : Nat} {x y : α} (hi : i < l.length) (j : Nat) :
    (l.set i x ++ [y])[j]? =
      if j < l.length then (if i = j then some x else l[j]?) else if j = l.length then some y else none := by
  rw [list_append_get]
  simp only [List.length_set]
  by_cases hj : j < l.length
  · rw [ite_eq_left hj, ite_eq_left hj, list_set_get hi]
  · rw [ite_eq_right hj, ite_eq_right hj]


/-! ### Confinement -/

/-- A thread's owned slot holds a share of cell `k` (A3.5's third cut: a live
    borrow's owner is one, `cellAt_of_live`). -/
def Thread.cellAt (t : Thread) (k : Nat) : Prop := ∃ y v, t.st y = some ⟨true, some v⟩ ∧ Sub (.cell k) v

/-- **A3.5's invariant: a cell's owners are in one place** (A3.5's second
    cut: one thread's owned slots, or one lock block's payload — a lock's, a
    cell's state, a channel's queue — never split; A3.5's third cut: owned
    slots, a borrow being counted through its owner, `CellInv.live_home`).
    - `home`: no two threads' owned slots hold a share of one cell;
    - `apart`: no thread's owned slot holds a share of a cell a lock block's
      payload holds one of (until a check-out, a take or a receive moves it out);
    - `one`: no two lock blocks' payloads hold a share of one cell;
    - and every cell share names a key taken from `nid` (so a new cell's key is
      no one's). -/
structure CellInv (C : Cfg) : Prop where
  below    : ∀ (j : Nat) (t : Thread) (k : Nat), C.ths[j]? = some t → t.cellAt k → k < C.nid
  blkBelow : ∀ k' k, LockHolds C.blk k' k → k < C.nid
  home     : ∀ (i j : Nat) (ti tj : Thread) (k : Nat), C.ths[i]? = some ti → C.ths[j]? = some tj →
    ti.cellAt k → tj.cellAt k → i = j
  apart    : ∀ (j : Nat) (t : Thread) (k k' : Nat), C.ths[j]? = some t → t.cellAt k → ¬ LockHolds C.blk k' k
  one      : ∀ k k1 k2, LockHolds C.blk k1 k → LockHolds C.blk k2 k → k1 = k2

/-- What a thread's view holds of a cell: its slots' shares and the blocks'. -/
theorem CellInv.view_below {C : Cfg} (h : CellInv C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t) :
    CellsBelow (C.view t) := fun k hk =>
  hk.elim (fun hc => h.below i t k hi hc) (fun ⟨k', h'⟩ => h.blkBelow k' k h')

/-- ... in one place. -/
theorem CellInv.onePlace {C : Cfg} (h : CellInv C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t)
    (k : Nat) : OnePlace (C.view t) k := by
  by_cases hc : t.cellAt k
  · exact .inl fun k' => h.apart i t k k' hi hc
  · exact .inr ⟨hc, h.one k⟩

/-- The start: one thread, holding nothing (A3.6: a global is no thread's
    binding), and the globals' blocks each cell's shares are in one of
    (`GlobsOK.cells`: the `make`s ran the crossing check). -/
theorem CellInv.start {P : Prog} {G : Globs} (hG : GlobsOK P G) (s : Stmt) (nv : Nat) :
    CellInv (Cfg.start G s nv) := by
  have hnone : ∀ (j : Nat) (t : Thread) (k : Nat), (Cfg.start G s nv).ths[j]? = some t → ¬ t.cellAt k := by
    rintro j t k hj ⟨y, v, hy, _⟩
    cases j with
    | zero => simp [Cfg.start] at hj; subst hj; cases hy
    | succ j => simp [Cfg.start] at hj
  exact ⟨fun j t k hj hk => absurd hk (hnone j t k hj), fun k' k hk => (hG.cells k k' k' hk hk).2,
    fun i _ ti _ k hi _ hk _ => absurd hk (hnone i ti k hi), fun j t k _ hj hk => absurd hk (hnone j t k hj),
    fun k k1 k2 hk1 hk2 => (hG.cells k k1 k2 hk1 hk2).1⟩

/-- **A thread's step, and the marking sweep that ends it, keep the cells' homes**:
    a share the stepping thread or a lock block holds afterwards was in the
    thread's view before (its slots or a lock block), or is a new cell's, at a
    key no thread's share names; and its cell's shares stay in one place
    (`Step.cellKeep`). -/
theorem CellInv.thread_of {P : Prog} {C : Cfg} (h : CellInv C) {i : Nat} {t : Thread}
    {m' : Mem} {s' : Stmt} (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) :
    CellInv (C.put i m' s').sweepD := by
  have hk : CellKeep (C.view t) m' := Step.cellKeep hst
  have hbl := h.view_below hi
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hnid : C.nid ≤ m'.nid := hk.nid
  -- a share the stepping thread holds afterwards was in its view, or is new
  have hnew : ∀ k, Holds m' k → (t.cellAt k ∨ ∃ k', LockHolds C.blk k' k) ∨ (C.nid ≤ k ∧ k < m'.nid) :=
    fun k hh => hk.holds k hh
  have hths : ∀ j tj, ((C.put i m' s').sweepD).ths[j]? = some tj →
      (j = i ∧ tj = ⟨m'.st, m'.nv, s'⟩) ∨ (j ≠ i ∧ C.ths[j]? = some tj) := by
    intro j tj hj
    simp only [Cfg.sweepD, Cfg.put] at hj
    rw [list_set_get hilen] at hj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; exact .inl ⟨hij.symm, rfl⟩
    · rw [ite_eq_right hij] at hj; exact .inr ⟨Ne.symm hij, hj⟩
  have hblk : ∀ k' k, LockHolds ((C.put i m' s').sweepD).blk k' k → LockHolds m'.blk k' k :=
    fun k' k h' => LockHolds.of_sweepD h'
  have hm'cell : ∀ k, (⟨m'.st, m'.nv, s'⟩ : Thread).cellAt k → CellAt m' k := fun k h' => h'
  -- a cell another thread holds is in no lock block and not the stepping thread's, before and after
  have hother : ∀ j tj k, j ≠ i → C.ths[j]? = some tj → tj.cellAt k → ¬ Holds m' k := by
    intro j tj k hji hj hc hh
    rcases hnew k hh with (h1 | ⟨k', h1⟩) | h1
    · exact hji (h.home j i tj t k hj hi hc h1)
    · exact h.apart j tj k k' hj hc h1
    · exact absurd (h.below j tj k hj hc) (Nat.not_lt.mpr h1.1)
  refine ⟨fun j tj k hj hc => ?_, fun k' k hk' => ?_, fun j1 j2 t1 t2 k hj1 hj2 hk1 hk2 => ?_,
    fun j tj k k' hj hc hk' => ?_, fun k k1 k2 h1 h2 => ?_⟩
  · show k < m'.nid
    rcases hths j tj hj with ⟨_, e⟩ | ⟨_, hj⟩
    · subst e; exact (hk.below hbl) k (.inl (hm'cell k hc))
    · exact Nat.lt_of_lt_of_le (h.below j tj k hj hc) hnid
  · exact (hk.below hbl) k (.inr ⟨k', hblk k' k hk'⟩)
  · rcases hths j1 t1 hj1 with ⟨e1, f1⟩ | ⟨hne1, hj1⟩ <;> rcases hths j2 t2 hj2 with ⟨e2, f2⟩ | ⟨hne2, hj2⟩
    · rw [e1, e2]
    · subst f1; exact absurd (.inl (hm'cell k hk1)) (hother j2 t2 k hne2 hj2 hk2)
    · subst f2; exact absurd (.inl (hm'cell k hk2)) (hother j1 t1 k hne1 hj1 hk1)
    · exact h.home _ _ _ _ k hj1 hj2 hk1 hk2
  · rcases hths j tj hj with ⟨_, e⟩ | ⟨hne, hj⟩
    · subst e
      rcases hk.one hbl k (h.onePlace hi k) with h1 | ⟨h1, _⟩
      · exact h1 k' (hblk k' k hk')
      · exact h1 (hm'cell k hc)
    · exact hother j tj k hne hj hc (.inr ⟨k', hblk k' k hk'⟩)
  · rcases hk.one hbl k (h.onePlace hi k) with h0 | ⟨_, huniq⟩
    · exact absurd (hblk k1 k h1) (h0 k1)
    · exact huniq k1 k2 (hblk k1 k h1) (hblk k2 k h2)

/-- Agora #755 item 1: **the reaps after a thread's step keep the cells'
    homes**: each is a step of the thread, ended by the marking sweep. -/
theorem CellInv.settle {P : Prog} {i : Nat} {C C' : Cfg} (h : CSettle P i C C') (hc : CellInv C) :
    CellInv C' := by
  induction h with
  | done _ => exact hc
  | reap hi hs _ _ ih => exact ih (hc.thread_of hi hs)

/-- A thread whose statement changes, and nothing else, keeps the cells'
    homes (a spawn whose crossing check fails). -/
theorem CellInv.setStmt {C : Cfg} (h : CellInv C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t)
    (s' : Stmt) : CellInv { C with ths := C.ths.set i ⟨t.st, t.nv, s'⟩ } := by
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hths : ∀ (j : Nat) (tj : Thread), ({ C with ths := C.ths.set i ⟨t.st, t.nv, s'⟩ } : Cfg).ths[j]? = some tj →
      ∃ tj0 : Thread, C.ths[j]? = some tj0 ∧ tj.st = tj0.st := by
    intro j tj hj
    simp only at hj
    rw [list_set_get hilen] at hj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; exact ⟨t, hij ▸ hi, rfl⟩
    · rw [ite_eq_right hij] at hj; exact ⟨tj, hj, rfl⟩
  have hcell : ∀ {t1 t2 : Thread} {k : Nat}, t1.st = t2.st → t1.cellAt k → t2.cellAt k := by
    intro t1 t2 k he hk
    obtain ⟨y, v, hy, hs⟩ := hk
    exact ⟨y, v, he ▸ hy, hs⟩
  refine ⟨fun j tj k hj hk => ?_, h.blkBelow, fun j1 j2 t1 t2 k hj1 hj2 hk1 hk2 => ?_,
    fun j tj k k' hj hk => ?_, h.one⟩
  · obtain ⟨tj0, hj0, he⟩ := hths j tj hj
    exact h.below j tj0 k hj0 (hcell he hk)
  · obtain ⟨t10, h10, he1⟩ := hths j1 t1 hj1
    obtain ⟨t20, h20, he2⟩ := hths j2 t2 hj2
    exact h.home j1 j2 t10 t20 k h10 h20 (hcell he1 hk1) (hcell he2 hk2)
  · obtain ⟨tj0, hj0, he⟩ := hths j tj hj
    exact h.apart j tj0 k k' hj0 (hcell he hk)

/-- Every value the arguments moved was in one of the spawner's slots. -/
theorem MoveArgs.val {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (h : MoveArgs st as vs st') : ∀ v ∈ vs, ∃ a, st a = some ⟨true, some v⟩ := by
  induction h with
  | nil => exact fun _ h => nomatch h
  | @cons st st' a as v vs ha _ ih =>
    intro w hw
    rcases List.mem_cons.mp hw with e | hw
    · subst e; exact ⟨a, ha⟩
    · obtain ⟨b, hb⟩ := ih w hw
      by_cases hba : b = a
      · subst hba; simp [upd] at hb
      · exact ⟨b, by simpa [upd, hba] using hb⟩

/-- **A spawn keeps the cells' homes, by the crossing check**: a cell the
    moved values hold a share of keeps none in the spawner (`SendCheck`), so
    the new thread becomes its home; any other stays where it was. -/
theorem CellInv.spawn_of {C : Cfg} (h : CellInv C) {i : Nat} {t : Thread} {K : Stmt → Stmt} {x : Nat}
    {k0 : Stmt} {fn : Fn} {args : List Var} {vs : List Val} {st' : Var → Option Slot}
    (hi : C.ths[i]? = some t) (hmv : MoveArgs t.st args vs st') (hsc : SendCheck C.blk vs st') :
    CellInv { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k0)⟩ ++
                      [⟨spawnSt fn vs, fn.nvars, wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] } := by
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  -- the spawner holds what it held
  have hS : ∀ k, (⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k0)⟩ : Thread).cellAt k →
      ∃ y w, st' y = some ⟨true, some w⟩ ∧ Sub (.cell k) w := by
    rintro k ⟨y, w, hy, hs⟩
    simp only [upd] at hy
    by_cases hyx : y = x
    · rw [ite_eq_left hyx] at hy; cases hy
    · rw [ite_eq_right hyx] at hy; exact ⟨y, w, hy, hs⟩
  have hS' : ∀ k, (⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k0)⟩ : Thread).cellAt k →
      t.cellAt k := by
    intro k hk
    obtain ⟨y, w, hy, hs⟩ := hS k hk
    rcases MoveArgs.slot hmv y _ hy with h0 | h0
    · exact ⟨y, w, h0, hs⟩
    · cases h0
  -- the new thread holds what a moved value held
  have hN : ∀ k, (⟨spawnSt fn vs, fn.nvars, wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩ :
      Thread).cellAt k → ∃ v ∈ vs, Sub (.cell k) v := by
    rintro k ⟨y, w, hy, hs⟩
    simp only [spawnSt] at hy
    split at hy
    · cases hy
    · cases hv : vs[y]? with
      | none => rw [hv] at hy; cases hy
      | some u => rw [hv] at hy; cases hy; exact ⟨_, List.mem_of_getElem? hv, hs⟩
  have hN' : ∀ k, (∃ v ∈ vs, Sub (.cell k) v) → t.cellAt k := by
    rintro k ⟨v, hv, hs⟩
    obtain ⟨a0, ha0⟩ := MoveArgs.val hmv v hv
    exact ⟨a0, v, ha0, hs⟩
  -- the threads of the new configuration
  have hths : ∀ j tj, ({ C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv,
        K (.scope x k0)⟩ ++ [⟨spawnSt fn vs, fn.nvars, wrapParams fn.params 0 0
        (.scope fn.params.length fn.body)⟩] } : Cfg).ths[j]? = some tj →
      (j = i ∧ tj = ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k0)⟩) ∨
      (j = C.ths.length ∧ tj = ⟨spawnSt fn vs, fn.nvars, wrapParams fn.params 0 0
        (.scope fn.params.length fn.body)⟩) ∨
      (j ≠ i ∧ j < C.ths.length ∧ C.ths[j]? = some tj) := by
    intro j tj hj
    simp only at hj
    rw [get_set_append hilen] at hj
    by_cases hjl : j < C.ths.length
    · rw [ite_eq_left hjl] at hj
      by_cases hij : i = j
      · rw [ite_eq_left hij] at hj; cases hj; exact .inl ⟨hij.symm, rfl⟩
      · rw [ite_eq_right hij] at hj; exact .inr (.inr ⟨Ne.symm hij, hjl, hj⟩)
    · rw [ite_eq_right hjl] at hj
      by_cases hje : j = C.ths.length
      · rw [ite_eq_left hje] at hj; cases hj; exact .inr (.inl ⟨hje, rfl⟩)
      · rw [ite_eq_right hje] at hj; cases hj
  refine ⟨fun j tj k hj hk => ?_, h.blkBelow, fun j1 j2 t1 t2 k hj1 hj2 hk1 hk2 => ?_,
    fun j tj k k' hj hk => ?_, h.one⟩
  · rcases hths j tj hj with ⟨_, e⟩ | ⟨_, e⟩ | ⟨_, _, hj⟩
    · subst e; exact h.below i t k hi (hS' k hk)
    · subst e; exact h.below i t k hi (hN' k (hN k hk))
    · exact h.below j tj k hj hk
  rotate_left
  · -- the blocks do not change: a moved value's shares were the spawner's
    rcases hths j tj hj with ⟨_, e⟩ | ⟨_, e⟩ | ⟨_, _, hj⟩
    · subst e; exact h.apart i t k k' hi (hS' k hk)
    · subst e; exact h.apart i t k k' hi (hN' k (hN k hk))
    · exact h.apart j tj k k' hj hk
  · rcases hths j1 t1 hj1 with ⟨e1, f1⟩ | ⟨e1, f1⟩ | ⟨hji1, _, hj1'⟩ <;>
      rcases hths j2 t2 hj2 with ⟨e2, f2⟩ | ⟨e2, f2⟩ | ⟨hji2, _, hj2'⟩
    · rw [e1, e2]
    · -- the spawner and the new thread: the crossing check
      subst f1; subst f2
      obtain ⟨y, w, hy, hs⟩ := hS k hk1
      exact absurd hs (hsc.1 k (hN k hk2) y w hy)
    · subst f1
      exact absurd (h.home _ _ _ _ k hi hj2' (hS' k hk1) hk2).symm hji2
    · subst f1; subst f2
      obtain ⟨y, w, hy, hs⟩ := hS k hk2
      exact absurd hs (hsc.1 k (hN k hk1) y w hy)
    · rw [e1, e2]
    · subst f1
      exact absurd (h.home _ _ _ _ k hi hj2' (hN' k (hN k hk1)) hk2).symm hji2
    · subst f2
      exact absurd (h.home _ _ _ _ k hj1' hi hk1 (hS' k hk2)) hji1
    · subst f2
      exact absurd (h.home _ _ _ _ k hj1' hi hk1 (hN' k (hN k hk2))) hji1
    · exact h.home _ _ _ _ k hj1' hj2' hk1 hk2

/-- A3.5's third cut: a live borrow of a library handle on a thread has an
    owner of it on the same thread (A2's `MInv.cell_owned`, over the thread's
    facts at any view of its slots). -/
theorem cellAt_of_live {m : Mem} {Γ : Ctx} {t : Thread} (hst : m.st = t.st) (hi : MInv m Γ) {y : Var}
    {E : Entry} {o : Bool} {w : Val} {k : Nat} (hy : Γ y = some E) (hl : E.live = true)
    (hw : t.st y = some ⟨o, some w⟩) (hs : Sub (.cell k) w) : t.cellAt k := by
  obtain ⟨x, T, hx, hT⟩ := hi.cell_owned hy hl (by rw [hst]; exact hw) hs
  exact ⟨x, T, by rw [← hst]; exact hx, hT⟩

/-- **Confinement over owners and live borrows**: two threads that each hold a
    share of one cell in an owned slot, or in a borrowed slot live in their
    typing context, are one thread.  (A dead borrow's slot is not counted: no
    rule reads a dead entry.) -/
theorem CellInv.live_home {C : Cfg} (h : CellInv C) {i j : Nat} {ti tj : Thread} {k : Nat}
    (hi : C.ths[i]? = some ti) (hj : C.ths[j]? = some tj)
    {mi mj : Mem} {Γi Γj : Ctx} (hsti : mi.st = ti.st) (hstj : mj.st = tj.st) (hii : MInv mi Γi)
    (hij : MInv mj Γj) {yi yj : Var} {Ei Ej : Entry} {oi oj : Bool} {wi wj : Val}
    (hyi : Γi yi = some Ei) (hli : Ei.live = true) (hwi : ti.st yi = some ⟨oi, some wi⟩) (hsi : Sub (.cell k) wi)
    (hyj : Γj yj = some Ej) (hlj : Ej.live = true) (hwj : tj.st yj = some ⟨oj, some wj⟩) (hsj : Sub (.cell k) wj) :
    i = j :=
  h.home i j ti tj k hi hj (cellAt_of_live hsti hii hyi hli hwi hsi) (cellAt_of_live hstj hij hyj hlj hwj hsj)

/-- What a typed `withLock` checks out through is a live binding. -/
theorem withLock_live {P : Prog} {Γ : Ctx} {F : List Var} {a x : Var} {s : Stmt} {Δ : Ctx} {m : Mem}
    (h : StmtT P Γ F (.withLock a x s) Δ) (hi : Inv m Γ F (.withLock a x s)) :
    ∃ Γ' Ea, MInv m Γ' ∧ Γ' a = some Ea ∧ Ea.live = true := by
  generalize hS : Stmt.withLock a x s = S at h hi
  induction h with
  | withLock _ _ _ ha hla _ _ _ _ _ _ => cases hS; exact ⟨_, _, hi.toMInv, ha, hla⟩
  | sub hw _ _ ih => exact ih hS (hi.weaker hw)
  | _ => cases hS

/-- A step on a cell's state is by a thread that holds an owner's share of
    it: a `withCell` through an owner, or through a live borrow, whose owner
    is on the thread (`cellAt_of_live`, from the thread's typing of the
    redex). -/
theorem CellOp.cellAt {P : Prog} {C : Cfg} (hc : CInv P C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t)
    {k : Nat} (h : CellOp t k) : t.cellAt k := by
  rcases h with ⟨K, a, x, s0, o, hR, ha⟩ | ⟨_, hk⟩
  · cases o with
    | true => exact ⟨a, _, ha, Sub.refl _⟩
    | false =>
      obtain ⟨ps, hcp, _⟩ := hc
      obtain ⟨pa, hpa⟩ := part_of hcp.len hi
      obtain ⟨⟨Γ, F, Δ, hT, hinv, _⟩, _⟩ := hcp.ok i t pa hi hpa
      obtain ⟨Γ', F', Δ', hT', hinv'⟩ := hR.typed Γ F Δ hT hinv
      obtain ⟨Γ'', Ea, hmi, hEa, hla⟩ := withLock_live hT' hinv'
      exact cellAt_of_live rfl hmi hEa hla ha (Sub.refl _)
  · exact hk

/-- **No cell race**: two threads never change one cell's state at once —
    each would hold an owner's share of it (`CellOp.cellAt`), and its owners
    are in one place: on one thread, or in one lock block's payload, which no
    thread's slot reaches until a check-out, a take or a receive moves the
    shares out to it. -/
theorem CellInv.cellRaceFree {P : Prog} {C : Cfg} (hc : CInv P C) (h : CellInv C) : ¬ CellRace C := by
  rintro ⟨i, j, ti, tj, k, hij, hi, hj, h1, h2⟩
  exact hij (h.home i j ti tj k hi hj (h1.cellAt hc hi) (h2.cellAt hc hj))

end A3
