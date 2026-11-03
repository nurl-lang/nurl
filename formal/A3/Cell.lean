import A3.Pres

/-! A3.5 — library handles whose copies are one state: confinement.

A library handle (a `PNCounter`, a `TcpConn`, a `Cell`) is a cell: a lock
block whose shares are cell shares (`Val.cell`), which the library changes
in place, through any share, with no lock.  So it is Send but not Sync: its
shares may be on one thread only.  The invariant says so (`CellInv`): no
two threads' slots hold a share of one cell.

A thread's own step keeps it, because a step only hands on what the
thread's slots held: a cell share in its slots afterwards was in its slots
before, or is a new cell's (`cell_new`, at a key no slot names yet), since a
lent cell share is no share (`lendOf`) and no lock payload holds one
(`Ty.ok`, `MInv.blocks`) (`Step.cell`).  A spawn keeps it because of the
crossing check (`SendCheck`): a cell the moved values hold a share of keeps
no share in the spawner.  So two threads never change one cell's state at
once (`CellInv.cellRaceFree`). -/

namespace A3
open A2

/-! ### A cell share in a store -/

/-- A slot of the store holds a share of cell `k`. -/
def CellAt (m : Mem) (k : Nat) : Prop := ∃ y o v, m.st y = some ⟨o, some v⟩ ∧ Sub (.cell k) v

/-- A lock block's payload holds a share of cell `k` (no typed one does). -/
def CellPay (B : Nat → Option Blk) (k : Nat) : Prop :=
  ∃ k' t p, B k' = some ⟨t, .lock, some p⟩ ∧ Sub (.cell k) p

/-- A lent value holds no cell share. -/
theorem not_sub_cell_lendOf : (v : Val) → ∀ {k : Nat}, Sub (.cell k) (lendOf v) → False
  | .int _, _, h => by cases h
  | .node .., _, h => by simp only [lendOf] at h; cases h
  | .href _, _, h => by cases h
  | .view .., _, h => by cases h
  | .pair a b, _, h => by
    simp only [lendOf] at h
    cases h with
    | fst h => exact not_sub_cell_lendOf a h
    | snd h => exact not_sub_cell_lendOf b h
  | .inl a, _, h => by
    simp only [lendOf] at h
    cases h with | inl h => exact not_sub_cell_lendOf a h
  | .inr a, _, h => by
    simp only [lendOf] at h
    cases h with | inr h => exact not_sub_cell_lendOf a h
  | .pkg _ _ _ a _, _, h => by
    simp only [lendOf] at h
    cases h with | pkg h => exact not_sub_cell_lendOf a h
  | .arc _ _, _, h => by cases h
  | .lk _, _, h => by cases h
  | .cell _, _, h => by simp only [lendOf] at h; cases h

/-- A tree of a type that holds no share holds no cell share. -/
theorem _root_.A2.WFv.noCell {τ : Ty} {v : Val} (hw : WFv τ v) (hna : τ.hasArc = false) {k : Nat} :
    ¬ Sub (.cell k) v := by
  induction hw with
  | int => intro h; cases h
  | view => intro h; cases h
  | arc => simp [Ty.hasArc] at hna
  | lk => simp [Ty.hasArc] at hna
  | cell => simp [Ty.hasArc] at hna
  | pkg => simp [Ty.hasArc] at hna
  | node _ ih =>
    intro h
    cases h with
    | child he hs => exact ih _ he (by simpa [Ty.hasArc] using hna) hs
  | pair _ _ iha ihb =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at hna
    intro h
    cases h with
    | fst h => exact iha hna.1 h
    | snd h => exact ihb hna.2 h
  | inl _ ih =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at hna
    intro h; cases h with | inl h => exact ih hna.1 h
  | inr _ ih =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at hna
    intro h; cases h with | inr h => exact ih hna.2 h

/-- A thread's facts: no lock block's payload holds a cell share (a lock's
    payload holds no share at all, `Ty.ok`). -/
theorem ThreadOK.noCellPay {P : Prog} {m : Mem} {s : Stmt} (h : ThreadOK P m s) {k : Nat} :
    ¬ CellPay m.blk k := by
  obtain ⟨Γ, F, Δ, _, hi, _⟩ := h
  rintro ⟨k', t, p, hk, hs⟩
  obtain ⟨_, _, h3, h4⟩ := hi.blocks k' _ hk
  exact WFv.noCell (h3 p rfl).1 (h4 rfl) hs

theorem CellAt.of_slot {m : Mem} {y : Var} {o : Bool} {v : Val} (h : m.st y = some ⟨o, some v⟩) {k : Nat}
    (hs : Sub (.cell k) v) : CellAt m k := ⟨y, o, v, h, hs⟩

theorem CellAt.of_st {m m' : Mem} (hst : m'.st = m.st) {k : Nat} (h : CellAt m' k) : CellAt m k := by
  obtain ⟨y, o, v, hy, hs⟩ := h
  exact ⟨y, o, v, by rw [← hst]; exact hy, hs⟩

/-- A slot set: the share is in its new value, or it was in a slot before. -/
theorem CellAt.set {m : Mem} {x : Var} {sl : Slot} {k : Nat} (h : CellAt (m.set x sl) k) :
    (∃ v, sl.val = some v ∧ Sub (.cell k) v) ∨ CellAt m k := by
  obtain ⟨y, o, v, hy, hs⟩ := h
  simp only [Mem.set, upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy; exact .inl ⟨v, rfl, hs⟩
  · rw [ite_eq_right hyx] at hy; exact .inr ⟨y, o, v, hy, hs⟩

/-- A slot set to hold nothing. -/
theorem CellAt.set_none {m : Mem} {x : Var} {o : Bool} {k : Nat} (h : CellAt (m.set x ⟨o, none⟩) k) :
    CellAt m k :=
  (CellAt.set h).elim (fun ⟨_, h, _⟩ => by cases h) id

theorem CellAt.of_upd {m m' : Mem} {x : Var} (hst : m'.st = upd m.st x none) {k : Nat} (h : CellAt m' k) :
    CellAt m k := by
  obtain ⟨y, o, v, hy, hs⟩ := h
  rw [hst] at hy
  simp only [upd] at hy
  by_cases hyx : y = x
  · rw [ite_eq_left hyx] at hy; cases hy
  · rw [ite_eq_right hyx] at hy; exact ⟨y, o, v, hy, hs⟩

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

/-- Handing a value on: what is handed on was in a slot, and no slot gains a
    share. -/
theorem _root_.A2.TakeVal.cell {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) {k : Nat} :
    (Sub (.cell k) v → CellAt m k) ∧ (CellAt m1 k → CellAt m k) := by
  cases h with
  | own hy => exact ⟨fun hs => .of_slot hy hs, CellAt.set_none⟩
  | bor hy => exact ⟨fun hs => .of_slot hy hs, id⟩

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
  | pair h1 h2 => exact h1.cell.2 (h2.cell.2 hc)
  | inl h1 => exact h1.cell.2 hc
  | inr h1 => exact h1.cell.2 hc
  | pack h1 => exact h1.cell.2 hc
  | arcNew h1 _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | lockNew h1 _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | cellNew h1 _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | chanSend _ h1 _ _ _ _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | chanSendClosed _ h1 _ _ => exact h1.cell.2 (CellAt.of_st rfl hc)
  | _ => exact CellAt.of_st rfl hc

/-- **What a right-hand side hands back** holds a cell share a slot held, or
    a lock payload (none does), or a new cell's, at a key taken from `nid`
    now. -/
theorem _root_.A2.EvalR.cellVal {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1)) {k : Nat}
    (hs : Sub (.cell k) v) : CellAt m k ∨ CellPay m.blk k ∨ (m.nid ≤ k ∧ k < m1.nid) := by
  cases h with
  | expr _ => cases hs
  | new => exact absurd (sub_cell_node hs) (by simp)
  | moveOwn hy => exact .inl (.of_slot hy hs)
  | copy hy => exact .inl (.of_slot hy hs)
  | borrowOwn _ => cases hs
  | borrowBor hy => exact .inl (.of_slot hy hs)
  | «at» _ _ _ => exact (not_sub_cell_lendOf _ hs).elim
  | view _ => cases hs
  | sat _ _ _ _ _ _ => exact (not_sub_cell_lendOf _ hs).elim
  | pop hy _ _ => exact .inl (.of_slot hy (Sub.child (by simp) hs))
  | pair h1 h2 =>
    cases hs with
    | fst hs => exact .inl (h1.cell.1 hs)
    | snd hs => exact .inl (h1.cell.2 (h2.cell.1 hs))
  | fst _ => exact (not_sub_cell_lendOf _ hs).elim
  | snd _ => exact (not_sub_cell_lendOf _ hs).elim
  | inl h1 => cases hs with | inl hs => exact .inl (h1.cell.1 hs)
  | inr h1 => cases hs with | inr hs => exact .inl (h1.cell.1 hs)
  | getl _ => exact (not_sub_cell_lendOf _ hs).elim
  | getr _ => exact (not_sub_cell_lendOf _ hs).elim
  | takel hy => exact .inl (.of_slot hy (Sub.inl hs))
  | taker hy => exact .inl (.of_slot hy (Sub.inr hs))
  | pack h1 => cases hs with | pkg hs => exact .inl (h1.cell.1 hs)
  | arcNew _ _ => cases hs
  | arcClone _ => cases hs
  | arcGet _ _ => exact (not_sub_cell_lendOf _ hs).elim
  | lockNew _ _ => cases hs
  | lockClone _ => cases hs
  | @cellNew t y w m1 h1 _ =>
    cases hs
    have hn : m1.nid = m.nid := by cases h1 <;> rfl
    exact .inr (.inr ⟨Nat.le_of_eq hn.symm, Nat.lt_succ_self _⟩)
  | cellClone hy => exact .inl (.of_slot hy hs)
  | atomic _ _ _ _ _ => cases hs
  | chanSend _ _ _ _ _ _ => cases hs
  | chanSendClosed _ _ _ _ => cases hs
  | chanRecv _ hk _ _ _ =>
    cases hs with
    | inr hs => exact .inr (.inl ⟨_, _, _, hk, Sub.fst (Sub.child (by simp) hs)⟩)
  | chanRecvNone _ _ _ _ => cases hs with | inl hs => cases hs
  | chanClose _ _ _ => cases hs
  | rwRead _ _ _ => cases hs

/-- Binding parameters hands each a value an argument held (an `in`
    parameter is lent its argument: no cell share). -/
theorem _root_.A2.BindParams.cellSt {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : ∀ {k : Nat}, CellAt m' k → CellAt m k := by
  induction h with
  | nil => exact id
  | @inp m m' t ps a as base i sl v ha hl _ ih =>
    intro k hc
    rcases CellAt.set (ih hc) with ⟨w, hw, hs⟩ | hc
    · cases hw
      obtain ⟨o, u⟩ := sl
      cases o <;> cases u <;> simp only [lendSlot, Option.some.injEq, reduceCtorEq] at hl
      · subst hl; exact .of_slot ha hs
      · subst hl; exact (not_sub_cell_lendOf _ hs).elim
    · exact hc
  | sink ha _ ih =>
    intro k hc
    rcases CellAt.set (ih hc) with ⟨w, hw, hs⟩ | hc
    · cases hw; exact .of_slot ha hs
    · exact CellAt.set_none hc
  | inout _ ih => exact ih

/-- A package's environment, lent: no cell share. -/
theorem CellAt.envMem {m : Mem} {env : Val} {k : Nat} (h : CellAt (envMem m env) k) : CellAt m k := by
  rcases CellAt.set (m := m) (CellAt.of_st rfl h) with ⟨w, hw, hs⟩ | hc
  · cases hw; exact (not_sub_cell_lendOf _ hs).elim
  · exact hc

/-- **A step's slots hold a cell share** its start's slots held, or a lock
    payload (none does), or a new cell's, at a key it took from `nid`. -/
theorem _root_.A2.Step.cell {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) :
    ∀ {k : Nat}, CellAt r.mem k → CellAt m k ∨ CellPay m.blk k ∨ (m.nid ≤ k ∧ k < r.mem.nid) := by
  induction h with
  | seqSkip => exact fun hc => .inl hc
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; exact he.cellVal hs
    · exact .inl (he.cellSt hc)
  | letvP _ => exact fun hc => .inl hc
  | letcall _ _ hbp =>
    exact fun hc => .inl (hbp.cellSt (CellAt.set_none (CellAt.set_none (CellAt.of_st rfl hc))))
  | scopeSkip _ _ => exact fun hc => .inl (CellAt.remove (CellAt.of_st rfl hc))
  | scopeIn _ ih => exact ih
  | scopeP _ _ _ ih => exact fun hc => ih (CellAt.of_st rfl (CellAt.remove hc))
  | rbindSkip _ => exact fun hc => .inl (CellAt.remove hc)
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact fun hc => ih (CellAt.remove hc)
  | frozenSkip => exact fun hc => .inl hc
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ _ =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; exact he.cellVal hs
    · exact .inl (he.cellSt (CellAt.of_st rfl hc))
  | assignP _ => exact fun hc => .inl hc
  | iteT _ _ => exact fun hc => .inl hc
  | iteF _ => exact fun hc => .inl hc
  | «while» => exact fun hc => .inl hc
  | push ht hx _ _ =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      obtain ⟨e, he, hse⟩ := sub_cell_node hs
      rcases List.mem_append.mp he with he | he
      · exact .inl (ht.cell.2 (.of_slot hx (Sub.child he hse)))
      · rw [List.mem_singleton] at he; subst he; exact .inl (ht.cell.1 hse)
    · exact .inl (ht.cell.2 hc)
  | pushRealloc ht hx _ _ =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      obtain ⟨e, he, hse⟩ := sub_cell_node hs
      rcases List.mem_append.mp he with he | he
      · exact .inl (ht.cell.2 (.of_slot hx (Sub.child he hse)))
      · rw [List.mem_singleton] at he; subst he; exact .inl (ht.cell.1 hse)
    · exact .inl (ht.cell.2 (CellAt.of_st rfl hc))
  | editPush ht hn hr =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact .inl (ht.cell.2 (.of_slot hn.2.2.1 h))
      · obtain ⟨e, he, hse⟩ := sub_cell_node h
        rcases List.mem_append.mp he with he | he
        · exact .inl (ht.cell.2 (.of_slot hn.2.2.1 ((Sub.child he hse).trans hr.sub)))
        · rw [List.mem_singleton] at he; subst he; exact .inl (ht.cell.1 hse)
    · exact .inl (ht.cell.2 hc)
  | editPushRealloc ht hn hr =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact .inl (ht.cell.2 (.of_slot hn.2.2.1 h))
      · obtain ⟨e, he, hse⟩ := sub_cell_node h
        rcases List.mem_append.mp he with he | he
        · exact .inl (ht.cell.2 (.of_slot hn.2.2.1 ((Sub.child he hse).trans hr.sub)))
        · rw [List.mem_singleton] at he; subst he; exact .inl (ht.cell.1 hse)
    · exact .inl (ht.cell.2 (CellAt.of_st rfl hc))
  | editTrunc _ hn _ hr =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact .inl (.of_slot hn.2.2.1 h)
      · exact .inl (.of_slot hn.2.2.1
          ((sub_cell_node_sub h fun e he => List.mem_of_mem_take he).trans hr.sub))
    · exact .inl (CellAt.of_st rfl hc)
  | editSet _ _ ht hn _ hr =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw
      rcases hr.cell hs with h | h
      · exact .inl (ht.cell.2 (.of_slot hn.2.2.1 h))
      · obtain ⟨e, he, hse⟩ := sub_cell_node h
        rcases List.mem_or_eq_of_mem_set he with he | rfl
        · exact .inl (ht.cell.2 (.of_slot hn.2.2.1 ((Sub.child he hse).trans hr.sub)))
        · exact .inl (ht.cell.1 hse)
    · exact .inl (ht.cell.2 (CellAt.of_st rfl hc))
  | editSetOOB _ ht _ _ _ => exact fun hc => .inl (ht.cell.2 (CellAt.of_st rfl hc))
  | free _ _ => exact fun hc => .inl (CellAt.of_st rfl (CellAt.set_none hc))
  | panic => exact fun hc => .inl hc
  | waitPanic _ => exact fun hc => .inl hc
  | letrec _ _ _ =>
    exact fun hc => .inl (CellAt.set_none (CellAt.set_none (CellAt.of_st rfl hc)))
  | catchIn _ ih => exact ih
  | catchSkip => exact fun hc => .inl hc
  | unpair hy _ _ _ =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; exact .inl (.of_slot hy (Sub.snd hs))
    · rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
      · cases hw; exact .inl (.of_slot hy (Sub.fst hs))
      · exact .inl (CellAt.set_none hc)
  | callc _ _ _ _ hbp =>
    exact fun hc => .inl (CellAt.envMem (hbp.cellSt (CellAt.set_none (CellAt.set_none (CellAt.of_st rfl hc)))))
  | catchP _ _ ih =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; cases hs
    · exact ih hc
  | letd _ he =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; exact he.cellVal hs
    · exact .inl (he.cellSt hc)
  | letdP _ => exact fun hc => .inl hc
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ => exact fun hc => .inl (CellAt.of_st rfl hc)
  | scopeDMoved _ => exact fun hc => .inl (CellAt.remove hc)
  | scopeDP _ _ ih => exact fun hc => ih (CellAt.of_st rfl hc)
  | scopeDPMoved _ _ ih => exact fun hc => ih (CellAt.remove hc)
  | withLock _ hk _ _ =>
    intro k hc
    rcases CellAt.set hc with ⟨w, hw, hs⟩ | hc
    · cases hw; exact .inr (.inl ⟨_, _, _, hk, hs⟩)
    · exact .inl (CellAt.of_st rfl hc)
  | scopeLIn _ ih => exact ih
  | scopeLSkip hrl => exact fun hc => .inl (CellAt.of_upd hrl.st hc)
  | scopeLP _ hrl ih =>
    intro k hc
    have h := ih (CellAt.of_upd hrl.st hc)
    simp only [Res.mem] at h ⊢
    rw [hrl.nid]; exact h

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

/-- A thread's slot holds a share of cell `k`. -/
def Thread.cellAt (t : Thread) (k : Nat) : Prop := ∃ y o v, t.st y = some ⟨o, some v⟩ ∧ Sub (.cell k) v

/-- **A3.5's invariant: a cell's shares are on one thread.**  No two threads'
    slots hold a share of one cell, and a cell share names a key taken from
    `nid` (so a new cell's key is no thread's). -/
structure CellInv (C : Cfg) : Prop where
  below : ∀ (j : Nat) (t : Thread) (k : Nat), C.ths[j]? = some t → t.cellAt k → k < C.nid
  home  : ∀ (i j : Nat) (ti tj : Thread) (k : Nat), C.ths[i]? = some ti → C.ths[j]? = some tj →
    ti.cellAt k → tj.cellAt k → i = j

/-- The start: one thread, holding nothing. -/
theorem CellInv.init (s : Stmt) (nv : Nat) : CellInv (Cfg.init s nv) := by
  have hnone : ∀ (j : Nat) (t : Thread) (k : Nat), (Cfg.init s nv).ths[j]? = some t → ¬ t.cellAt k := by
    rintro j t k hj ⟨y, o, v, hy, _⟩
    cases j with
    | zero => simp [Cfg.init] at hj; subst hj; cases hy
    | succ j => simp [Cfg.init] at hj
  exact ⟨fun j t k hj hk => absurd hk (hnone j t k hj), fun i _ ti _ k hi _ hk _ => absurd hk (hnone i ti k hi)⟩

/-- **A thread's step, and the sweep that ends it, keep the cells' homes**:
    a cell share the stepping thread holds afterwards it held before, or it
    is a new cell's, at a key no thread's share names (`Step.cell`; a lock
    payload holds none). -/
theorem CellInv.thread_of {P : Prog} {C : Cfg} (hC : CInv P C) (h : CellInv C) {i : Nat} {t : Thread}
    {m' : Mem} {s' : Stmt} (hi : C.ths[i]? = some t) (hst : Step P (C.view t) t.s (.ok m' s')) :
    CellInv (C.put i m' s').sweep := by
  obtain ⟨ps, hc, _⟩ := hC
  obtain ⟨a, ha⟩ := part_of hc.len hi
  have hto := (hc.ok i t a hi ha).1
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  have hnid : C.nid ≤ m'.nid := (Step.grows hst).nid
  have hnew : ∀ k, (⟨m'.st, m'.nv, s'⟩ : Thread).cellAt k → t.cellAt k ∨ (C.nid ≤ k ∧ k < m'.nid) := by
    intro k hk
    obtain ⟨y, o, v, hy, hs⟩ := hk
    rcases Step.cell hst (k := k) ⟨y, o, v, hy, hs⟩ with h1 | h1 | h1
    · exact .inl h1
    · exact absurd h1 (hto.noCellPay (k := k))
    · exact .inr h1
  have hths : ∀ j tj, ((C.put i m' s').sweep).ths[j]? = some tj →
      (j = i ∧ tj = ⟨m'.st, m'.nv, s'⟩) ∨ (j ≠ i ∧ C.ths[j]? = some tj) := by
    intro j tj hj
    simp only [Cfg.sweep, Cfg.put] at hj
    rw [list_set_get hilen] at hj
    by_cases hij : i = j
    · rw [ite_eq_left hij] at hj; cases hj; exact .inl ⟨hij.symm, rfl⟩
    · rw [ite_eq_right hij] at hj; exact .inr ⟨Ne.symm hij, hj⟩
  constructor
  · intro j tj k hj hk
    show k < m'.nid
    rcases hths j tj hj with ⟨_, e⟩ | ⟨_, hj⟩
    · subst e
      rcases hnew k hk with h1 | h1
      · exact Nat.lt_of_lt_of_le (h.below i t k hi h1) hnid
      · exact h1.2
    · exact Nat.lt_of_lt_of_le (h.below j tj k hj hk) hnid
  · intro j1 j2 t1 t2 k hj1 hj2 hk1 hk2
    rcases hths j1 t1 hj1 with ⟨e1, f1⟩ | ⟨_, hj1⟩ <;> rcases hths j2 t2 hj2 with ⟨e2, f2⟩ | ⟨_, hj2⟩
    · rw [e1, e2]
    · subst f1
      rcases hnew k hk1 with h1 | h1
      · rw [e1]; exact h.home _ _ _ _ k hi hj2 h1 hk2
      · exact absurd (h.below _ _ k hj2 hk2) (Nat.not_lt.mpr h1.1)
    · subst f2
      rcases hnew k hk2 with h2 | h2
      · rw [e2]; exact h.home _ _ _ _ k hj1 hi hk1 h2
      · exact absurd (h.below _ _ k hj1 hk1) (Nat.not_lt.mpr h2.1)
    · exact h.home _ _ _ _ k hj1 hj2 hk1 hk2

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
    obtain ⟨y, o, v, hy, hs⟩ := hk
    exact ⟨y, o, v, he ▸ hy, hs⟩
  refine ⟨fun j tj k hj hk => ?_, fun j1 j2 t1 t2 k hj1 hj2 hk1 hk2 => ?_⟩
  · obtain ⟨tj0, hj0, he⟩ := hths j tj hj
    exact h.below j tj0 k hj0 (hcell he hk)
  · obtain ⟨t10, h10, he1⟩ := hths j1 t1 hj1
    obtain ⟨t20, h20, he2⟩ := hths j2 t2 hj2
    exact h.home j1 j2 t10 t20 k h10 h20 (hcell he1 hk1) (hcell he2 hk2)

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
    (hi : C.ths[i]? = some t) (hmv : MoveArgs t.st args vs st') (hsc : SendCheck vs st') :
    CellInv { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k0)⟩ ++
                      [⟨spawnSt fn vs, fn.nvars, wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] } := by
  have hilen : i < C.ths.length := (List.getElem?_eq_some_iff.mp hi).1
  -- the spawner holds what it held
  have hS : ∀ k, (⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k0)⟩ : Thread).cellAt k →
      ∃ y o w, st' y = some ⟨o, some w⟩ ∧ Sub (.cell k) w := by
    rintro k ⟨y, o, w, hy, hs⟩
    simp only [upd] at hy
    by_cases hyx : y = x
    · rw [ite_eq_left hyx] at hy; cases hy; cases hs
    · rw [ite_eq_right hyx] at hy; exact ⟨y, o, w, hy, hs⟩
  have hS' : ∀ k, (⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k0)⟩ : Thread).cellAt k →
      t.cellAt k := by
    intro k hk
    obtain ⟨y, o, w, hy, hs⟩ := hS k hk
    rcases MoveArgs.slot hmv y _ hy with h0 | h0
    · exact ⟨y, o, w, h0, hs⟩
    · cases h0
  -- the new thread holds what a moved value held
  have hN : ∀ k, (⟨spawnSt fn vs, fn.nvars, wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩ :
      Thread).cellAt k → ∃ v ∈ vs, Sub (.cell k) v := by
    rintro k ⟨y, o, w, hy, hs⟩
    simp only [spawnSt] at hy
    split at hy
    · cases hy
    · cases hv : vs[y]? with
      | none => rw [hv] at hy; cases hy
      | some u => rw [hv] at hy; cases hy; exact ⟨_, List.mem_of_getElem? hv, hs⟩
  have hN' : ∀ k, (∃ v ∈ vs, Sub (.cell k) v) → t.cellAt k := by
    rintro k ⟨v, hv, hs⟩
    obtain ⟨a0, ha0⟩ := MoveArgs.val hmv v hv
    exact ⟨a0, true, v, ha0, hs⟩
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
  refine ⟨fun j tj k hj hk => ?_, fun j1 j2 t1 t2 k hj1 hj2 hk1 hk2 => ?_⟩
  · rcases hths j tj hj with ⟨_, e⟩ | ⟨_, e⟩ | ⟨_, _, hj⟩
    · subst e; exact h.below i t k hi (hS' k hk)
    · subst e; exact h.below i t k hi (hN' k (hN k hk))
    · exact h.below j tj k hj hk
  · rcases hths j1 t1 hj1 with ⟨e1, f1⟩ | ⟨e1, f1⟩ | ⟨hji1, _, hj1'⟩ <;>
      rcases hths j2 t2 hj2 with ⟨e2, f2⟩ | ⟨e2, f2⟩ | ⟨hji2, _, hj2'⟩
    · rw [e1, e2]
    · -- the spawner and the new thread: the crossing check
      subst f1; subst f2
      obtain ⟨y, o, w, hy, hs⟩ := hS k hk1
      exact absurd hs (hsc k (hN k hk2) y o w hy)
    · subst f1
      exact absurd (h.home _ _ _ _ k hi hj2' (hS' k hk1) hk2).symm hji2
    · subst f1; subst f2
      obtain ⟨y, o, w, hy, hs⟩ := hS k hk2
      exact absurd hs (hsc k (hN k hk1) y o w hy)
    · rw [e1, e2]
    · subst f1
      exact absurd (h.home _ _ _ _ k hi hj2' (hN' k (hN k hk1)) hk2).symm hji2
    · subst f2
      exact absurd (h.home _ _ _ _ k hj1' hi hk1 (hS' k hk2)) hji1
    · subst f2
      exact absurd (h.home _ _ _ _ k hj1' hi hk1 (hN' k (hN k hk2))) hji1
    · exact h.home _ _ _ _ k hj1' hj2' hk1 hk2

/-- A step on a cell's state is by a thread that holds a share of it. -/
theorem CellOp.cellAt {t : Thread} {k : Nat} (h : CellOp t k) : t.cellAt k := by
  rcases h with ⟨_, a, _, _, o, _, ha⟩ | ⟨_, hk⟩
  · exact ⟨a, o, _, ha, Sub.refl _⟩
  · exact hk

/-- **No cell race**: two threads never change one cell's state at once —
    each would hold a share of it, and its shares are on one thread. -/
theorem CellInv.cellRaceFree {C : Cfg} (h : CellInv C) : ¬ CellRace C := by
  rintro ⟨i, j, ti, tj, k, hij, hi, hj, h1, h2⟩
  exact hij (h.home i j ti tj k hi hj h1.cellAt h2.cellAt)

end A3
