import A3.Mark
import A3.Fresh
import A3.SpawnOld

/-! A3 — Agora #805: **every share names a key below `nid`**.

A block's key is taken from `nid` (`arc_new`, `locked_new`, a cell's
constructor, `rw_read`, a closed channel's send), which then moves past it,
and every other share is a copy of one that was there before.  So every
share a value of the configuration holds — in any thread's slot, in a live
or dead binding alike, in a block's payload or in a module global — names a
key below `nid` (`CKeys`, kept by every configuration step: `Reach.keys`).
A2's invariant says as much of the shares it types (an owned tree's,
`MInv.shares`; a live borrow's, `ValOK`), but nothing of a dead borrow's
slot, which still holds what it held: this is the fact for every value.

Its use: the block a step makes at the key `nid` is named by no share but
the ones the step itself makes (none, for a closed channel's send), so the
marking sweep that ends the step finds nothing that refers to it
(`A3.TStep.closed_send_reaps`, `A3.TStep.closed_send_reaps_assign`;
at the witness, `A3.chanClosed_reaps`). -/

namespace A3
open A2

/-- Every share `v` holds (outside a carried `arc` payload, which is ghost
    data: the block's own payload is the one that counts) names a key below
    `n`. -/
inductive KB (n : Nat) : Val → Prop
  | int {j : Nat} : KB n (.int j)
  | href {c : Nat} : KB n (.href c)
  | view {d o l : Nat} : KB n (.view d o l)
  | node {t : Ty} {c d : Nat} {es : List Val} : (∀ e ∈ es, KB n e) → KB n (.node t c d es)
  | pair {v w : Val} : KB n v → KB n w → KB n (.pair v w)
  | inl {v : Val} : KB n v → KB n (.inl v)
  | inr {v : Val} : KB n v → KB n (.inr v)
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {v : Val} {cs : List (Var × PMode × Ty)} :
      KB n v → KB n (.pkg fs te ms v cs)
  | arc {k : Nat} {p : Val} : k < n → KB n (.arc k p)
  | lk {k : Nat} : k < n → KB n (.lk k)
  | cell {k : Nat} : k < n → KB n (.cell k)

namespace KB

theorem mono {n n' : Nat} (hn : n ≤ n') {v : Val} (h : KB n v) : KB n' v := by
  induction h with
  | int => exact .int
  | href => exact .href
  | view => exact .view
  | node _ ih => exact .node ih
  | pair _ _ ih1 ih2 => exact .pair ih1 ih2
  | inl _ ih => exact .inl ih
  | inr _ ih => exact .inr ih
  | pkg _ ih => exact .pkg ih
  | arc h => exact .arc (Nat.lt_of_lt_of_le h hn)
  | lk h => exact .lk (Nat.lt_of_lt_of_le h hn)
  | cell h => exact .cell (Nat.lt_of_lt_of_le h hn)

/-- What a value holds, it holds below the same bound. -/
theorem sub {n : Nat} {w v : Val} (hs : Sub w v) (h : KB n v) : KB n w := by
  induction hs with
  | refl => exact h
  | child he _ ih => cases h with | node hes => exact ih (hes _ he)
  | fst _ ih => cases h with | pair h1 _ => exact ih h1
  | snd _ ih => cases h with | pair _ h2 => exact ih h2
  | inl _ ih => cases h with | inl h1 => exact ih h1
  | inr _ ih => cases h with | inr h1 => exact ih h1
  | pkg _ ih => cases h with | pkg h1 => exact ih h1

/-- **A share a value holds names a key below the bound.** -/
theorem share {n : Nat} {v : Val} (h : KB n v) {k : Nat} (hs : ShareIn k v) : k < n := by
  rcases hs with ⟨p, hp⟩ | hc
  · cases p with
    | some p => have h1 := h.sub hp; cases h1 with | arc h => exact h
    | none => have h1 := h.sub hp; cases h1 with | lk h => exact h
  · have h1 := h.sub hc; cases h1 with | cell h => exact h

theorem lendOf {n : Nat} {v : Val} (h : KB n v) : KB n (A2.lendOf v) := by
  induction h with
  | node _ _ => exact .href
  | pair _ _ ih1 ih2 => exact .pair ih1 ih2
  | inl _ ih => exact .inl ih
  | inr _ ih => exact .inr ih
  | pkg _ ih => exact .pkg ih
  | int => exact .int
  | href => exact .href
  | view => exact .view
  | arc h => exact .arc h
  | lk h => exact .lk h
  | cell h => exact .cell h

/-- A tree with one of its parts replaced by one below the bound. -/
theorem repl {n : Nat} {a b T T' : Val} (hr : Repl a b T T') (hT : KB n T) (hb : KB n b) : KB n T' := by
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

/-- A node whose elements all come from another's, or are one more value. -/
theorem node_of {n : Nat} {t t' : Ty} {c d c' d' : Nat} {es es' : List Val} (h : KB n (.node t c d es))
    {v : Val} (hv : KB n v) (hsub : ∀ e ∈ es', e ∈ es ∨ e = v) : KB n (.node t' c' d' es') := by
  cases h with
  | node hes =>
    refine .node fun e he => ?_
    rcases hsub e he with h | rfl
    · exact hes e h
    · exact hv

theorem node_elem {n : Nat} {t : Ty} {c d : Nat} {es : List Val} (h : KB n (.node t c d es)) {e : Val}
    (he : e ∈ es) : KB n e := by
  cases h with | node hes => exact hes e he

end KB

/-! ### A store's shares -/

/-- Every share in a store's slots, its blocks' payloads and its globals
    names a key below its `nid`. -/
structure MKeys (m : Mem) : Prop where
  st  : ∀ x o v, m.st x = some ⟨o, some v⟩ → KB m.nid v
  blk : ∀ k t kd v, m.blk k = some ⟨t, kd, some v⟩ → KB m.nid v
  gl  : ∀ g v, m.gl g = some v → KB m.nid v

namespace MKeys

theorem of_eq {m m' : Mem} (h : MKeys m) (hst : m'.st = m.st) (hb : m'.blk = m.blk) (hg : m'.gl = m.gl)
    (hn : m.nid ≤ m'.nid) : MKeys m' :=
  ⟨fun x o v hx => (h.st x o v (by rw [← hst]; exact hx)).mono hn,
   fun k t kd v hk => (h.blk k t kd v (by rw [← hb]; exact hk)).mono hn,
   fun g v hg' => (h.gl g v (by rw [← hg]; exact hg')).mono hn⟩

theorem set {m : Mem} (h : MKeys m) (x : Var) {o : Bool} {w : Option Val}
    (hw : ∀ v, w = some v → KB m.nid v) : MKeys (m.set x ⟨o, w⟩) := by
  refine ⟨fun y o' v hy => ?_, h.blk, h.gl⟩
  simp only [Mem.set, upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy; exact hw v rfl
  · rw [ite_eq_right hyx] at hy; exact h.st y o' v hy

theorem withAlloc {m : Mem} (h : MKeys m) (a : Nat → Bool) : MKeys { m with alloc := a } :=
  ⟨h.st, h.blk, h.gl⟩

theorem withAN {m : Mem} (h : MKeys m) (a : Nat → Bool) {n : Nat} (hn : m.nid ≤ n) :
    MKeys { m with alloc := a, nid := n } :=
  ⟨fun x o v hx => (h.st x o v hx).mono hn, fun k t kd v hk => (h.blk k t kd v hk).mono hn,
   fun g v hg => (h.gl g v hg).mono hn⟩

theorem withNv {m : Mem} (h : MKeys m) (n : Nat) : MKeys { m with nv := n } := ⟨h.st, h.blk, h.gl⟩

/-- Agora #810: which blocks are taken holds no share. -/
theorem withTaken {m : Mem} (h : MKeys m) (T : Nat → Bool) : MKeys { m with taken := T } := ⟨h.st, h.blk, h.gl⟩

theorem remove {m : Mem} (h : MKeys m) (x : Var) : MKeys (m.remove x) := by
  refine ⟨fun y o' v hy => ?_, h.blk, h.gl⟩
  simp only [Mem.remove, upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy
  · rw [ite_eq_right hyx] at hy; exact h.st y o' v hy

theorem updBlk {m : Mem} (h : MKeys m) (k : Nat) {t : Ty} {kd : BKind} {w : Option Val}
    (hw : ∀ v, w = some v → KB m.nid v) : MKeys { m with blk := upd m.blk k (some ⟨t, kd, w⟩) } := by
  refine ⟨h.st, fun k' t' kd' v hk => ?_, h.gl⟩
  simp only [upd] at hk
  by_cases he : k' = k
  · rw [ite_eq_left he] at hk; cases hk; exact hw v rfl
  · rw [ite_eq_right he] at hk; exact h.blk k' t' kd' v hk

theorem rd {m : Mem} (h : MKeys m) {k : Nat} {bl : Blk} (hk : m.blk k = some bl) : KB m.nid bl.rd := by
  obtain ⟨t, kd, pay⟩ := bl
  cases pay with
  | none => cases kd <;> exact .int
  | some v =>
    have hv := h.blk k t kd v hk
    cases kd <;> first | exact hv | exact .int

theorem nodeAt {m : Mem} (h : MKeys m) {c : Nat} {n : Val} (hn : NodeAt m c n) : KB m.nid n := by
  rcases hn with ⟨x, T, hT, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.st x true T hT).sub hs
  · exact (h.rd hk).sub hs

theorem dataAt {m : Mem} (h : MKeys m) {d : Nat} {n : Val} (hn : DataAt m d n) : KB m.nid n := by
  rcases hn with ⟨x, T, hT, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
  · exact (h.st x true T hT).sub hs
  · exact (h.rd hk).sub hs

theorem vecOf {m : Mem} (h : MKeys m) {x : Var} {t : Ty} {c d : Nat} {es : List Val}
    (hv : VecOf m x t c d es) : KB m.nid (.node t c d es) := by
  rcases hv.2.2 with hx | ⟨_, hn⟩
  · exact h.st x true _ hx
  · exact h.nodeAt hn

theorem nodeOf {m : Mem} (h : MKeys m) {x o : Var} {T : Val} {t : Ty} {c d : Nat} {es : List Val}
    (hno : NodeOf m x o T t c d es) : KB m.nid T ∧ KB m.nid (.node t c d es) := by
  obtain ⟨_, _, ho, hxo⟩ := hno
  have hT := h.st _ _ _ ho
  refine ⟨hT, ?_⟩
  rcases hxo with ⟨_, rfl⟩ | ⟨_, hs⟩
  · exact hT
  · exact hT.sub hs

theorem takeVal {m m1 : Mem} (h : MKeys m) {y : Var} {v : Val} (ht : TakeVal m y v m1) :
    MKeys m1 ∧ KB m.nid v ∧ m1.nid = m.nid ∧ m1.blk = m.blk := by
  cases ht with
  | own hy => exact ⟨h.set y (fun _ h => by cases h), h.st y true v hy, rfl, rfl⟩
  | bor hy _ => exact ⟨h, h.st y false v hy, rfl, rfl⟩

end MKeys

/-- **A right-hand side keeps the store's shares below `nid`**, and its value's. -/
theorem EvalR.keys {m m' : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m')) (hk : MKeys m) :
    MKeys m' ∧ KB m'.nid v := by
  have hn : m.nid ≤ m'.nid := (EvalR.grows h).nid
  cases h with
  | expr _ => exact ⟨hk, .int⟩
  | new =>
    exact ⟨hk.of_eq rfl rfl rfl (by show m.nid ≤ m.nid + 2; omega), .node fun _ h => by cases h⟩
  | moveOwn hy => exact ⟨hk.set _ (fun _ h => by cases h), hk.st _ _ _ hy⟩
  | copy hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | borrowOwn _ => exact ⟨hk, .href⟩
  | borrowBor hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | «at» h hv _ => exact ⟨hk, ((hk.vecOf hv).node_elem (List.getElem_mem h)).lendOf⟩
  | view _ => exact ⟨hk, .view⟩
  | sat h _ _ _ _ hd => exact ⟨hk, ((hk.dataAt hd).node_elem (List.getElem_mem h)).lendOf⟩
  | pop hy _ _ =>
    have hT := hk.st _ _ _ hy
    refine ⟨hk.set _ (fun w hw => ?_), hT.node_elem (by simp)⟩
    cases hw; exact hT.node_of (KB.int (j := 0)) (fun e he => .inl (by simp [he]))
  | remove h hy _ _ _ =>
    have hT := hk.st _ _ _ hy
    refine ⟨hk.set _ (fun w hw => ?_), hT.node_elem (List.getElem_mem h)⟩
    cases hw; exact hT.node_of (KB.int (j := 0)) (fun e he => .inl (List.mem_of_mem_eraseIdx he))
  | pair h1 h2 =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1
    obtain ⟨hk2, hv2, hn2, _⟩ := hk1.takeVal h2
    exact ⟨hk2, .pair (by rw [hn2, hn1]; exact hv1) (by rw [hn2]; exact hv2)⟩
  | fst hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | pair h1 _ => exact ⟨hk, h1.lendOf⟩
  | snd hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | pair _ h2 => exact ⟨hk, h2.lendOf⟩
  | inl h1 => obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1; exact ⟨hk1, .inl (by rw [hn1]; exact hv1)⟩
  | inr h1 => obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1; exact ⟨hk1, .inr (by rw [hn1]; exact hv1)⟩
  | getl hy => have hT := hk.st _ _ _ hy; cases hT with | inl h1 => exact ⟨hk, h1.lendOf⟩
  | getr hy => have hT := hk.st _ _ _ hy; cases hT with | inr h1 => exact ⟨hk, h1.lendOf⟩
  | takel hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | inl h1 => exact ⟨hk.set _ (fun _ h => by cases h), h1⟩
  | taker hy =>
    have hT := hk.st _ _ _ hy
    cases hT with | inr h1 => exact ⟨hk.set _ (fun _ h => by cases h), h1⟩
  | pack h1 => obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1; exact ⟨hk1, .pkg (by rw [hn1]; exact hv1)⟩
  | arcNew h1 _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1
    refine ⟨?_, .arc (by show _ < _ + 1; omega)⟩
    exact (hk1.updBlk _ (fun w hw => by cases hw; rw [hn1]; exact hv1)).of_eq rfl rfl rfl (Nat.le_succ _)
  | arcClone hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | arcGet _ hb => exact ⟨hk, (hk.rd hb).lendOf⟩
  | lockNew h1 _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1
    refine ⟨?_, .lk (by show _ < _ + 1; omega)⟩
    exact (hk1.updBlk _ (fun w hw => by cases hw; rw [hn1]; exact hv1)).of_eq rfl rfl rfl (Nat.le_succ _)
  | lockClone hy => exact ⟨hk, hk.st _ _ _ hy⟩
  | cellNew h1 _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1
    refine ⟨?_, .cell (by show _ < _ + 1; omega)⟩
    exact (hk1.updBlk _ (fun w hw => by cases hw; rw [hn1]; exact hv1)).of_eq rfl rfl rfl (Nat.le_succ _)
  | cellClone hy _ => exact ⟨hk, hk.st _ _ _ hy⟩
  | atomic _ _ _ _ _ => exact ⟨hk.updBlk _ (fun w hw => by cases hw; exact .int), .int⟩
  | chanSend _ h1 hb _ _ _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1
    refine ⟨hk1.updBlk _ (fun w hw => ?_), .int⟩
    cases hw
    have hq := hk1.blk _ _ _ _ hb
    cases hq with
    | pair hq1 _ =>
      exact .pair (hq1.node_of (by rw [hn1]; exact hv1) (fun e he => by
        simp only [List.mem_append, List.mem_singleton] at he; exact he)) .int
  | chanSendClosed _ h1 _ _ _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1
    refine ⟨?_, .int⟩
    exact (hk1.updBlk _ (fun w hw => by cases hw; rw [hn1]; exact hv1)).of_eq rfl rfl rfl (Nat.le_succ _)
  | chanRecv _ hb _ _ _ _ =>
    have hq := hk.blk _ _ _ _ hb
    cases hq with
    | pair hq1 _ =>
      refine ⟨hk.updBlk _ (fun w hw => ?_), .inr (hq1.node_elem (by simp))⟩
      cases hw; exact .pair (hq1.node_of (KB.int (j := 0)) (fun e he => .inl (by simp [he]))) .int
  | chanRecvNone _ _ _ _ => exact ⟨hk, .inl .int⟩
  | chanClose _ hb _ =>
    have hq := hk.blk _ _ _ _ hb
    cases hq with
    | pair hq1 _ => exact ⟨hk.updBlk _ (fun w hw => by cases hw; exact .pair hq1 .int), .int⟩
  | rwRead ha hb _ =>
    have hl := hk.st _ _ _ ha
    have hp := hk.blk _ _ _ _ hb
    cases hl with
    | lk hlt =>
      refine ⟨?_, .arc (by show _ < _ + 1; omega)⟩
      exact (hk.updBlk _ (fun w hw => by cases hw; exact .pair (.lk hlt) hp)).of_eq rfl rfl rfl
        (Nat.le_succ _)
  | rwTryRead ha hb _ =>
    have hl := hk.st _ _ _ ha
    have hp := hk.blk _ _ _ _ hb
    cases hl with
    | lk hlt =>
      refine ⟨?_, .inr (.arc (by show _ < _ + 1; omega))⟩
      exact (hk.updBlk _ (fun w hw => by cases hw; exact .pair (.lk hlt) hp)).of_eq rfl rfl rfl
        (Nat.le_succ _)
  | rwTryReadNone _ _ => exact ⟨hk, .inl .int⟩
  | rwTryWrite _ _ _ => exact ⟨hk, .inr .int⟩
  | rwTryWriteNone _ _ => exact ⟨hk, .inl .int⟩
  | glob hg _ => exact ⟨hk, hk.gl _ _ hg⟩
  | lockTake _ hb _ =>
    exact ⟨(hk.updBlk _ (fun _ h => by cases h)).withTaken _, hk.blk _ _ _ _ hb⟩
  | lockRestore _ h1 _ _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal h1
    exact ⟨hk1.updBlk _ (fun w hw => by cases hw; rw [hn1]; exact hv1), .int⟩

theorem BindParams.keys {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (hk : MKeys m) : MKeys m' := by
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

theorem Release.keys {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') (hk : MKeys m) :
    MKeys m' := by
  cases h with
  | put hx _ _ _ => exact (hk.updBlk _ (fun w hw => by cases hw; exact hk.st _ _ _ hx)).remove x
  | drop _ _ _ => exact (hk.withAlloc _).remove x

/-- **A step keeps the store's shares below `nid`**, to a configuration or a
    panic. -/
theorem Step.keys {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hk : MKeys m) : MKeys r.mem := by
  induction h with
  | seqSkip => exact hk
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he =>
    obtain ⟨h1, h2⟩ := EvalR.keys he hk
    exact h1.set _ (fun w hw => by cases hw; exact h2)
  | letvP _ => exact hk
  | letcall _ _ hb =>
    have h1 := BindParams.keys hb hk
    exact ((h1.set _ (fun _ h => by cases h)).set _ (fun _ h => by cases h)).of_eq rfl rfl rfl (Nat.le_refl _)
  | scopeSkip _ _ => exact (hk.withAlloc _).remove _
  | scopeIn _ ih => exact ih
  | scopeP _ _ _ ih => exact (ih.withAlloc _).remove _
  | rbindSkip _ => exact hk.remove _
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact (ih).remove _
  | frozenSkip => exact hk
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ _ =>
    obtain ⟨h1, h2⟩ := EvalR.keys he hk
    exact (h1.withAlloc _).set _ (fun w hw => by cases hw; exact h2)
  | assignP _ => exact hk
  | iteT _ _ => exact hk
  | iteF _ => exact hk
  | «while» => exact hk
  | push ht hx _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal ht
    refine hk1.set _ (fun w hw => ?_)
    cases hw
    exact (hk1.st _ _ _ hx).node_of (by rw [hn1]; exact hv1) (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he)
  | pushRealloc ht hx _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal ht
    refine (hk1.withAN _ (Nat.le_succ _)).set _ (fun w hw => ?_)
    cases hw
    exact ((hk1.st _ _ _ hx).node_of (by rw [hn1]; exact hv1) (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he)).mono (Nat.le_succ _)
  | editPush ht hno hr =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal ht
    obtain ⟨hT, hN⟩ := hk1.nodeOf hno
    refine hk1.set _ (fun w hw => ?_)
    cases hw
    exact hT.repl hr (hN.node_of (by rw [hn1]; exact hv1) (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he))
  | editPushRealloc ht hno hr =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal ht
    obtain ⟨hT, hN⟩ := hk1.nodeOf hno
    refine (hk1.withAN _ (Nat.le_succ _)).set _ (fun w hw => ?_)
    cases hw
    exact (hT.repl hr (hN.node_of (by rw [hn1]; exact hv1) (fun e he => by
      simp only [List.mem_append, List.mem_singleton] at he; exact he))).mono (Nat.le_succ _)
  | editTrunc _ hno _ hr =>
    obtain ⟨hT, hN⟩ := hk.nodeOf hno
    refine (hk.withAlloc _).set _ (fun w hw => ?_)
    cases hw
    exact hT.repl hr (hN.node_of (KB.int (j := 0)) (fun e he => .inl (List.mem_of_mem_take he)))
  | editSet _ _ ht hno _ hr =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal ht
    obtain ⟨hT, hN⟩ := hk1.nodeOf hno
    refine (hk1.withAlloc _).set _ (fun w hw => ?_)
    cases hw
    exact hT.repl hr (hN.node_of (by rw [hn1]; exact hv1) (fun e he => by
      rcases List.mem_or_eq_of_mem_set he with h | h
      · exact .inl h
      · exact .inr h))
  | editSetOOB _ ht _ _ _ =>
    obtain ⟨hk1, _, _, _⟩ := hk.takeVal ht
    exact hk1.withAlloc _
  | insert _ ht hx _ _ =>
    obtain ⟨hk1, hv1, hn1, _⟩ := hk.takeVal ht
    refine hk1.set _ (fun w hw => ?_)
    cases hw
    exact (hk1.st _ _ _ hx).node_of (by rw [hn1]; exact hv1) (fun e he => by
      simp only [List.mem_append, List.mem_cons] at he
      rcases he with h | h | h
      · exact .inl (List.mem_of_mem_take h)
      · exact .inr h
      · exact .inl (List.mem_of_mem_drop h))
  | withElem h hv _ _ _ _ =>
    have hT := hk.st _ _ _ hv
    refine (hk.set _ (fun w hw => ?_)).set _ (fun w hw => ?_)
    · cases hw
      exact hT.node_of (KB.int (j := 0)) (fun e he => by
        simp only [List.mem_append] at he
        rcases he with h | h
        · exact .inl (List.mem_of_mem_take h)
        · exact .inl (List.mem_of_mem_drop h))
    · cases hw; exact hT.node_elem (List.getElem_mem h)
  | withElemOOB _ _ _ _ => exact hk
  | free _ _ => exact (hk.withAlloc _).set _ (fun _ h => by cases h)
  | panic => exact hk
  | waitPanic _ => exact hk
  | letrec _ _ _ =>
    exact ((hk.set _ (fun _ h => by cases h)).set _ (fun _ h => by cases h)).of_eq rfl rfl rfl (Nat.le_refl _)
  | catchIn _ ih => exact ih
  | catchSkip => exact hk
  | unpair hy _ _ _ =>
    have hT := hk.st _ _ _ hy
    cases hT with
    | pair h1 h2 =>
      exact (((hk.set _ (fun _ h => by cases h)).set _ (fun w hw => by cases hw; exact h1)).set _
        (fun w hw => by cases hw; exact h2))
  | callc hc _ _ _ hb =>
    have hT := hk.st _ _ _ hc
    cases hT with
    | pkg he =>
      have h0 : MKeys (envMem _ _) :=
        (hk.set _ (fun w hw => by cases hw; exact he.lendOf)).of_eq rfl rfl rfl (Nat.le_refl _)
      have h1 := BindParams.keys hb h0
      exact ((h1.set _ (fun _ h => by cases h)).set _ (fun _ h => by cases h)).of_eq rfl rfl rfl (Nat.le_refl _)
  | callcE hc _ _ _ _ =>
    have hT := hk.st _ _ _ hc
    cases hT with
    | pkg he =>
      exact (((hk.set _ (fun _ h => by cases h)).set _ (fun w hw => by cases hw; exact he)).set _
        (fun _ h => by cases h)).of_eq rfl rfl rfl (Nat.le_refl _)
  | callcD hc _ _ _ _ =>
    have hT := hk.st _ _ _ hc
    cases hT with
    | pkg he =>
      exact (((hk.set _ (fun _ h => by cases h)).set _ (fun w hw => by cases hw; exact he)).set _
        (fun _ h => by cases h)).of_eq rfl rfl rfl (Nat.le_refl _)
  | catchP _ _ ih => exact (ih).set _ (fun w hw => by cases hw; exact .int)
  | letd _ he =>
    obtain ⟨h1, h2⟩ := EvalR.keys he hk
    exact h1.set _ (fun w hw => by cases hw; exact h2)
  | letdP _ => exact hk
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ _ => exact hk.of_eq rfl rfl rfl (Nat.le_refl _)
  | scopeDMoved _ => exact hk.remove _
  | scopeDDrain _ => exact hk.of_eq rfl rfl rfl (Nat.le_refl _)
  | scopeDEmpty _ => exact hk
  | scopeDP _ _ _ ih => exact ih
  | scopeDPDrain _ _ ih | scopeLPD _ _ _ _ _ ih => exact ih
  | scopeDPMoved _ _ ih => exact (ih).remove _
  | withLock _ hb _ _ =>
    exact ((hk.updBlk _ (fun _ h => by cases h)).withTaken _).set _ (fun w hw => by cases hw; exact hk.blk _ _ _ _ hb)
  | scopeLIn _ ih => exact ih
  | scopeLSkip hrl _ => exact Release.keys hrl hk
  | scopeLFail _ _ => exact hk
  | scopeLP _ hrl ih => exact Release.keys hrl ih
  | reap _ hb _ =>
    have hp := hk.blk _ _ _ _ hb
    exact ((hk.set _ (fun w hw => by cases hw; exact hp)).updBlk _ (fun _ h => by cases h)).of_eq
      rfl rfl rfl (Nat.le_refl _)

/-! ### A typed store's shares

What A2's invariant says of the shares a typed tree holds (each names a
block, `SharesIn`), for the start: every block's key is below `nid`. -/

/-- A tree of a type that holds no share holds none. -/
theorem KB.of_noArc {n : Nat} {τ : Ty} {T : Val} (hw : WFv τ T) (ha : τ.hasArc = false) : KB n T := by
  induction hw with
  | int => exact .int
  | view => exact .view
  | node _ ih => exact .node fun e he => ih e he ha
  | pair _ _ ih1 ih2 =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at ha; exact .pair (ih1 ha.1) (ih2 ha.2)
  | inl _ ih => simp only [Ty.hasArc, Bool.or_eq_false_iff] at ha; exact .inl (ih ha.1)
  | inr _ ih => simp only [Ty.hasArc, Bool.or_eq_false_iff] at ha; exact .inr (ih ha.2)
  | pkg _ hq ih => exact .pkg (ih (hq.2.2.1 ha))
  | arc => cases ha
  | rguard => cases ha
  | lk => cases ha
  | cell => cases ha
  | dtor _ _ ih => exact ih ha

/-- **A typed tree's shares name blocks**, so keys below `n` when every
    block's is. -/
theorem KB.of_wfv {B : Nat → Option Blk} {n : Nat} (hB : ∀ k bl, B k = some bl → k < n) {τ : Ty} {T : Val}
    (hw : WFv τ T) (hs : SharesIn B τ T) : KB n T := by
  induction hw with
  | int => exact .int
  | view => exact .view
  | node _ ih => exact .node fun e he => ih e he (fun u k p h => hs u k p (.child he h))
  | pair _ _ ih1 ih2 => exact .pair (ih1 fun u k p h => hs u k p (.fst h)) (ih2 fun u k p h => hs u k p (.snd h))
  | inl _ ih => exact .inl (ih fun u k p h => hs u k p (.inl h))
  | inr _ ih => exact .inr (ih fun u k p h => hs u k p (.inr h))
  | @pkg fs te ms q v cs hv hq ih =>
    cases hqs : q.shares
    · exact .pkg (KB.of_noArc hv (hq.2.2.1 hqs))
    · exact .pkg (ih fun u k p h => hs u k p (.pkg h hqs))
  | arc =>
    obtain ⟨_, h, _⟩ := ArcBlk.rd (hs _ _ _ .here)
    exact .arc (hB _ _ h)
  | rguard =>
    obtain ⟨_, h, _⟩ := ArcBlk.rd (hs _ _ _ .rguard)
    exact .arc (hB _ _ h)
  | lk =>
    obtain ⟨o, h⟩ := hs _ _ _ .lk
    exact .lk (hB _ _ h)
  | cell =>
    obtain ⟨o, h⟩ := hs _ _ _ .cell
    exact .cell (hB _ _ h)
  | dtor _ _ ih => exact ih (SharesIn.dtor_iff.mp hs)

/-! ### A configuration's shares -/

/-- **Every share in the configuration names a key below `nid`**: in every
    thread's slots (live bindings and dead ones alike), in every block's
    payload, and in the module globals. -/
structure CKeys (C : Cfg) : Prop where
  ths : ∀ (j : Nat) (t : Thread), C.ths[j]? = some t → ∀ x o v, t.st x = some ⟨o, some v⟩ → KB C.nid v
  blk : ∀ k t kd v, C.blk k = some ⟨t, kd, some v⟩ → KB C.nid v
  gl  : ∀ g v, C.gl g = some v → KB C.nid v

namespace CKeys

theorem view {C : Cfg} (h : CKeys C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t) : MKeys (C.view t) :=
  ⟨h.ths i t hi, h.blk, h.gl⟩

/-- A root of the configuration names keys below `nid` only. -/
theorem root {C : Cfg} (h : CKeys C) {v : Val} (hv : C.roots v) : KB C.nid v := by
  rcases hv with ⟨j, t, hj, x, o, hx⟩ | ⟨g, hg⟩
  · exact h.ths j t hj x o v hx
  · exact h.gl g v hg

/-- A thread's step written back. -/
theorem put {C : Cfg} (h : CKeys C) {i : Nat} {m' : Mem} {s' : Stmt} (hm : MKeys m') (hn : C.nid ≤ m'.nid) :
    CKeys (C.put i m' s') := by
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
    exact (h.ths j t hj x o v hx).mono hn

/-- The marking sweep keeps it: it keeps or marks blocks, their payloads as
    they were. -/
theorem sweepD {C : Cfg} (h : CKeys C) : CKeys C.sweepD := by
  refine ⟨h.ths, fun k t kd v hk => ?_, h.gl⟩
  rcases sweepBlkD_some hk with ⟨hk0, _⟩ | ⟨bl0, hk0, _, _, he⟩
  · exact h.blk k t kd v hk0
  · obtain ⟨t0, kd0, p0⟩ := bl0
    simp only [Blk.mark, Blk.mk.injEq] at he
    obtain ⟨rfl, -, rfl⟩ := he
    exact h.blk k _ _ v hk0

/-- A thread's step, the marking sweep after it: the shares stay below `nid`. -/
theorem step {P : Prog} {C : Cfg} (h : CKeys C) {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt}
    (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) : CKeys (C.put i m' s').sweepD :=
  (h.put (Step.keys hst (h.view hi)) (Step.grows hst).nid).sweepD

end CKeys

theorem CSettle.keys {P : Prog} {i : Nat} {C C' : Cfg} (hse : CSettle P i C C') (h : CKeys C) : CKeys C' := by
  induction hse with
  | done _ => exact h
  | reap hi hs _ _ ih => exact ih (h.step hi hs)

theorem MoveArgs.keys {st st' : Var → Option Slot} {as : List Var} {vs : List Val} (hm : MoveArgs st as vs st')
    {n : Nat} (h : ∀ x o v, st x = some ⟨o, some v⟩ → KB n v) :
    (∀ x o v, st' x = some ⟨o, some v⟩ → KB n v) ∧ ∀ v ∈ vs, KB n v := by
  induction hm with
  | nil => exact ⟨h, fun _ h => by cases h⟩
  | @cons st st' a as v vs ha _ ih =>
    have h' : ∀ x o w, upd st a (some ⟨true, none⟩) x = some ⟨o, some w⟩ → KB n w := by
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

/-- **A configuration step keeps every share below `nid`**: a thread's step
    and its reaps, and a spawn (what it moves is the spawner's). -/
theorem TStep.keys {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (hs : TStep P spawn C C') (h : CKeys C) :
    CKeys C' := by
  cases hs with
  | thread hi _ hst hse => exact CSettle.keys hse (h.step hi hst)
  | @spawn i t K x f args k fn vs st' hi _ _ _ _ hm _ =>
    obtain ⟨h1, h2⟩ := MoveArgs.keys hm (h.ths i t hi)
    refine ⟨fun j t' hj y o v hy => ?_, h.blk, h.gl⟩
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
    refine ⟨fun j t' hj y o v hy => ?_, h.blk, h.gl⟩
    simp only at hj ⊢
    by_cases hji : i = j
    · subst hji
      have hlt : _ < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
      rw [List.getElem?_set_self hlt] at hj
      cases hj; exact h.ths _ _ hi y o v hy
    · rw [List.getElem?_set_ne hji] at hj
      exact h.ths j t' hj y o v hy

theorem Reach.keys {P : Prog} {spawn : Nat → Bool} {C C' : Cfg} (hr : Reach P spawn C C') (h : CKeys C) :
    CKeys C' := by
  induction hr with
  | refl => exact h
  | step hs _ ih => exact ih (TStep.keys hs h)

/-- **The start**: the globals' blocks are typed (`GlobsOK.inv`) and every
    global is a share of one of them (`GlobsOK.sync`). -/
theorem CKeys.start {P : Prog} {G : Globs} (hG : GlobsOK P G) (s : Stmt) (nv : Nat) :
    CKeys (Cfg.start G s nv) := by
  have hB : ∀ k bl, G.blk k = some bl → k < G.nid := fun k bl hk => (hG.blocksAt k bl hk).key
  refine ⟨fun j t hj x o v hx => ?_, fun k t kd v hk => ?_, fun g v hg => ?_⟩
  · simp only [Cfg.start] at hj
    cases j with
    | zero => simp at hj; subst hj; cases hx
    | succ _ => simp at hj
  · obtain ⟨_, _, hpay, _, _⟩ := hG.inv.blocks k _ hk
    obtain ⟨hw, hs⟩ := hpay v rfl
    exact KB.of_wfv hB hw hs
  · obtain ⟨_, _, _, hf⟩ := hG.sync g v hg
    rcases hf with ⟨u, k, o, _, rfl, hk⟩ | ⟨u, k, p, _, rfl, hk⟩
    · exact .lk (hB _ _ hk)
    · obtain ⟨_, hk, _⟩ := hk.rd
      exact .arc (hB _ _ hk)

/-- **On every configuration a typed start reaches, every share names a key
    below `nid`.** -/
theorem reach_keys {P : Prog} {spawn : Nat → Bool} {G : Globs} (hG : GlobsOK P G) {s : Stmt} {nv : Nat}
    {C : Cfg} (hr : Reach P spawn (Cfg.start G s nv) C) : CKeys C :=
  Reach.keys hr (CKeys.start hG s nv)

/-! ### A closed channel's send: the parked block is marked and reaped by the sender -/

/-- What refers to a lock block holds a share of it (no one reads a lock
    block's payload through a handle: `Blk.rd` is nothing). -/
theorem Refers.lock_share {B : Nat → Option Blk} {k : Nat} {t : Ty} {p : Option Val}
    (hk : B k = some ⟨t, .lock, p⟩) {w : Val} (h : Refers B w k) : ShareIn k w := by
  rcases h with h | ⟨bl, hb, h⟩
  · exact h
  · rw [hk] at hb; cases hb
    rcases h with ⟨c, _, hc⟩ | ⟨d, o, l, _, hc⟩ <;> simp [Blk.rd] at hc

/-- **Agora #805: a closed channel's send parks the value for the sender to
    reap**, whatever binds its answer (the core of `TStep.closed_send_reaps`
    and `TStep.closed_send_reaps_assign`).  Thread `i` evaluates `chan_send
    a y` on a closed channel (`a` shares the lock block `kc`, whose flag is
    set) whose elements are destructor values (`Ty.nest n (.dtor g u)`: a
    destructor value, or a drained `Vec` of them), and its step writes the
    answer to a slot `x`, the addresses `al` live (a `letv`'s fresh slot, or
    an `assign`'s, whose old integer's drop frees nothing).  The value taken
    from `y` goes into a fresh lock block at the key `C.nid`
    (`EvalR.chanSendClosed`), the answer is 0, and:

    - the configuration's marking sweep that ends the step marks that block
      `dead`, the value in it: no thread's slot, no global and no block's
      payload holds a share of it, since every share in the configuration
      names a key below `C.nid` (`CKeys`);
    - in the result `C'` of the step's reaps (`CSettle`, all thread `i`'s,
      before any other thread runs) a slot `w` of thread `i` at or above its
      `nv` before the step owns the value, and the block is emptied or gone
      (`TStep.last_drop_reaps`, over `CSettle.reaps_block`). -/
theorem closed_send_core {P : Prog} {C : Cfg} (hK : CKeys C) {i : Nat} {t : Thread} (hi : C.ths[i]? = some t)
    {a y : Var} {r : Val} {o : Bool} {m1 : Mem} (he : EvalR (C.view t) (.chanSend a y) (.ok r o m1))
    {o' : Bool} {kc : Nat} {τ : Ty} {q : Val} {f : Nat} (ha : t.st a = some ⟨o', some (.lk kc)⟩)
    (hc : C.blk kc = some ⟨τ, .lock, some (.pair q (.int (f + 1)))⟩)
    {n g : Nat} {u : Ty} (hs : τ.undtor = .prod (.vec (Ty.nest n (.dtor g u))) .int)
    {x : Var} {al : Nat → Bool} {s' : Stmt} {C' : Cfg}
    (hse : CSettle P i (C.put i { m1 with alloc := al, st := upd m1.st x (some ⟨o, some r⟩) } s').sweepD C') :
    r = .int 0 ∧ ∃ v m0, TakeVal (C.view t) y v m0 ∧
      (C.put i { m1 with alloc := al, st := upd m1.st x (some ⟨o, some r⟩) } s').sweepD.blk C.nid =
        some ⟨Ty.nest n (.dtor g u), .dead, some v⟩ ∧
      ∃ (t' : Thread) (w : Var), C'.ths[i]? = some t' ∧ t'.st w = some ⟨true, some v⟩ ∧ t.nv ≤ w ∧
        Emptied C'.blk C.nid (Ty.nest n (.dtor g u)) := by
  have hlen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hkv := hK.view hi
  cases he with
  | chanSend hv ht hk' _ _ _ _ =>
    change t.st a = _ at hv; rw [ha] at hv; cases hv
    rw [TakeVal.blk ht] at hk'; change C.blk kc = _ at hk'; rw [hc] at hk'; cases hk'
  | @chanSendClosed _ _ _ _ t0 s q0 f0 v m0 hv ht hk' hs' hfr _ =>
    change t.st a = _ at hv; rw [ha] at hv; cases hv
    rw [TakeVal.blk ht] at hk'; change C.blk kc = _ at hk'; rw [hc] at hk'; cases hk'
    rw [hs] at hs'
    simp only [Ty.prod.injEq, Ty.vec.injEq, and_true] at hs'
    subst hs'
    obtain ⟨hk0, hv0, hn0, hb0⟩ := hkv.takeVal ht
    have hnid : m0.nid = C.nid := hn0
    have hnv : m0.nv = t.nv := by cases ht <;> rfl
    -- the store after the step, and one of the same slots and globals with `nid` as it was
    let m1' : Mem :=
      { m0 with nid := m0.nid + 1, blk := upd m0.blk m0.nid (some ⟨Ty.nest n (.dtor g u), .lock, some v⟩) }
    let m' : Mem := { m1' with alloc := al, st := upd m1'.st x (some ⟨false, some (.int 0)⟩) }
    let m'' : Mem := m0.set x ⟨false, some (.int 0)⟩
    have hm'' : MKeys m'' := hk0.set x (fun w hw => by cases hw; exact .int)
    have hK'' : CKeys (C.put i m'' s') := hK.put hm'' (by show C.nid ≤ m0.nid; omega)
    have hblk : m'.blk = upd C.blk C.nid (some ⟨Ty.nest n (.dtor g u), .lock, some v⟩) := by
      show upd m0.blk m0.nid _ = _; rw [hb0, hnid]; rfl
    have hk : m'.blk C.nid = some ⟨Ty.nest n (.dtor g u), .lock, some v⟩ := by rw [hblk]; simp [upd]
    have hv' : ∀ w, (C.put i m' s').roots w → ¬ Refers m'.blk w C.nid := by
      intro w hw hr
      have hw' : (C.put i m'' s').roots w := hw
      have := (hK''.root hw').share (Refers.lock_share hk hr)
      simp [Cfg.put, m'', hnid] at this
    have hb : ∀ k' bl', m'.blk k' = some bl' → ¬ Refers m'.blk bl'.keeps C.nid := by
      intro k' bl' hk' hr
      have hsh := Refers.lock_share hk hr
      rw [hblk] at hk'
      simp only [upd] at hk'
      by_cases he : k' = C.nid
      · rw [ite_eq_left he] at hk'; cases hk'
        exact Nat.lt_irrefl _ (hv0.share hsh)
      · rw [ite_eq_right he] at hk'
        obtain ⟨t1, kd1, p1⟩ := bl'
        cases p1 with
        | none =>
          exact Nat.lt_irrefl _ ((KB.int (n := C.nid) (j := 0)).share hsh)
        | some p1 => exact Nat.lt_irrefl _ ((hK.blk _ _ _ _ hk').share hsh)
    obtain ⟨hm, t', w, h1, h2, h3, h4⟩ :=
      TStep.last_drop_reaps (P := P) (C := C) (i := i) (m' := m') hlen hse (Or.inr rfl) hk (CutOff.one hv' hb) rfl
    exact ⟨rfl, v, m0, ht, hm, t', w, h1, h2, by rw [← hnv]; exact h3, h4⟩

/-- **Agora #805: a closed channel's send bound by `letv x`** (`: r ( chan_send
    ch x )`): the step is a configuration step (`TStep.thread`, at no spawn
    redex), the answer is 0, the value taken from `y` sits in the block at
    `C.nid`, which the step's marking sweep marks `dead`, and in the step's
    result `C'` a slot `w` of thread `i` at or above its `nv` before the step
    (one its reaps made) owns the value, the block emptied or gone
    (`closed_send_core`).  (Which frame the reap put around the redex is
    `Step.reap`'s: `scopeD _ g`, whose end runs the destructor; this
    statement does not trace it.) -/
theorem TStep.closed_send_reaps {P : Prog} {spawn : Nat → Bool} {C : Cfg} (hK : CKeys C) {i : Nat}
    {t : Thread} {K : Stmt → Stmt} {x a y : Var} {k : Stmt} (hi : C.ths[i]? = some t)
    (hR : Redex t.s K (.letv x (.chanSend a y) k)) (hsp : ¬ SpawnRedex spawn t.s) (hx : t.st x = none)
    {r : Val} {o : Bool} {m1 : Mem} (he : EvalR (C.view t) (.chanSend a y) (.ok r o m1))
    {o' : Bool} {kc : Nat} {τ : Ty} {q : Val} {f : Nat} (ha : t.st a = some ⟨o', some (.lk kc)⟩)
    (hc : C.blk kc = some ⟨τ, .lock, some (.pair q (.int (f + 1)))⟩)
    {n g : Nat} {u : Ty} (hs : τ.undtor = .prod (.vec (Ty.nest n (.dtor g u))) .int)
    {C' : Cfg} (hse : CSettle P i (C.put i (m1.set x ⟨o, some r⟩) (K (.scope x k))).sweepD C') :
    TStep P spawn C C' ∧ r = .int 0 ∧ ∃ v m0, TakeVal (C.view t) y v m0 ∧
      (C.put i (m1.set x ⟨o, some r⟩) (K (.scope x k))).sweepD.blk C.nid =
        some ⟨Ty.nest n (.dtor g u), .dead, some v⟩ ∧
      ∃ (t' : Thread) (w : Var), C'.ths[i]? = some t' ∧ t'.st w = some ⟨true, some v⟩ ∧ t.nv ≤ w ∧
        Emptied C'.blk C.nid (Ty.nest n (.dtor g u)) := by
  have hst : Step P (C.view t) t.s (.ok (m1.set x ⟨o, some r⟩) (K (.scope x k))) := by
    rw [hR.eq]; exact hR.step (Step.letv hx he)
  exact ⟨.thread hi hsp hst hse, closed_send_core (al := m1.alloc) hK hi he ha hc hs hse⟩

/-- **... and bound by `assign z`** (`= r ( chan_send ch x )`): the same, the
    step an `Step.assign` whose old value's drop (`DropSlot`, to the
    addresses `al`) is part of the step. -/
theorem TStep.closed_send_reaps_assign {P : Prog} {spawn : Nat → Bool} {C : Cfg} (hK : CKeys C) {i : Nat}
    {t : Thread} {K : Stmt → Stmt} {z a y : Var} (hi : C.ths[i]? = some t)
    (hR : Redex t.s K (.assign z (.chanSend a y))) (hsp : ¬ SpawnRedex spawn t.s) (hz : (t.st z).isSome)
    {r : Val} {o : Bool} {m1 : Mem} (he : EvalR (C.view t) (.chanSend a y) (.ok r o m1))
    {sl : Slot} {al : Nat → Bool} (hsl : m1.st z = some sl) (hd : DropSlot m1.alloc sl al)
    {o' : Bool} {kc : Nat} {τ : Ty} {q : Val} {f : Nat} (ha : t.st a = some ⟨o', some (.lk kc)⟩)
    (hc : C.blk kc = some ⟨τ, .lock, some (.pair q (.int (f + 1)))⟩)
    {n g : Nat} {u : Ty} (hs : τ.undtor = .prod (.vec (Ty.nest n (.dtor g u))) .int)
    {C' : Cfg} (hse : CSettle P i (C.put i ({ m1 with alloc := al }.set z ⟨o, some r⟩) (K .skip)).sweepD C') :
    TStep P spawn C C' ∧ r = .int 0 ∧ ∃ v m0, TakeVal (C.view t) y v m0 ∧
      (C.put i ({ m1 with alloc := al }.set z ⟨o, some r⟩) (K .skip)).sweepD.blk C.nid =
        some ⟨Ty.nest n (.dtor g u), .dead, some v⟩ ∧
      ∃ (t' : Thread) (w : Var), C'.ths[i]? = some t' ∧ t'.st w = some ⟨true, some v⟩ ∧ t.nv ≤ w ∧
        Emptied C'.blk C.nid (Ty.nest n (.dtor g u)) := by
  have hst : Step P (C.view t) t.s (.ok ({ m1 with alloc := al }.set z ⟨o, some r⟩) (K .skip)) := by
    rw [hR.eq]; exact hR.step (Step.assign hz he hsl hd)
  exact ⟨.thread hi hsp hst hse, closed_send_core hK hi he ha hc hs hse⟩

/-- ... on every configuration a start with typed globals reaches
    (`reach_keys`). -/
theorem reach_closed_send_reaps {P : Prog} {spawn : Nat → Bool} {G : Globs} (hG : GlobsOK P G) {s0 : Stmt}
    {nv : Nat} {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C) {i : Nat}
    {t : Thread} {K : Stmt → Stmt} {x a y : Var} {k : Stmt} (hi : C.ths[i]? = some t)
    (hR : Redex t.s K (.letv x (.chanSend a y) k)) (hsp : ¬ SpawnRedex spawn t.s) (hx : t.st x = none)
    {r : Val} {o : Bool} {m1 : Mem} (he : EvalR (C.view t) (.chanSend a y) (.ok r o m1))
    {o' : Bool} {kc : Nat} {τ : Ty} {q : Val} {f : Nat} (ha : t.st a = some ⟨o', some (.lk kc)⟩)
    (hc : C.blk kc = some ⟨τ, .lock, some (.pair q (.int (f + 1)))⟩)
    {n g : Nat} {u : Ty} (hs : τ.undtor = .prod (.vec (Ty.nest n (.dtor g u))) .int)
    {C' : Cfg} (hse : CSettle P i (C.put i (m1.set x ⟨o, some r⟩) (K (.scope x k))).sweepD C') :
    TStep P spawn C C' ∧ r = .int 0 ∧ ∃ v m0, TakeVal (C.view t) y v m0 ∧
      (C.put i (m1.set x ⟨o, some r⟩) (K (.scope x k))).sweepD.blk C.nid =
        some ⟨Ty.nest n (.dtor g u), .dead, some v⟩ ∧
      ∃ (t' : Thread) (w : Var), C'.ths[i]? = some t' ∧ t'.st w = some ⟨true, some v⟩ ∧ t.nv ≤ w ∧
        Emptied C'.blk C.nid (Ty.nest n (.dtor g u)) :=
  TStep.closed_send_reaps (reach_keys hG hr) hi hR hsp hx he ha hc hs hse

/-- ... and the `assign`-bound send there. -/
theorem reach_closed_send_reaps_assign {P : Prog} {spawn : Nat → Bool} {G : Globs} (hG : GlobsOK P G)
    {s0 : Stmt} {nv : Nat} {C : Cfg} (hr : Reach P spawn (Cfg.start G s0 nv) C) {i : Nat}
    {t : Thread} {K : Stmt → Stmt} {z a y : Var} (hi : C.ths[i]? = some t)
    (hR : Redex t.s K (.assign z (.chanSend a y))) (hsp : ¬ SpawnRedex spawn t.s) (hz : (t.st z).isSome)
    {r : Val} {o : Bool} {m1 : Mem} (he : EvalR (C.view t) (.chanSend a y) (.ok r o m1))
    {sl : Slot} {al : Nat → Bool} (hsl : m1.st z = some sl) (hd : DropSlot m1.alloc sl al)
    {o' : Bool} {kc : Nat} {τ : Ty} {q : Val} {f : Nat} (ha : t.st a = some ⟨o', some (.lk kc)⟩)
    (hc : C.blk kc = some ⟨τ, .lock, some (.pair q (.int (f + 1)))⟩)
    {n g : Nat} {u : Ty} (hs : τ.undtor = .prod (.vec (Ty.nest n (.dtor g u))) .int)
    {C' : Cfg} (hse : CSettle P i (C.put i ({ m1 with alloc := al }.set z ⟨o, some r⟩) (K .skip)).sweepD C') :
    TStep P spawn C C' ∧ r = .int 0 ∧ ∃ v m0, TakeVal (C.view t) y v m0 ∧
      (C.put i ({ m1 with alloc := al }.set z ⟨o, some r⟩) (K .skip)).sweepD.blk C.nid =
        some ⟨Ty.nest n (.dtor g u), .dead, some v⟩ ∧
      ∃ (t' : Thread) (w : Var), C'.ths[i]? = some t' ∧ t'.st w = some ⟨true, some v⟩ ∧ t.nv ≤ w ∧
        Emptied C'.blk C.nid (Ty.nest n (.dtor g u)) :=
  TStep.closed_send_reaps_assign (reach_keys hG hr) hi hR hsp hz he hsl hd ha hc hs hse

end A3
