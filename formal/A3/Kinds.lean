import A3.Keys

/-! A3.5 — Agora #815: **no block is named by both a lock share and a cell share.**

Cells and locks are both lock blocks (`BKind.lock`), and the typing cannot
tell them apart: a lock share `.lk k` of type `Ty.lk u` and a cell share
`.cell k` of type `Ty.cell u` both name a lock block of payload type `u`.
What keeps them apart is how their keys are made: `locked_new` (and
`chan_new`, `rw_new`, an `Atomic`'s constructor, all `lockNew`) and a cell's
constructor (`cellNew`) each take a fresh key from `nid`, above every share
in the configuration (`CKeys`), and make its one share, of their kind; every
other share is a copy of one that was there before (`lockClone`, `cellClone`,
a move, a borrow, a payload checked out or back in, a read of a global), of
the same kind.  No rule turns a lock share into a cell share or back:
`withLock` (and `Stmt.withCell`, the same rule) checks the block's payload out
through either, and the frame it opens (`scopeL`) gives it back by the key.

So there is a kind per key (`κ : Nat → Bool`, `true` for a cell's) that every
share of the configuration agrees with (`CKinds`): in every thread's slot
(live bindings and dead ones alike), in every block's payload and in the
module globals.  A configuration step keeps one (`TStep.kinds`: a step moves
`κ` only at the fresh key `nid`, which no share names yet).  The start has
one when its blocks and globals do (`GlobsKinds`), which the make phase
leaves (`make_ok`), and `GlobsOK` asks of the start (`GlobsOK.kinds`):
`GlobsTyped`, all it asked before, admits a start naming a key by both
(`mix_globsTyped`, `mix_not_shareKind`).  Hence `ShareKind`
(`reach_shareKind`): no key is named by a share `.lk k` and by a share
`.cell k` of one reached configuration, and a check-out of a cell's block is
through a cell share (`reach_frame_cell_owner`, A3/LockRoot.lean). -/

namespace A3
open A2

/-- `κ` moved at the key `n` only: to `b`. -/
def kSet (κ : Nat → Bool) (n : Nat) (b : Bool) : Nat → Bool := fun j => if j = n then b else κ j

theorem kSet_self (κ : Nat → Bool) (n : Nat) (b : Bool) : kSet κ n b n = b := by simp [kSet]

theorem kSet_lt {κ : Nat → Bool} {n : Nat} {b : Bool} {j : Nat} (h : j < n) : kSet κ n b j = κ j := by
  simp [kSet, Nat.ne_of_lt h]

namespace KK

/-- **A value below `n` agrees with every `κ'` that agrees with `κ` below `n`.** -/
theorem agree {n : Nat} {κ κ' : Nat → Bool} (hag : ∀ j, j < n → κ' j = κ j) {v : Val} (hb : KB n v)
    (h : KK κ v) : KK κ' v := by
  induction h with
  | int => exact .int
  | href => exact .href
  | view => exact .view
  | node _ ih => cases hb with | node hes => exact .node fun e he => ih e he (hes e he)
  | pair _ _ ih1 ih2 => cases hb with | pair h1 h2 => exact .pair (ih1 h1) (ih2 h2)
  | inl _ ih => cases hb with | inl h1 => exact .inl (ih h1)
  | inr _ ih => cases hb with | inr h1 => exact .inr (ih h1)
  | pkg _ ih => cases hb with | pkg h1 => exact .pkg (ih h1)
  | arc => exact .arc
  | lk h => cases hb with | lk hl => exact .lk (by rw [hag _ hl]; exact h)
  | cell h => cases hb with | cell hl => exact .cell (by rw [hag _ hl]; exact h)

theorem sub {κ : Nat → Bool} {w v : Val} (hs : Sub w v) (h : KK κ v) : KK κ w := by
  induction hs with
  | refl => exact h
  | child he _ ih => cases h with | node hes => exact ih (hes _ he)
  | fst _ ih => cases h with | pair h1 _ => exact ih h1
  | snd _ ih => cases h with | pair _ h2 => exact ih h2
  | inl _ ih => cases h with | inl h1 => exact ih h1
  | inr _ ih => cases h with | inr h1 => exact ih h1
  | pkg _ ih => cases h with | pkg h1 => exact ih h1

/-- A lock share a value holds names a key of kind `false`. -/
theorem lk_of {κ : Nat → Bool} {v : Val} (h : KK κ v) {k : Nat} (hs : Sub (.lk k) v) : κ k = false := by
  have h1 := h.sub hs; cases h1 with | lk h => exact h

/-- A cell share a value holds names a key of kind `true`. -/
theorem cell_of {κ : Nat → Bool} {v : Val} (h : KK κ v) {k : Nat} (hs : Sub (.cell k) v) : κ k = true := by
  have h1 := h.sub hs; cases h1 with | cell h => exact h

theorem lendOf {κ : Nat → Bool} {v : Val} (h : KK κ v) : KK κ (A2.lendOf v) := by
  induction h with
  | node _ _ => exact .href
  | pair _ _ ih1 ih2 => exact .pair ih1 ih2
  | inl _ ih => exact .inl ih
  | inr _ ih => exact .inr ih
  | pkg _ ih => exact .pkg ih
  | int => exact .int
  | href => exact .href
  | view => exact .view
  | arc => exact .arc
  | lk h => exact .lk h
  | cell h => exact .cell h

theorem repl {κ : Nat → Bool} {a b T T' : Val} (hr : Repl a b T T') (hT : KK κ T) (hb : KK κ b) : KK κ T' := by
  induction hr with
  | here => exact hb
  | elem _ ih =>
    cases hT with
    | node hes =>
      refine .node fun e he => ?_
      simp only [List.mem_append, List.mem_cons] at he
      rcases he with h | rfl | h
      · exact hes e (by simp [h])
      · exact ih (hes _ (by simp))
      · exact hes e (by simp [h])
  | fst _ ih => cases hT with | pair h1 h2 => exact .pair (ih h1) h2
  | snd _ ih => cases hT with | pair h1 h2 => exact .pair h1 (ih h2)
  | inl _ ih => cases hT with | inl h1 => exact .inl (ih h1)
  | inr _ ih => cases hT with | inr h1 => exact .inr (ih h1)
  | pkg _ ih => cases hT with | pkg h1 => exact .pkg (ih h1)

theorem node_of {κ : Nat → Bool} {t t' : Ty} {c d c' d' : Nat} {es es' : List Val} (h : KK κ (.node t c d es))
    {v : Val} (hv : KK κ v) (hsub : ∀ e ∈ es', e ∈ es ∨ e = v) : KK κ (.node t' c' d' es') := by
  cases h with
  | node hes =>
    refine .node fun e he => ?_
    rcases hsub e he with h | rfl
    · exact hes e h
    · exact hv

theorem node_elem {κ : Nat → Bool} {t : Ty} {c d : Nat} {es : List Val} (h : KK κ (.node t c d es)) {e : Val}
    (he : e ∈ es) : KK κ e := by
  cases h with | node hes => exact hes e he

end KK

/-! ### A store's shares -/

/-- Every share in a store's slots, its blocks' payloads and its globals
    agrees with `κ`. -/
structure MKinds (κ : Nat → Bool) (m : Mem) : Prop where
  st  : ∀ x o v, m.st x = some ⟨o, some v⟩ → KK κ v
  blk : ∀ k t kd v, m.blk k = some ⟨t, kd, some v⟩ → KK κ v
  gl  : ∀ g v, m.gl g = some v → KK κ v

/-- Some `κ'` that agrees with `κ` below `n` does it of `m`. -/
def KExt (κ : Nat → Bool) (n : Nat) (m : Mem) : Prop :=
  ∃ κ' : Nat → Bool, (∀ j, j < n → κ' j = κ j) ∧ MKinds κ' m

theorem KExt.map {κ : Nat → Bool} {n : Nat} {m m' : Mem} (h : KExt κ n m)
    (f : ∀ κ', MKinds κ' m → MKinds κ' m') : KExt κ n m' := by
  obtain ⟨κ', h1, h2⟩ := h; exact ⟨κ', h1, f κ' h2⟩

namespace MKinds

variable {κ : Nat → Bool}

theorem ext {n : Nat} {m : Mem} (h : MKinds κ m) : KExt κ n m := ⟨κ, fun _ _ => rfl, h⟩

theorem of_eq {m m' : Mem} (h : MKinds κ m) (hst : m'.st = m.st) (hb : m'.blk = m.blk) (hg : m'.gl = m.gl) :
    MKinds κ m' :=
  ⟨fun x o v hx => h.st x o v (by rw [← hst]; exact hx),
   fun k t kd v hk => h.blk k t kd v (by rw [← hb]; exact hk),
   fun g v hg' => h.gl g v (by rw [← hg]; exact hg')⟩

/-- **A store below its `nid` agrees with every `κ'` that agrees with `κ`
    below it.** -/
theorem agree {m : Mem} (h : MKinds κ m) (hk : MKeys m) {κ' : Nat → Bool}
    (hag : ∀ j, j < m.nid → κ' j = κ j) : MKinds κ' m :=
  ⟨fun x o v hx => (h.st x o v hx).agree hag (hk.st x o v hx),
   fun k t kd v hb => (h.blk k t kd v hb).agree hag (hk.blk k t kd v hb),
   fun g v hg => (h.gl g v hg).agree hag (hk.gl g v hg)⟩

theorem set {m : Mem} (h : MKinds κ m) (x : Var) {o : Bool} {w : Option Val}
    (hw : ∀ v, w = some v → KK κ v) : MKinds κ (m.set x ⟨o, w⟩) := by
  refine ⟨fun y o' v hy => ?_, h.blk, h.gl⟩
  simp only [Mem.set, upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy; exact hw v rfl
  · rw [ite_eq_right hyx] at hy; exact h.st y o' v hy

theorem withAlloc {m : Mem} (h : MKinds κ m) (a : Nat → Bool) : MKinds κ { m with alloc := a } :=
  ⟨h.st, h.blk, h.gl⟩

/-- Agora #810: which blocks are taken holds no share. -/
theorem withTaken {m : Mem} (h : MKinds κ m) (T : Nat → Bool) : MKinds κ { m with taken := T } :=
  ⟨h.st, h.blk, h.gl⟩

theorem withAN {m : Mem} (h : MKinds κ m) (a : Nat → Bool) (n : Nat) :
    MKinds κ { m with alloc := a, nid := n } := ⟨h.st, h.blk, h.gl⟩

theorem remove {m : Mem} (h : MKinds κ m) (x : Var) : MKinds κ (m.remove x) := by
  refine ⟨fun y o' v hy => ?_, h.blk, h.gl⟩
  simp only [Mem.remove, upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy
  · rw [ite_eq_right hyx] at hy; exact h.st y o' v hy

theorem updBlk {m : Mem} (h : MKinds κ m) (k : Nat) {t : Ty} {kd : BKind} {w : Option Val}
    (hw : ∀ v, w = some v → KK κ v) : MKinds κ { m with blk := upd m.blk k (some ⟨t, kd, w⟩) } := by
  refine ⟨h.st, fun k' t' kd' v hk => ?_, h.gl⟩
  simp only [upd] at hk
  by_cases he : k' = k
  · rw [ite_eq_left he] at hk; cases hk; exact hw v rfl
  · rw [ite_eq_right he] at hk; exact h.blk k' t' kd' v hk

theorem rd {m : Mem} (h : MKinds κ m) {k : Nat} {bl : Blk} (hk : m.blk k = some bl) : KK κ bl.rd := by
  obtain ⟨t, kd, pay⟩ := bl
  cases pay with
  | none => cases kd <;> exact .int
  | some v =>
    have hv := h.blk k t kd v hk
    cases kd <;> first | exact hv | exact .int

theorem nodeAt {m : Mem} (h : MKinds κ m) {c : Nat} {n : Val} (hn : NodeAt m c n) : KK κ n := by
  rcases hn with ⟨x, T, hT, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.st x true T hT).sub hs
  · exact (h.rd hk).sub hs

theorem dataAt {m : Mem} (h : MKinds κ m) {d : Nat} {n : Val} (hn : DataAt m d n) : KK κ n := by
  rcases hn with ⟨x, T, hT, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.st x true T hT).sub hs
  · exact (h.rd hk).sub hs

theorem vecOf {m : Mem} (h : MKinds κ m) {x : Var} {t : Ty} {c d : Nat} {es : List Val}
    (hv : VecOf m x t c d es) : KK κ (.node t c d es) := by
  rcases hv.2.2 with hx | ⟨_, hn⟩
  · exact h.st x true _ hx
  · exact h.nodeAt hn

theorem nodeOf {m : Mem} (h : MKinds κ m) {x o : Var} {T : Val} {t : Ty} {c d : Nat} {es : List Val}
    (hno : NodeOf m x o T t c d es) : KK κ T ∧ KK κ (.node t c d es) := by
  obtain ⟨_, _, ho, hxo⟩ := hno
  have hT := h.st _ _ _ ho
  refine ⟨hT, ?_⟩
  rcases hxo with ⟨_, rfl⟩ | ⟨_, hs⟩
  · exact hT
  · exact hT.sub hs

theorem takeVal {m m1 : Mem} (h : MKinds κ m) {y : Var} {v : Val} (ht : TakeVal m y v m1) :
    MKinds κ m1 ∧ KK κ v ∧ m1.nid = m.nid := by
  cases ht with
  | own hy => exact ⟨h.set y (fun _ h => by cases h), h.st y true v hy, rfl⟩
  | bor hy _ => exact ⟨h, h.st y false v hy, rfl⟩

end MKinds

/-- A right-hand side's fresh share, by its kind: `cell_new` makes a cell
    share, every other a lock share or none. -/
def _root_.A2.Rhs.isCellNew : Rhs → Bool
  | .cellNew _ _ => true
  | _ => false

/-- **A right-hand side keeps the store's shares agreeing with `κ`**, and its
    value's, when `κ` gives the key `nid` the kind of the share a
    constructor makes there. -/
theorem EvalR.kinds_of {κ : Nat → Bool} {m m' : Mem} {r : Rhs} {v : Val} {o : Bool}
    (h : EvalR m r (.ok v o m')) (hk : MKinds κ m) (hf : κ m.nid = r.isCellNew) :
    MKinds κ m' ∧ KK κ v := by
  cases h with
  | expr _ => exact ⟨hk, .int⟩
  | new => exact ⟨hk.of_eq rfl rfl rfl, .node fun _ h => by cases h⟩
  | moveOwn hy => exact ⟨hk.set _ (fun _ h => by cases h), hk.st _ _ _ hy⟩
  | take hy =>
    exact ⟨(hk.of_eq (m' := { m with alloc := upd (upd m.alloc m.nid true) (m.nid + 1) true, nid := m.nid + 2 })
      rfl rfl rfl).set _
      (fun _ h => by cases h; exact .node fun _ h => by cases h), hk.st _ _ _ hy⟩
  | copy hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | borrowOwn _ => exact ⟨hk, .href⟩
  | borrowBor hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | «at» h hv _ => exact ⟨hk, ((hk.vecOf hv).node_elem (List.getElem_mem h)).lendOf⟩
  | view _ => exact ⟨hk, .view⟩
  | sat h _ _ _ _ hd => exact ⟨hk, ((hk.dataAt hd).node_elem (List.getElem_mem h)).lendOf⟩
  | pop hy _ _ =>
    have hT := hk.st _ _ _ hy
    refine ⟨hk.set _ (fun w hw => ?_), hT.node_elem (by simp)⟩
    cases hw; exact hT.node_of (KK.int (j := 0)) (fun e he => .inl (by simp [he]))
  | remove h hy _ _ _ =>
    have hT := hk.st _ _ _ hy
    refine ⟨hk.set _ (fun w hw => ?_), hT.node_elem (List.getElem_mem h)⟩
    cases hw; exact hT.node_of (KK.int (j := 0)) (fun e he => .inl (List.mem_of_mem_eraseIdx he))
  | pair h1 h2 =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1
    obtain ⟨hk2, hv2, _⟩ := hk1.takeVal h2
    exact ⟨hk2, .pair hv1 hv2⟩
  | fst hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | pair h1 _ => exact ⟨hk, h1.lendOf⟩
  | snd hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | pair _ h2 => exact ⟨hk, h2.lendOf⟩
  | inl h1 => obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1; exact ⟨hk1, .inl hv1⟩
  | inr h1 => obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1; exact ⟨hk1, .inr hv1⟩
  | getl hy => have hT := hk.st _ _ _ hy; cases hT with | inl h1 => exact ⟨hk, h1.lendOf⟩
  | getr hy => have hT := hk.st _ _ _ hy; cases hT with | inr h1 => exact ⟨hk, h1.lendOf⟩
  | takel hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | inl h1 => exact ⟨hk.set _ (fun _ h => by cases h), h1⟩
  | taker hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | inr h1 => exact ⟨hk.set _ (fun _ h => by cases h), h1⟩
  | pack h1 => obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1; exact ⟨hk1, .pkg hv1⟩
  | arcNew h1 _ =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1
    exact ⟨(hk1.updBlk _ (fun w hw => by cases hw; exact hv1)).of_eq rfl rfl rfl, .arc⟩
  | arcClone hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | arcGet _ hb => exact ⟨hk, (hk.rd hb).lendOf⟩
  | lockNew h1 _ _ =>
    obtain ⟨hk1, hv1, hn1⟩ := hk.takeVal h1
    refine ⟨(hk1.updBlk _ (fun w hw => by cases hw; exact hv1)).of_eq rfl rfl rfl, .lk ?_⟩
    rw [hn1]; exact hf
  | lockClone hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | cellNew h1 _ _ =>
    obtain ⟨hk1, hv1, hn1⟩ := hk.takeVal h1
    refine ⟨(hk1.updBlk _ (fun w hw => by cases hw; exact hv1)).of_eq rfl rfl rfl, .cell ?_⟩
    rw [hn1]; exact hf
  | cellClone hy _ => exact ⟨hk, hk.st _ _ _ hy⟩
  | atomic _ _ _ _ _ => exact ⟨hk.updBlk _ (fun w hw => by cases hw; exact .int), .int⟩
  | chanSend _ h1 hb _ _ _ _ =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1
    refine ⟨hk1.updBlk _ (fun w hw => ?_), .int⟩
    cases hw
    have hq := hk1.blk _ _ _ _ hb
    cases hq with
    | pair hq1 _ =>
      exact .pair (hq1.node_of hv1 (fun e he => by
        simp only [List.mem_append, List.mem_singleton] at he; exact he)) .int
  | chanSendClosed _ h1 _ _ _ _ =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1
    exact ⟨(hk1.updBlk _ (fun w hw => by cases hw; exact hv1)).of_eq rfl rfl rfl, .int⟩
  | chanRecv _ hb _ _ _ _ =>
    have hq := hk.blk _ _ _ _ hb
    cases hq with
    | pair hq1 _ =>
      refine ⟨hk.updBlk _ (fun w hw => ?_), .inr (hq1.node_elem (by simp))⟩
      cases hw; exact .pair (hq1.node_of (KK.int (j := 0)) (fun e he => .inl (by simp [he]))) .int
  | chanRecvNone _ _ _ _ => exact ⟨hk, .inl .int⟩
  | chanClose _ hb _ =>
    have hq := hk.blk _ _ _ _ hb
    cases hq with
    | pair hq1 _ => exact ⟨hk.updBlk _ (fun w hw => by cases hw; exact .pair hq1 .int), .int⟩
  | rwRead ha hb _ =>
    have hl := hk.st _ _ _ ha
    have hp := hk.blk _ _ _ _ hb
    exact ⟨(hk.updBlk _ (fun w hw => by cases hw; exact .pair hl hp)).of_eq rfl rfl rfl, .arc⟩
  | rwTryRead ha hb _ =>
    have hl := hk.st _ _ _ ha
    have hp := hk.blk _ _ _ _ hb
    exact ⟨(hk.updBlk _ (fun w hw => by cases hw; exact .pair hl hp)).of_eq rfl rfl rfl, .inr .arc⟩
  | rwTryReadNone _ _ => exact ⟨hk, .inl .int⟩
  | rwTryWrite _ _ _ => exact ⟨hk, .inr .int⟩
  | rwTryWriteNone _ _ => exact ⟨hk, .inl .int⟩
  | glob hg _ => exact ⟨hk, hk.gl _ _ hg⟩
  | lockTake _ hb _ =>
    exact ⟨(hk.updBlk _ (fun _ h => by cases h)).withTaken _, hk.blk _ _ _ _ hb⟩
  | lockRestore _ h1 _ _ _ =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal h1
    exact ⟨hk1.updBlk _ (fun w hw => by cases hw; exact hv1), .int⟩

/-- **A right-hand side keeps the store's shares agreeing with a kind per
    key**: `κ` moved at the key `nid` (no share names it, `MKeys`) to the
    kind of the share a constructor makes there. -/
theorem EvalR.kinds {κ : Nat → Bool} {m m' : Mem} {r : Rhs} {v : Val} {o : Bool}
    (h : EvalR m r (.ok v o m')) (hK : MKeys m) (hk : MKinds κ m) :
    ∃ κ' : Nat → Bool, (∀ j, j < m.nid → κ' j = κ j) ∧ MKinds κ' m' ∧ KK κ' v :=
  ⟨kSet κ m.nid r.isCellNew, fun _ hj => kSet_lt hj,
    EvalR.kinds_of h (hk.agree hK fun _ hj => kSet_lt hj) (kSet_self _ _ _)⟩

theorem BindParams.kinds {κ : Nat → Bool} {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (hk : MKinds κ m) : MKinds κ m' := by
  induction h with
  | nil => exact hk
  | @inp m0 m1 t ps a as base i sl v ha hl _ ih =>
    refine ih (hk.set _ (fun w hw => ?_))
    cases hw
    obtain ⟨o, w'⟩ := sl
    cases o <;> cases w' <;> simp only [lendSlot, Option.some.injEq, reduceCtorEq] at hl
    · subst hl; exact hk.st _ _ _ ha
    · subst hl; exact (hk.st _ _ _ ha).lendOf
  | sink ha _ ih => exact ih ((hk.set _ (fun _ h => by cases h)).set _ (fun w hw => by cases hw; exact hk.st _ _ _ ha))
  | inout _ ih => exact ih hk

theorem Release.kinds {κ : Nat → Bool} {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m')
    (hk : MKinds κ m) : MKinds κ m' := by
  cases h with
  | put hx _ _ _ => exact (hk.updBlk _ (fun w hw => by cases hw; exact hk.st _ _ _ hx)).remove x
  | drop _ _ _ => exact (hk.withAlloc _).remove x

/-- **A step keeps the store's shares agreeing with a kind per key**, to a
    configuration or a panic: `κ` moved only at keys `nid` or above. -/
theorem Step.kinds {P : Prog} {κ : Nat → Bool} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r)
    (hK : MKeys m) (hk : MKinds κ m) : KExt κ m.nid r.mem := by
  induction h with
  | seqSkip => exact hk.ext
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he =>
    obtain ⟨κ', hag, h1, h2⟩ := EvalR.kinds he hK hk
    exact ⟨κ', hag, h1.set _ (fun w hw => by cases hw; exact h2)⟩
  | letvP _ => exact hk.ext
  | letcall _ _ hb =>
    have h1 := BindParams.kinds hb hk
    refine MKinds.ext ?_; exact ((h1.set _ (fun _ h => by cases h)).set _ (fun _ h => by cases h)).of_eq rfl rfl rfl
  | scopeSkip _ _ => exact ((hk.withAlloc _).remove _).ext
  | scopeIn _ ih => exact ih
  | scopeP _ _ _ ih => exact (ih).map fun _ h => (h.withAlloc _).remove _
  | rbindSkip _ => exact (hk.remove _).ext
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact (ih).map fun _ h => h.remove _
  | frozenSkip => exact hk.ext
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ _ =>
    obtain ⟨κ', hag, h1, h2⟩ := EvalR.kinds he hK hk
    exact ⟨κ', hag, (h1.withAlloc _).set _ (fun w hw => by cases hw; exact h2)⟩
  | assignP _ => exact hk.ext
  | iteT _ _ => exact hk.ext
  | iteF _ => exact hk.ext
  | «while» => exact hk.ext
  | push ht hx _ _ =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal ht
    refine (hk1.set _ (fun w hw => ?_)).ext
    cases hw
    exact (hk1.st _ _ _ hx).node_of hv1 (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he)
  | pushRealloc ht hx _ _ =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal ht
    refine ((hk1.withAN _ _).set _ (fun w hw => ?_)).ext
    cases hw
    exact (hk1.st _ _ _ hx).node_of hv1 (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he)
  | editPush ht hno hr =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal ht
    obtain ⟨hT, hN⟩ := hk1.nodeOf hno
    refine (hk1.set _ (fun w hw => ?_)).ext
    cases hw
    exact hT.repl hr (hN.node_of hv1 (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he))
  | editPushRealloc ht hno hr =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal ht
    obtain ⟨hT, hN⟩ := hk1.nodeOf hno
    refine ((hk1.withAN _ _).set _ (fun w hw => ?_)).ext
    cases hw
    exact hT.repl hr (hN.node_of hv1 (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he))
  | editTrunc _ hno _ hr =>
    obtain ⟨hT, hN⟩ := hk.nodeOf hno
    refine ((hk.withAlloc _).set _ (fun w hw => ?_)).ext
    cases hw
    exact hT.repl hr (hN.node_of (KK.int (j := 0)) (fun e he => .inl (List.mem_of_mem_take he)))
  | editSet _ _ ht hno _ hr =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal ht
    obtain ⟨hT, hN⟩ := hk1.nodeOf hno
    refine ((hk1.withAlloc _).set _ (fun w hw => ?_)).ext
    cases hw
    exact hT.repl hr (hN.node_of hv1 (fun e he => by
      rcases List.mem_or_eq_of_mem_set he with h | h
      · exact .inl h
      · exact .inr h))
  | editSetOOB _ ht _ _ _ =>
    obtain ⟨hk1, _, _⟩ := hk.takeVal ht
    exact (hk1.withAlloc _).ext
  | insert _ ht hx _ _ =>
    obtain ⟨hk1, hv1, _⟩ := hk.takeVal ht
    refine (hk1.set _ (fun w hw => ?_)).ext
    cases hw
    exact (hk1.st _ _ _ hx).node_of hv1 (fun e he => by
      simp only [List.mem_append, List.mem_cons] at he
      rcases he with h | h | h
      · exact .inl (List.mem_of_mem_take h)
      · exact .inr h
      · exact .inl (List.mem_of_mem_drop h))
  | withElem h hv _ _ _ _ =>
    have hT := hk.st _ _ _ hv
    refine ((hk.set _ (fun w hw => ?_)).set _ (fun w hw => ?_)).ext
    · cases hw
      exact hT.node_of (KK.int (j := 0)) (fun e he => by
        simp only [List.mem_append] at he
        rcases he with h | h
        · exact .inl (List.mem_of_mem_take h)
        · exact .inl (List.mem_of_mem_drop h))
    · cases hw; exact hT.node_elem (List.getElem_mem h)
  | withElemOOB _ _ _ _ => exact hk.ext
  | free _ _ => exact ((hk.withAlloc _).set _ (fun _ h => by cases h)).ext
  | panic => exact hk.ext
  | waitPanic _ => exact hk.ext
  | letrec _ _ _ =>
    refine MKinds.ext ?_; exact ((hk.set _ (fun _ h => by cases h)).set _ (fun _ h => by cases h)).of_eq rfl rfl rfl
  | catchIn _ ih => exact ih
  | catchSkip => exact hk.ext
  | unpair hy _ _ _ =>
    have hT := hk.st _ _ _ hy
    cases hT with
    | pair h1 h2 =>
      exact (((hk.set _ (fun _ h => by cases h)).set _ (fun w hw => by cases hw; exact h1)).set _
        (fun w hw => by cases hw; exact h2)).ext
  | callc hc _ _ _ hb =>
    have hT := hk.st _ _ _ hc
    cases hT with
    | pkg he =>
      have h0 : MKinds κ (envMem _ _) :=
        (hk.set _ (fun w hw => by cases hw; exact he.lendOf)).of_eq rfl rfl rfl
      have h1 := BindParams.kinds hb h0
      refine MKinds.ext ?_; exact ((h1.set _ (fun _ h => by cases h)).set _ (fun _ h => by cases h)).of_eq rfl rfl rfl
  | callcE hc _ _ _ _ =>
    have hT := hk.st _ _ _ hc
    cases hT with
    | pkg he =>
      refine MKinds.ext ?_
      exact (((hk.set _ (fun _ h => by cases h)).set _ (fun w hw => by cases hw; exact he)).set _
        (fun _ h => by cases h)).of_eq rfl rfl rfl
  | callcD hc _ _ _ _ =>
    have hT := hk.st _ _ _ hc
    cases hT with
    | pkg he =>
      refine MKinds.ext ?_
      exact (((hk.set _ (fun _ h => by cases h)).set _ (fun w hw => by cases hw; exact he)).set _
        (fun _ h => by cases h)).of_eq rfl rfl rfl
  | catchP _ _ ih => exact (ih).map fun _ h => h.set _ (fun w hw => by cases hw; exact .int)
  | letd _ he =>
    obtain ⟨κ', hag, h1, h2⟩ := EvalR.kinds he hK hk
    exact ⟨κ', hag, h1.set _ (fun w hw => by cases hw; exact h2)⟩
  | letdP _ => exact hk.ext
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ _ => exact MKinds.ext (hk.of_eq (m' := { m with nv := m.nv + 1 }) rfl rfl rfl)
  | scopeDMoved _ => exact (hk.remove _).ext
  | scopeDDrain _ => exact MKinds.ext (hk.of_eq (m' := { m with nv := m.nv + 1 }) rfl rfl rfl)
  | scopeDEmpty _ => exact hk.ext
  | scopeDP _ _ _ ih => exact ih
  | scopeDPDrain _ _ ih | scopeLPD _ _ _ _ _ ih => exact ih
  | scopeDPMoved _ _ ih => exact (ih).map fun _ h => h.remove _
  | withLock _ hb _ _ =>
    refine MKinds.ext ?_
    exact ((hk.updBlk _ (fun _ h => by cases h)).withTaken _).set _ (fun w hw => by cases hw; exact hk.blk _ _ _ _ hb)
  | scopeLIn _ ih => exact ih
  | scopeLSkip hrl _ => exact (Release.kinds hrl hk).ext
  | scopeLFail _ _ => exact hk.ext
  | scopeLP _ hrl ih => exact (ih).map fun _ h => Release.kinds hrl h
  | reap _ hb _ =>
    have hp := hk.blk _ _ _ _ hb
    refine MKinds.ext ?_
    exact ((hk.set _ (fun w hw => by cases hw; exact hp)).updBlk _ (fun _ h => by cases h)).of_eq
      rfl rfl rfl

/-! ### A configuration's shares -/

/-- **Every share in the configuration agrees with the kind per key `κ`**:
    in every thread's slots (live bindings and dead ones alike), in every
    block's payload, and in the module globals. -/
structure CKinds (κ : Nat → Bool) (C : Cfg) : Prop where
  ths : ∀ (j : Nat) (t : Thread), C.ths[j]? = some t → ∀ x o v, t.st x = some ⟨o, some v⟩ → KK κ v
  blk : ∀ k t kd v, C.blk k = some ⟨t, kd, some v⟩ → KK κ v
  gl  : ∀ g v, C.gl g = some v → KK κ v

namespace CKinds

variable {κ : Nat → Bool}

theorem view {C : Cfg} (h : CKinds κ C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t) :
    MKinds κ (C.view t) :=
  ⟨h.ths i t hi, h.blk, h.gl⟩

/-- A thread's step written back, its store agreeing with a `κ'` that agrees
    with `κ` below the configuration's `nid` (which every other thread's
    shares are below, `CKeys`). -/
theorem put {C : Cfg} (h : CKinds κ C) (hK : CKeys C) {κ' : Nat → Bool} (hag : ∀ j, j < C.nid → κ' j = κ j)
    {i : Nat} {m' : Mem} {s' : Stmt} (hm : MKinds κ' m') : CKinds κ' (C.put i m' s') := by
  refine ⟨fun j t hj x o v hx => ?_, hm.blk, hm.gl⟩
  simp only [Cfg.put] at hj ⊢
  by_cases hji : i = j
  · subst hji
    by_cases hlt : i < C.ths.length
    · rw [List.getElem?_set_self hlt] at hj
      cases hj; exact hm.st x o v hx
    · have : (C.ths.set i ⟨m'.st, m'.nv, s'⟩)[i]? = none :=
        List.getElem?_eq_none (by simp only [List.length_set]; omega)
      rw [this] at hj; cases hj
  · rw [List.getElem?_set_ne hji] at hj
    exact (h.ths j t hj x o v hx).agree hag (hK.ths j t hj x o v hx)

/-- The marking sweep keeps it: it keeps or marks blocks, their payloads as
    they were. -/
theorem sweepD {C : Cfg} (h : CKinds κ C) : CKinds κ C.sweepD := by
  refine ⟨h.ths, fun k t kd v hk => ?_, h.gl⟩
  rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, _, he⟩
  · exact h.blk k t kd v hk0
  · obtain ⟨t0, kd0, p0⟩ := bl0
    simp only [Blk.mark, Blk.mk.injEq] at he
    obtain ⟨rfl, -, rfl⟩ := he
    exact h.blk k _ _ v hk0

/-- A thread's step, the marking sweep after it: the shares agree with a
    kind per key, `κ` moved at keys `nid` or above only. -/
theorem step {P : Prog} {C : Cfg} (h : CKinds κ C) (hK : CKeys C) {i : Nat} {t : Thread} {m' : Mem}
    {s' : Stmt} (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) :
    ∃ κ', CKinds κ' (C.put i m' s').sweepD := by
  obtain ⟨κ', hag, hm⟩ := Step.kinds hst (hK.view hi) (h.view hi)
  exact ⟨κ', (h.put hK hag hm).sweepD⟩

end CKinds

theorem CSettle.kinds {P : Prog} {i : Nat} {C C' : Cfg} (hse : CSettle P i C C') {κ : Nat → Bool}
    (h : CKinds κ C) (hK : CKeys C) : ∃ κ', CKinds κ' C' := by
  induction hse generalizing κ with
  | done _ => exact ⟨κ, h⟩
  | reap hi hs _ _ ih =>
    obtain ⟨κ', h'⟩ := h.step hK hi hs
    exact ih h' (hK.step hi hs)

theorem MoveArgs.kinds {κ : Nat → Bool} {st st' : Var → Option Slot} {as : List Var} {vs : List Val}
    (hm : MoveArgs st as vs st') (h : ∀ x o v, st x = some ⟨o, some v⟩ → KK κ v) :
    (∀ x o v, st' x = some ⟨o, some v⟩ → KK κ v) ∧ ∀ v ∈ vs, KK κ v := by
  induction hm with
  | nil => exact ⟨h, fun _ h => by cases h⟩
  | @cons st st' a as v vs ha _ ih =>
    have h' : ∀ x o w, upd st a (some ⟨true, none⟩) x = some ⟨o, some w⟩ → KK κ w := by
      intro x o w hx
      simp only [upd] at hx
      by_cases hxa : x = a
      · rw [ite_eq_left hxa] at hx; cases hx
      · rw [ite_eq_right hxa] at hx; exact h x o w hx
    obtain ⟨h1, h2⟩ := ih h'
    refine ⟨h1, fun w hw => ?_⟩
    rcases List.mem_cons.mp hw with rfl | hw
    · exact h a true w ha
    · exact h2 w hw

/-- **A configuration step keeps a kind per key**: a thread's step and its
    reaps (`κ` moved at the fresh key a constructor takes), and a spawn (what
    it moves is the spawner's). -/
theorem TStep.kinds {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (hs : TStep P spawn C C') {κ : Nat → Bool}
    (h : CKinds κ C) (hK : CKeys C) : ∃ κ', CKinds κ' C' := by
  cases hs with
  | thread hi _ hst hse =>
    obtain ⟨κ', h'⟩ := h.step hK hi hst
    exact CSettle.kinds hse h' (hK.step hi hst)
  | @spawn i t K x f args k fn vs st' hi _ _ _ _ hm _ =>
    obtain ⟨h1, h2⟩ := MoveArgs.kinds hm (h.ths i t hi)
    refine ⟨κ, fun j t' hj y o v hy => ?_, h.blk, h.gl⟩
    simp only at hj ⊢
    have hlen : (C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩).length =
        C.ths.length := List.length_set ..
    by_cases hjl : j < C.ths.length
    · rw [List.getElem?_append_left (by rw [hlen]; exact hjl)] at hj
      by_cases hji : i = j
      · subst hji
        rw [List.getElem?_set_self (by exact hjl)] at hj
        cases hj
        simp only [upd] at hy
        by_cases hyx : y = x
        · rw [ite_eq_left hyx] at hy; cases hy; exact .int
        · rw [ite_eq_right hyx] at hy; exact h1 y o v hy
      · rw [List.getElem?_set_ne hji] at hj
        exact h.ths j t' hj y o v hy
    · rw [List.getElem?_append_right (by rw [hlen]; omega)] at hj
      rw [hlen] at hj
      cases hjj : j - C.ths.length with
      | succ _ => rw [hjj] at hj; simp at hj
      | zero =>
        rw [hjj] at hj
        simp only [List.getElem?_cons_zero, Option.some.injEq] at hj
        subst hj
        simp only [spawnSt] at hy
        split at hy
        · cases hy
        · cases hv : vs[y]? with
          | none => rw [hv] at hy; cases hy
          | some w =>
            rw [hv] at hy; cases hy
            exact h2 v (List.mem_of_getElem? hv)
  | @spawnFail i t K x f args k fn vs st' hi _ _ _ _ _ _ =>
    refine ⟨κ, fun j t' hj y o v hy => ?_, h.blk, h.gl⟩
    simp only at hj ⊢
    by_cases hji : i = j
    · subst hji
      have hlt : _ < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
      rw [List.getElem?_set_self hlt] at hj
      cases hj; exact h.ths _ _ hi y o v hy
    · rw [List.getElem?_set_ne hji] at hj
      exact h.ths j t' hj y o v hy

theorem Reach.kinds {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (hr : Reach P spawn C C') {κ : Nat → Bool}
    (h : CKinds κ C) (hK : CKeys C) : ∃ κ', CKinds κ' C' := by
  induction hr generalizing κ with
  | refl => exact ⟨κ, h⟩
  | step hs _ ih =>
    obtain ⟨κ', h'⟩ := TStep.kinds hs h hK
    exact ih h' (TStep.keys hs hK)

/-! ### The start -/

theorem CKinds.start {G : Globs} (hG : GlobsKinds G) (s : Stmt) (nv : Nat) :
    ∃ κ, CKinds κ (Cfg.start G s nv) := by
  obtain ⟨κ, hb, hg⟩ := hG
  refine ⟨κ, fun j t hj x o v hx => ?_, hb, hg⟩
  simp only [Cfg.start] at hj
  cases j with
  | zero => simp at hj; subst hj; cases hx
  | succ _ => simp at hj

/-- **On every configuration a typed start reaches, a kind per key agrees
    with every share** (the start's globals keep lock and cell shares apart,
    `GlobsOK.kinds`). -/
theorem reach_kinds {P : Prog} {spawn : Nat → Bool} {G : Globs} (hG : GlobsOK P G)
    {s : Stmt} {nv : Nat} {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C) : ∃ κ, CKinds κ C := by
  obtain ⟨κ, h⟩ := CKinds.start hG.kinds s nv
  exact Reach.kinds hr h (CKeys.start hG s nv)

/-! ### No key named by both a lock share and a cell share -/

-- `Cfg.Holds` (some value of the configuration holds a share) is in
-- A3/Defs.lean, where `A3.CellAdequate` states with it what a cell's block is.

/-- **Agora #815: no key is named by both a lock share and a cell share** of
    the configuration: if some value holds `.lk k`, none holds `.cell k`. -/
def ShareKind (C : Cfg) : Prop := ∀ k, C.Holds (.lk k) → ¬ C.Holds (.cell k)

theorem CKinds.holds_lk {κ : Nat → Bool} {C : Cfg} (h : CKinds κ C) {k : Nat} (hl : C.Holds (.lk k)) :
    κ k = false := by
  rcases hl with ⟨j, t, x, o, v, hj, hx, hs⟩ | ⟨k', t, kd, v, hk, hs⟩ | ⟨g, v, hg, hs⟩
  · exact (h.ths j t hj x o v hx).lk_of hs
  · exact (h.blk k' t kd v hk).lk_of hs
  · exact (h.gl g v hg).lk_of hs

theorem CKinds.holds_cell {κ : Nat → Bool} {C : Cfg} (h : CKinds κ C) {k : Nat} (hc : C.Holds (.cell k)) :
    κ k = true := by
  rcases hc with ⟨j, t, x, o, v, hj, hx, hs⟩ | ⟨k', t, kd, v, hk, hs⟩ | ⟨g, v, hg, hs⟩
  · exact (h.ths j t hj x o v hx).cell_of hs
  · exact (h.blk k' t kd v hk).cell_of hs
  · exact (h.gl g v hg).cell_of hs

theorem CKinds.shareKind {κ : Nat → Bool} {C : Cfg} (h : CKinds κ C) : ShareKind C := fun _ hl hc => by
  have h1 := h.holds_lk hl; rw [h.holds_cell hc] at h1; cases h1

/-- **Agora #815: on every configuration a typed start reaches, no block is
    named by both a lock share and a cell share.** -/
theorem reach_shareKind {P : Prog} {spawn : Nat → Bool} {G : Globs} (hG : GlobsOK P G)
    {s : Stmt} {nv : Nat} {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C) : ShareKind C := by
  obtain ⟨κ, h⟩ := reach_kinds hG hr
  exact h.shareKind

/-! ### Why `GlobsOK` asks `GlobsKinds`

A start `GlobsTyped` holds of (every condition `GlobsOK` asked before
Agora #815) whose key 0 is named by a lock share (global 0, a `Locked int`)
and by a cell share (in the payload of block 1, the lock global 1 shares, a
`Locked (cell int)`): both name a lock block of payload type `int`, which is
all the typing asks of either.  On it a thread checking block 0 out through
the global's lock share changes the cell's state with no owner's share of
the cell: no `CellOp`, so a race with a `withCell` on the cell, which the
runtime runs with no lock, would not be a `Race`.  `GlobsOK` refuses it
(`mix_not_globsOK`); no make phase leaves it (`make_ok`). -/

/-- Block 0 a lock of an integer, block 1 a lock whose payload is a cell
    share of block 0. -/
def mixB : Nat → Option Blk := fun k =>
  if k = 0 then some ⟨.int, .lock, some (.int 0)⟩
  else if k = 1 then some ⟨.cell .int, .lock, some (.cell 0)⟩ else none

/-- ... global 0 a lock share of block 0, global 1 one of block 1. -/
def mixG : Globs :=
  ⟨fun _ => false, 2, mixB, fun g => if g = 0 then some (.lk 0) else if g = 1 then some (.lk 1) else none,
   fun _ => false⟩

theorem mixB_some {k : Nat} {bl : Blk} (h : mixB k = some bl) :
    (k = 0 ∧ bl = ⟨.int, .lock, some (.int 0)⟩) ∨ (k = 1 ∧ bl = ⟨.cell .int, .lock, some (.cell 0)⟩) := by
  unfold mixB at h
  by_cases h0 : k = 0
  · rw [ite_eq_left h0] at h; cases h; exact .inl ⟨h0, rfl⟩
  · rw [ite_eq_right h0] at h
    by_cases h1 : k = 1
    · rw [ite_eq_left h1] at h; cases h; exact .inr ⟨h1, rfl⟩
    · rw [ite_eq_right h1] at h; cases h

/-- `GlobsTyped` holds of it ... -/
theorem mix_globsTyped (P : Prog) : GlobsTyped P mixG where
  sync g v h := by
    simp only [mixG] at h
    by_cases h0 : g = 0
    · rw [ite_eq_left h0] at h; cases h
      exact ⟨.lk .int, rfl, rfl, .inl ⟨.int, 0, _, rfl, rfl, rfl⟩⟩
    · rw [ite_eq_right h0] at h
      by_cases h1 : g = 1
      · rw [ite_eq_left h1] at h; cases h
        exact ⟨.lk (.cell .int), rfl, rfl, .inl ⟨.cell .int, 1, _, rfl, rfl, rfl⟩⟩
      · rw [ite_eq_right h1] at h; cases h
  inv := {
    dom := fun _ => rfl
    slot := fun _ _ h => by cases h
    heap := by
      refine ⟨fun _ _ h => (by cases h), fun _ _ _ _ _ h => (by cases h), fun _ _ h => (by cases h),
        fun _ _ h => (by cases h), fun k bl hk => ?_, fun k bl hk hv => ?_⟩
      · rcases mixB_some hk with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
        · exact ⟨by decide, by simp [Blk.tree], fun i hi => by simp [Blk.tree] at hi⟩
        · exact ⟨by decide, by simp [Blk.tree, Val.ids], fun i hi => by simp [Blk.tree, Val.ids] at hi⟩
      · rcases mixB_some hk with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> cases hv
    nvSt := fun _ h => by cases h
    noInout := fun _ _ _ h => by cases h
    wf := ⟨fun _ _ h => (by cases h), fun _ _ h => (by cases h), fun _ _ h => (by cases h),
      fun _ _ h => (by cases h)⟩
    rootbLive := fun _ _ h => by cases h
    rootbLt := fun _ _ h => by cases h
    names := fun _ _ h => by cases h
    held := fun _ _ _ _ h => by cases h
    pkgs := fun _ _ _ h => by cases h
    armed := fun _ _ _ h => by cases h
    shares := fun _ _ _ _ h => by cases h
    blocks := fun k bl hk => by
      rcases mixB_some hk with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      · refine ⟨rfl, rfl, fun p hp => ?_, .inl rfl, ?_, rfl⟩
        · cases hp; exact ⟨.int, fun u k' q ha => by cases ha⟩
        · exact ⟨fun _ _ => .inl rfl, fun h => (by cases h), fun h => (by cases h)⟩
      · refine ⟨rfl, rfl, fun p hp => ?_, .inl rfl, ?_, rfl⟩
        · cases hp
          refine ⟨.cell, fun u k' q ha => ?_⟩
          cases ha
          exact ⟨_, rfl⟩
        · exact ⟨fun _ _ => .inl rfl, fun h => (by cases h), fun h => (by cases h)⟩ }
  cover _ h := by cases h
  reach k bl h := by
    rcases mixB_some h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact .root ⟨0, rfl⟩ (.inl (.inl ⟨none, .refl _⟩))
    · exact .root ⟨1, rfl⟩ (.inl (.inl ⟨none, .refl _⟩))
  codes k bl h := by
    rcases mixB_some h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
      exact ⟨fun _ _ _ _ _ hs => (by cases hs), fun _ _ _ _ _ hs => (by cases hs)⟩
  dtors := DeadCodes.of_none fun k bl h => by rcases mixB_some h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> rfl
  cells k k1 k2 h1 h2 := by
    obtain ⟨t1, p1, hb1, hs1⟩ := h1
    obtain ⟨t2, p2, hb2, hs2⟩ := h2
    rcases mixB_some hb1 with ⟨rfl, he⟩ | ⟨rfl, he⟩ <;> cases he <;> cases hs1
    rcases mixB_some hb2 with ⟨rfl, he⟩ | ⟨rfl, he⟩ <;> cases he <;> cases hs2
    exact ⟨rfl, by decide⟩

/-- ... and its start names key 0 by both kinds. -/
theorem mix_not_shareKind (s : Stmt) (nv : Nat) : ¬ ShareKind (Cfg.start mixG s nv) := fun h =>
  h 0 (.inr (.inr ⟨0, _, rfl, .refl _⟩)) (.inr (.inl ⟨1, _, _, _, rfl, .refl _⟩))

/-- ... so `GlobsOK` refuses it: every start it admits keeps the kinds apart
    (`reach_shareKind`, at the start itself). -/
theorem mix_not_globsOK (P : Prog) : ¬ GlobsOK P mixG := fun hG =>
  mix_not_shareKind .skip 0 (reach_shareKind (spawn := fun _ => false) hG .refl)

end A3
