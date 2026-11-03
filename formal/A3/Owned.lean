import A3.Rel
import A2.Repl

/-! A3.0 — what a step's owned trees hold: addresses the step's start
owned, or fresh ones.  A step moves trees between slots, takes subtrees out
of them and packs them into structs; a borrowed value it packs has no
address (`BorFree`), and the only addresses it adds are the ones it
allocates, at or past `nid`.  So a thread's owned trees keep avoiding the
other threads' parts through every store of a step. -/

namespace A3
open A2

/-! ### Owned addresses after an update -/

theorem OwnedId.of_slot {m : Mem} {x : Var} {t : Val} (hx : m.st x = some ⟨true, some t⟩) {i : Nat}
    (hi : i ∈ t.ids) : OwnedId m i := ⟨x, t, hx, hi⟩

/-- An owned address after one slot is set: in the slot's new tree, or
    owned before. -/
theorem OwnedId.of_set {m : Mem} {x : Var} {o : Bool} {w : Option Val} {i : Nat}
    (h : OwnedId (m.set x ⟨o, w⟩) i) : (o = true ∧ ∃ t, w = some t ∧ i ∈ t.ids) ∨ OwnedId m i := by
  obtain ⟨y, t, hy, hi⟩ := h
  rcases ownedAt_set.mp hy with ⟨_, he⟩ | ⟨_, hy'⟩
  · cases he; exact .inl ⟨rfl, t, rfl, hi⟩
  · exact .inr ⟨y, t, hy', hi⟩

theorem OwnedId.set_some {m : Mem} {x : Var} {o : Bool} {v : Val} {i : Nat}
    (h : OwnedId (m.set x ⟨o, some v⟩) i) : (o = true ∧ i ∈ v.ids) ∨ OwnedId m i := by
  rcases OwnedId.of_set h with ⟨ho, t, ht, hi⟩ | h
  · cases ht; exact .inl ⟨ho, hi⟩
  · exact .inr h

/-- An emptied slot owns nothing. -/
theorem OwnedId.set_none {m : Mem} {x : Var} {o : Bool} {i : Nat}
    (h : OwnedId (m.set x ⟨o, none⟩) i) : OwnedId m i := by
  rcases OwnedId.of_set h with ⟨_, t, ht, _⟩ | h
  · cases ht
  · exact h

/-- A borrowed slot owns nothing. -/
theorem OwnedId.set_bor {m : Mem} {x : Var} {w : Option Val} {i : Nat}
    (h : OwnedId (m.set x ⟨false, w⟩) i) : OwnedId m i := by
  rcases OwnedId.of_set h with ⟨ho, _⟩ | h
  · cases ho
  · exact h

theorem OwnedId.of_remove {m : Mem} {x : Var} {i : Nat} (h : OwnedId (m.remove x) i) : OwnedId m i := by
  obtain ⟨y, t, hy, hi⟩ := h
  exact ⟨y, t, (ownedAt_remove.mp hy).2, hi⟩

/-- A lock scope's end owns only what was owned: it removes its slot. -/
theorem Release.ownedId {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') {i : Nat}
    (hi : OwnedId m' i) : OwnedId m i := by
  obtain ⟨y, T, hy, hiy⟩ := hi
  have hy' : (m.remove x).st y = some ⟨true, some T⟩ := by rw [show (m.remove x).st = m'.st by rw [h.st]; rfl]; exact hy
  exact OwnedId.of_remove ⟨y, T, hy', hiy⟩

/-- `OwnedId` reads the bindings only. -/
theorem OwnedId.of_st {m m' : Mem} (hst : m'.st = m.st) {i : Nat} (h : OwnedId m' i) : OwnedId m i := by
  obtain ⟨y, t, hy, hi⟩ := h
  exact ⟨y, t, by unfold OwnedAt at *; rw [← hst]; exact hy, hi⟩

theorem OwnedId.of_nv {m : Mem} {k i : Nat} (h : OwnedId { m with nv := k } i) : OwnedId m i := h

/-- A package's environment is bound lent: it owns nothing. -/
theorem OwnedId.of_envMem {m : Mem} {env : Val} {i : Nat} (h : OwnedId (envMem m env) i) :
    OwnedId m i :=
  OwnedId.set_bor (OwnedId.of_nv h)

/-- An address of a `Vec` with an element pushed: the `Vec`'s, or the
    element's. -/
theorem mem_ids_push {t : Ty} {c d : Nat} {es : List Val} {e : Val} {i : Nat}
    (h : i ∈ (Val.node t c d (es ++ [e])).ids) : i ∈ (Val.node t c d es).ids ∨ i ∈ e.ids := by
  simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.mem_cons,
    List.mem_append] at h ⊢
  rcases h with h | h | h | h
  · exact .inl (.inl h)
  · exact .inl (.inr (.inl h))
  · exact .inl (.inr (.inr h))
  · exact .inr h

/-- A `Vec` holds the addresses of its last element and of what a pop
    leaves of it. -/
theorem mem_ids_pop {t : Ty} {c d : Nat} {es : List Val} {e : Val} {i : Nat} :
    (i ∈ (Val.node t c d es).ids ∨ i ∈ e.ids) → i ∈ (Val.node t c d (es ++ [e])).ids := by
  simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.mem_cons,
    List.mem_append]
  rintro ((h | h | h) | h)
  · exact .inl h
  · exact .inr (.inl h)
  · exact .inr (.inr (.inl h))
  · exact .inr (.inr (.inr h))

/-! ### Each part of a step -/

/-- **Handing a value on**: what it hands on was owned, and nothing becomes
    owned. -/
theorem TakeVal.ownedId {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) (hb : BorFree m) :
    (∀ i ∈ v.ids, OwnedId m i) ∧ ∀ i, OwnedId m1 i → OwnedId m i := by
  cases h with
  | own hy => exact ⟨fun i hi => OwnedId.of_slot hy hi, fun i hi => OwnedId.set_none hi⟩
  | bor hy => exact ⟨fun i hi => by simp [hb y v hy] at hi, fun i hi => hi⟩

/-- **Evaluating a right-hand side**: what it hands back owned, and what the
    store it leaves owns, was owned before or is fresh. -/
theorem EvalR.ownedId {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    (hb : BorFree m) :
    (o = true → ∀ i ∈ v.ids, OwnedId m i ∨ m.nid ≤ i ∨ PayAddr m i) ∧ ∀ i, OwnedId m1 i → OwnedId m i ∨ m.nid ≤ i := by
  cases h with
  | new =>
    refine ⟨fun _ i hi => .inr (.inl ?_), fun i hi => .inl hi⟩
    simp only [ids_node, idsL_nil, List.mem_cons, List.not_mem_nil, or_false] at hi
    rcases hi with rfl | rfl <;> omega
  | moveOwn hy => exact ⟨fun _ i hi => .inl (OwnedId.of_slot hy hi), fun i hi => .inl (OwnedId.set_none hi)⟩
  | pop hy _ _ =>
    refine ⟨fun _ i hi => .inl (OwnedId.of_slot hy (mem_ids_pop (.inr hi))), fun i hi => .inl ?_⟩
    rcases OwnedId.set_some hi with ⟨_, hi⟩ | hi
    · exact OwnedId.of_slot hy (mem_ids_pop (.inl hi))
    · exact hi
  | pair h1 h2 =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId h1 hb
    obtain ⟨a2, b2⟩ := TakeVal.ownedId h2 (TakeVal.borFree h1 hb).1
    refine ⟨fun _ i hi => .inl ?_, fun i hi => .inl (b1 i (b2 i hi))⟩
    simp only [ids_pair, List.mem_append] at hi
    rcases hi with hi | hi
    · exact a1 i hi
    · exact b1 i (a2 i hi)
  | inl h1 =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId h1 hb
    exact ⟨fun _ i hi => .inl (a1 i (by simpa using hi)), fun i hi => .inl (b1 i hi)⟩
  | inr h1 =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId h1 hb
    exact ⟨fun _ i hi => .inl (a1 i (by simpa using hi)), fun i hi => .inl (b1 i hi)⟩
  | takel hy =>
    exact ⟨fun _ i hi => .inl (OwnedId.of_slot hy (by simpa using hi)),
      fun i hi => .inl (OwnedId.set_none hi)⟩
  | taker hy =>
    exact ⟨fun _ i hi => .inl (OwnedId.of_slot hy (by simpa using hi)),
      fun i hi => .inl (OwnedId.set_none hi)⟩
  | pack h1 =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId h1 hb
    exact ⟨fun _ i hi => .inl (a1 i (by simpa using hi)), fun i hi => .inl (b1 i hi)⟩
  -- A3.1: a share owns no address; a new block takes `y`'s tree, which leaves the owned trees
  | arcNew h1 _ =>
    obtain ⟨_, b1⟩ := TakeVal.ownedId h1 hb
    exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl (b1 i hi)⟩
  | lockNew h1 _ =>
    obtain ⟨_, b1⟩ := TakeVal.ownedId h1 hb
    exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl (b1 i hi)⟩
  | cellNew h1 _ =>
    obtain ⟨_, b1⟩ := TakeVal.ownedId h1 hb
    exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl (b1 i hi)⟩
  | arcClone _ => exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl hi⟩
  | lockClone _ => exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl hi⟩
  | cellClone _ => exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl hi⟩
  -- A3.6: a global's share owns no address
  | glob _ hf =>
    rcases hf with ⟨_, _, _, _, rfl, _⟩ | ⟨_, _, _, _, rfl, _⟩ <;>
      exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl hi⟩
  -- A3.4: a value sent leaves the owned trees; one received was the channel's payload's
  | chanSend _ h1 _ _ _ => exact ⟨fun h => (nomatch h), fun i hi => .inl ((TakeVal.ownedId h1 hb).2 i hi)⟩
  | chanSendClosed _ h1 _ _ =>
    exact ⟨fun h => (nomatch h), fun i hi => .inl ((TakeVal.ownedId h1 hb).2 i hi)⟩
  | chanRecv _ hk _ _ =>
    exact ⟨fun _ i hi => .inr (.inr ⟨_, _, hk, by simp only [ids_inr] at hi; simp [Blk.tree, hi]⟩),
      fun i hi => .inl hi⟩
  | chanRecvNone _ _ _ _ => exact ⟨fun _ i hi => by simp at hi, fun i hi => .inl hi⟩
  -- A3.3: a read guard is a share, which owns no address
  | rwRead _ _ _ => exact ⟨fun _ i hi => by simp [Val.ids] at hi, fun i hi => .inl hi⟩
  | _ => exact ⟨fun h => (nomatch h), fun i hi => .inl hi⟩

/-- **Binding parameters**: a `sink` parameter owns what its argument owned,
    an `in` parameter owns nothing. -/
theorem BindParams.ownedId {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (hb : BorFree m) : ∀ j, OwnedId m' j → OwnedId m j := by
  induction h with
  | nil => exact fun j hj => hj
  | inp ha hl _ ih =>
    exact fun j hj =>
      OwnedId.set_bor (ih (hb.set _ (SlotFree.ids fun _ => lendSlot_ids hb ha hl)) j hj)
  | sink ha _ ih =>
    intro j hj
    rcases OwnedId.set_some (ih ((hb.set _ (SlotFree.own _)).set _ (SlotFree.own _)) j hj) with
      ⟨_, hjv⟩ | hj
    · exact OwnedId.of_slot ha hjv
    · exact OwnedId.set_none hj
  | inout _ ih => exact ih hb

/-! ### A step -/

/-- **A step's owned trees** hold only addresses its start owned, or fresh
    ones. -/
theorem Step.ownedId {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hb : BorFree m) :
    ∀ i, OwnedId r.mem i → OwnedId m i ∨ m.nid ≤ i ∨ PayAddr m i := by
  induction h with
  | seqSkip => exact fun i hi => .inl hi
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he =>
    intro i hi
    rcases OwnedId.set_some hi with ⟨ho, hiv⟩ | hi
    · exact (EvalR.ownedId he hb).1 ho i hiv
    · exact ((EvalR.ownedId he hb).2 i hi).imp_right .inl
  | letvP _ => exact fun i hi => .inl hi
  | letcall _ _ hbp =>
    exact fun i hi =>
      .inl (BindParams.ownedId hbp hb i (OwnedId.set_none (OwnedId.set_none (OwnedId.of_nv hi))))
  | scopeSkip _ _ => exact fun i hi => .inl (OwnedId.of_remove hi)
  | scopeIn _ ih => exact ih
  | scopeP _ _ _ ih => exact fun i hi => ih i (OwnedId.of_remove hi)
  | rbindSkip _ => exact fun i hi => .inl (OwnedId.of_remove hi)
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact fun i hi => ih i (OwnedId.of_remove hi)
  | frozenSkip => exact fun i hi => .inl hi
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ _ =>
    intro i hi
    rcases OwnedId.set_some hi with ⟨ho, hiv⟩ | hi
    · exact (EvalR.ownedId he hb).1 ho i hiv
    · exact ((EvalR.ownedId he hb).2 i hi).imp_right .inl
  | assignP _ => exact fun i hi => .inl hi
  | iteT _ _ => exact fun i hi => .inl hi
  | iteF _ => exact fun i hi => .inl hi
  | «while» => exact fun i hi => .inl hi
  | push ht hx _ _ =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId ht hb
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases mem_ids_push hiv with hi | hi
      · exact .inl (b1 i (OwnedId.of_slot hx hi))
      · exact .inl (a1 i hi)
    · exact .inl (b1 i hi)
  | insert _ ht hx _ _ =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId ht hb
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases mem_ids_push ((ids_perm (perm_insert _ _ _)).subset hiv) with hi | hi
      · exact .inl (b1 i (OwnedId.of_slot hx hi))
      · exact .inl (a1 i hi)
    · exact .inl (b1 i hi)
  | pushRealloc ht hx _ _ =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId ht hb
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases mem_ids_push hiv with hi | hi
      · simp only [ids_node, List.mem_cons] at hi
        rcases hi with hi | hi | hi
        · exact .inl (b1 i (OwnedId.of_slot hx (by simp [hi])))
        · subst hi; exact .inr (.inl (TakeVal.grows ht).nid)
        · exact .inl (b1 i (OwnedId.of_slot hx (by simp [hi])))
      · exact .inl (a1 i hi)
    · exact .inl (b1 i hi)
  | free _ _ => exact fun i hi => .inl (OwnedId.set_none hi)
  | editPush ht hn hr =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId ht hb
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases hr.mem_ids hiv with hi | hi
      · rcases mem_ids_push hi with hi | hi
        · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 (hr.sub.ids i hi)))
        · exact .inl (a1 i hi)
      · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 hi))
    · exact .inl (b1 i hi)
  | editPushRealloc ht hn hr =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId ht hb
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases hr.mem_ids hiv with hi | hi
      · rcases mem_ids_push hi with hi | hi
        · simp only [ids_node, List.mem_cons] at hi
          rcases hi with hi | hi | hi
          · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 (hr.sub.ids i (by simp [hi]))))
          · subst hi; exact .inr (.inl (TakeVal.grows ht).nid)
          · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 (hr.sub.ids i (by simp [hi]))))
        · exact .inl (a1 i hi)
      · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 hi))
    · exact .inl (b1 i hi)
  | editTrunc _ hn _ hr =>
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases hr.mem_ids hiv with hi | hi
      · refine .inl (OwnedId.of_slot hn.2.2.1 (hr.sub.ids i ?_))
        simp only [ids_node, List.mem_cons] at hi ⊢
        rcases hi with hi | hi | hi
        · exact .inl hi
        · exact .inr (.inl hi)
        · obtain ⟨e, he, hie⟩ := mem_idsL_iff.mp hi
          exact .inr (.inr (mem_idsL (List.mem_of_mem_take he) hie))
      · exact .inl (OwnedId.of_slot hn.2.2.1 hi)
    · exact .inl hi
  | editSet _ _ ht hn _ hr =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId ht hb
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases hr.mem_ids hiv with hi | hi
      · simp only [ids_node, List.mem_cons] at hi
        rcases hi with hi | hi | hi
        · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 (hr.sub.ids i (by simp [hi]))))
        · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 (hr.sub.ids i (by simp [hi]))))
        · obtain ⟨e, he, hie⟩ := mem_idsL_iff.mp hi
          rcases List.mem_or_eq_of_mem_set he with he | rfl
          · refine .inl (b1 i (OwnedId.of_slot hn.2.2.1 (hr.sub.ids i ?_)))
            simp only [ids_node, List.mem_cons]
            exact .inr (.inr (mem_idsL he hie))
          · exact .inl (a1 i hie)
      · exact .inl (b1 i (OwnedId.of_slot hn.2.2.1 hi))
    · exact .inl (b1 i hi)
  | editSetOOB _ ht _ _ _ => exact fun i hi => .inl ((TakeVal.ownedId ht hb).2 i hi)
  | panic => exact fun i hi => .inl hi
  | waitPanic _ => exact fun i hi => .inl hi
  | letrec _ _ _ =>
    exact fun i hi => .inl (OwnedId.set_none (OwnedId.set_none (OwnedId.of_nv hi)))
  | catchIn _ ih => exact ih
  | catchSkip => exact fun i hi => .inl hi
  | unpair hy _ _ _ =>
    intro i hi
    refine .inl ?_
    rcases OwnedId.set_some hi with ⟨_, hiw⟩ | hi
    · exact OwnedId.of_slot hy (by simp [hiw])
    · rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
      · exact OwnedId.of_slot hy (by simp [hiv])
      · exact OwnedId.set_none hi
  | callc _ _ _ _ hbp =>
    exact fun i hi => .inl (OwnedId.of_envMem (BindParams.ownedId hbp (envMem_borFree hb _) i
      (OwnedId.set_none (OwnedId.set_none (OwnedId.of_nv hi)))))
  | catchP _ _ ih => exact fun i hi => ih i (OwnedId.set_bor hi)
  | letd _ he =>
    intro i hi
    rcases OwnedId.set_some hi with ⟨ho, hiv⟩ | hi
    · exact (EvalR.ownedId he hb).1 ho i hiv
    · exact ((EvalR.ownedId he hb).2 i hi).imp_right .inl
  | letdP _ => exact fun i hi => .inl hi
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ => exact fun i hi => .inl (OwnedId.of_nv hi)
  | scopeDMoved _ => exact fun i hi => .inl (OwnedId.of_remove hi)
  | scopeDP _ _ ih => exact fun i hi => ih i (OwnedId.of_nv hi)
  | scopeDPMoved _ _ ih => exact fun i hi => ih i (OwnedId.of_remove hi)
  -- A3.2: a lock's payload checked out is owned; one given back is the block's
  | withLock _ hk _ =>
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · exact .inr (.inr ⟨_, _, hk, hiv⟩)
    · exact .inl hi
  | scopeLIn _ ih => exact ih
  | scopeLSkip hrl =>
    cases hrl with
    | put _ _ _ => exact fun i hi => .inl (OwnedId.of_remove hi)
    | drop _ _ _ => exact fun i hi => .inl (OwnedId.of_remove hi)
  | scopeLP _ hrl ih => exact fun i hi => ih i (Release.ownedId hrl hi)

/-- A panicking step allocates nothing: its owned trees were owned before. -/
theorem Step.ownedId_panic {P : Prog} {m m1 : Mem} {s : Stmt} (h : Step P m s (.panic m1)) :
    ∀ i, OwnedId m1 i → OwnedId m i := by
  generalize hr : Res.panic m1 = r at h
  induction h generalizing m1 with
  | seqP _ ih => exact ih hr
  | letvP _ => cases hr; exact fun i hi => hi
  | scopeP _ _ _ ih => cases hr; exact fun i hi => ih rfl i (OwnedId.of_remove hi)
  | rbindP _ _ ih => cases hr; exact fun i hi => ih rfl i (OwnedId.of_remove hi)
  | frozenP _ ih => exact ih hr
  | assignP _ => cases hr; exact fun i hi => hi
  | panic => cases hr; exact fun i hi => hi
  | waitPanic _ => cases hr; exact fun i hi => hi
  | letdP _ => cases hr; exact fun i hi => hi
  | scopeDPMoved _ _ ih => cases hr; exact fun i hi => ih rfl i (OwnedId.of_remove hi)
  | scopeLP _ hrl ih => cases hr; exact fun i hi => ih rfl i (Release.ownedId hrl hi)
  | _ => cases hr

/-! ### A3.2: where a payload's addresses come from -/

/-- An address the payload of block `k` of `B` owns. -/
def PayAt (B : Nat → Option Blk) (k i : Nat) : Prop := ∃ bl, B k = some bl ∧ i ∈ bl.tree.ids

/-- **Evaluating a right-hand side**: a payload's address afterwards was the
    same block's, or (a new block) an owned tree's. -/
theorem EvalR.payAt {m m' : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m'))
    (hb : BorFree m) : ∀ k i, PayAt m'.blk k i → PayAt m.blk k i ∨ OwnedId m i := by
  intro k i ⟨bl, hk, hi⟩
  cases h with
  | pair h1 h2 => rw [TakeVal.blk h2, TakeVal.blk h1] at hk; exact .inl ⟨bl, hk, hi⟩
  | inl h1 => rw [TakeVal.blk h1] at hk; exact .inl ⟨bl, hk, hi⟩
  | inr h1 => rw [TakeVal.blk h1] at hk; exact .inl ⟨bl, hk, hi⟩
  | pack h1 => rw [TakeVal.blk h1] at hk; exact .inl ⟨bl, hk, hi⟩
  | @arcNew t y v1 m1 h1 _ =>
    by_cases he : k = m1.nid
    · subst he
      simp [upd] at hk
      subst hk
      exact .inr ((TakeVal.ownedId h1 hb).1 i (by simpa [Blk.tree] using hi))
    · have hk' : upd m1.blk m1.nid _ k = some bl := hk
      rw [upd_ne _ _ he, TakeVal.blk h1] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | @lockNew t y v1 m1 h1 _ =>
    by_cases he : k = m1.nid
    · subst he
      simp [upd] at hk
      subst hk
      exact .inr ((TakeVal.ownedId h1 hb).1 i (by simpa [Blk.tree] using hi))
    · have hk' : upd m1.blk m1.nid _ k = some bl := hk
      rw [upd_ne _ _ he, TakeVal.blk h1] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | @cellNew t y v1 m1 h1 _ =>
    by_cases he : k = m1.nid
    · subst he
      simp [upd] at hk
      subst hk
      exact .inr ((TakeVal.ownedId h1 hb).1 i (by simpa [Blk.tree] using hi))
    · have hk' : upd m1.blk m1.nid _ k = some bl := hk
      rw [upd_ne _ _ he, TakeVal.blk h1] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | @atomic _ _ _ _ _ k0 _ _ _ _ hk0 _ _ =>
    have hk' : upd _ k0 _ k = some bl := hk
    by_cases he : k = k0
    · subst he
      simp [upd] at hk'
      subst hk'
      simp [Blk.tree] at hi
    · rw [upd_ne _ _ he] at hk'
      exact .inl ⟨bl, hk', hi⟩
  -- A3.4: a channel's payload keeps its addresses, and gains a sent value's
  -- (an owned tree's), or loses a head received
  | @chanSend _ _ _ k0 _ _ _ _ _ _ m1 _ h1 hk0 _ _ =>
    have hk' : upd m1.blk k0 _ k = some bl := hk
    rw [TakeVal.blk h1] at hk0
    by_cases he : k = k0
    · subst he
      simp [upd] at hk'
      subst hk'
      simp only [Blk.tree, Option.getD_some, ids_pair, ids_node, idsL_append, idsL_cons, idsL_nil,
        ids_int, List.append_nil, List.mem_cons, List.mem_append] at hi
      rcases hi with h | h | h | h
      · exact .inl ⟨_, hk0, by simp [Blk.tree, h]⟩
      · exact .inl ⟨_, hk0, by simp [Blk.tree, h]⟩
      · exact .inl ⟨_, hk0, by simp [Blk.tree, h]⟩
      · exact .inr ((TakeVal.ownedId h1 hb).1 i h)
    · rw [upd_ne _ _ he, TakeVal.blk h1] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | chanSendClosed _ h1 _ _ =>
    have hk' : _ = some bl := hk
    rw [TakeVal.blk h1] at hk'
    exact .inl ⟨bl, hk', hi⟩
  | @chanRecv _ _ _ k0 _ _ _ _ _ _ _ _ hk0 _ _ =>
    have hk' : upd _ k0 _ k = some bl := hk
    by_cases he : k = k0
    · subst he
      simp [upd] at hk'
      subst hk'
      simp only [Blk.tree, Option.getD_some, ids_pair, ids_node, ids_int, List.append_nil,
        List.mem_cons] at hi
      refine .inl ⟨_, hk0, ?_⟩
      simp only [Blk.tree, Option.getD_some, ids_pair, ids_node, idsL_cons, ids_int, List.append_nil,
        List.mem_cons, List.mem_append]
      rcases hi with h | h | h
      · exact .inl h
      · exact .inr (.inl h)
      · exact .inr (.inr (.inr h))
    · rw [upd_ne _ _ he] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | @chanClose _ _ k0 _ _ _ _ hk0 =>
    have hk' : upd _ k0 _ k = some bl := hk
    by_cases he : k = k0
    · subst he
      simp [upd] at hk'
      subst hk'
      exact .inl ⟨_, hk0, by simpa [Blk.tree] using hi⟩
    · rw [upd_ne _ _ he] at hk'
      exact .inl ⟨bl, hk', hi⟩
  -- A3.3: a new view owns nothing
  | @rwRead _ _ _ _ _ _ _ _ =>
    have hk' : upd m.blk m.nid _ k = some bl := hk
    by_cases he : k = m.nid
    · subst he; simp [upd] at hk'; subst hk'; simp at hi
    · rw [upd_ne _ _ he] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | _ => exact .inl ⟨bl, hk, hi⟩

/-- A lock scope's end: a payload's address afterwards was the same block's,
    or (given back) the tree of the slot the scope ends. -/
theorem Release.payAt {m m' : Mem} {k0 : Nat} {t : Ty} {x : Var} (hrl : Release m k0 t x m') :
    ∀ k i, PayAt m'.blk k i → PayAt m.blk k i ∨ OwnedId m i := by
  intro k i ⟨bl, hk, hi⟩
  cases hrl with
  | @put o v hx hg hk0 =>
    have hk' : upd _ k0 (some ⟨t, .lock, some v⟩) k = some bl := hk
    by_cases he : k = k0
    · subst he
      simp [upd] at hk'
      subst hk'
      simp only [Blk.tree, Option.getD_some] at hi
      cases o with
      | true => exact .inr (OwnedId.of_slot hx hi)
      | false =>
        cases v with
        | int n => simp [Val.ids] at hi
        | _ => simp [Giveable] at hg
    · rw [upd_ne _ _ he] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | drop _ _ _ => exact .inl ⟨bl, hk, hi⟩

/-- **A step**: a payload's address afterwards was the same block's, or an
    owned tree's (a new block's, or a lock's given back).  Not a fresh one:
    a step's fresh addresses go to its slots. -/
theorem Step.payAt {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hb : BorFree m) :
    ∀ k i, PayAt r.mem.blk k i → PayAt m.blk k i ∨ OwnedId m i := by
  induction h with
  | seqL _ ih | seqP _ ih | scopeIn _ ih | rbindIn _ ih | frozenIn _ ih | frozenP _ ih | catchIn _ ih
    | scopeDIn _ ih | scopeLIn _ ih => exact ih
  | scopeP _ _ _ ih | rbindP _ _ ih | catchP _ _ ih | scopeDP _ _ ih | scopeDPMoved _ _ ih => exact ih
  | letv _ he | letd _ he | assign _ he _ _ => exact fun k i hp => EvalR.payAt he hb k i hp
  | letcall _ _ hbp =>
    intro k i ⟨bl, hk, hi⟩
    have hk' : _ = some bl := hk
    simp only [Mem.set_blk] at hk'
    rw [BindParams.blk hbp] at hk'
    exact .inl ⟨bl, hk', hi⟩
  | callc _ _ _ _ hbp =>
    intro k i ⟨bl, hk, hi⟩
    have hk' : _ = some bl := hk
    simp only [Mem.set_blk] at hk'
    rw [BindParams.blk hbp] at hk'
    exact .inl ⟨bl, hk', hi⟩
  | push ht _ _ _ | pushRealloc ht _ _ _ | editPush ht _ _ | editPushRealloc ht _ _
    | editSet _ _ ht _ _ _ | editSetOOB _ ht _ _ _ | insert _ ht _ _ _ =>
    intro k i ⟨bl, hk, hi⟩
    rw [← TakeVal.blk ht]
    exact .inl ⟨bl, hk, hi⟩
  | @withLock a x s0 k0 t v _ hk0 _ =>
    intro k i ⟨bl, hk, hi⟩
    have hk' : upd _ k0 (some ⟨t, .lock, none⟩) k = some bl := hk
    by_cases he : k = k0
    · subst he
      simp [upd] at hk'
      subst hk'
      simp [Blk.tree] at hi
    · rw [upd_ne _ _ he] at hk'
      exact .inl ⟨bl, hk', hi⟩
  | scopeLSkip hrl => exact Release.payAt hrl
  | scopeLP hs hrl ih =>
    -- A3.3: what a panic's unwinding gives back was the thread's own
    exact fun k i hp => (Release.payAt hrl k i hp).elim (ih k i)
      (fun h => .inr (Step.ownedId_panic hs i h))
  | _ => exact fun k i h => .inl h

/-! ### Avoiding another part -/

theorem FreshFrom.mono {a2 : Nat → Bool} {n n' : Nat} (h : FreshFrom a2 n) (hn : n ≤ n') :
    FreshFrom a2 n' :=
  fun i hi => h i (Nat.le_trans hn hi)

/-- A store that owns only what `m` owned, or addresses at or past `n`,
    avoids every part that `m` avoids and that has no address at or past
    `n`. -/
theorem Avoids.mono {m m' : Mem} {a2 : Nat → Bool} {n : Nat} (hav : Avoids m a2) (hf : FreshFrom a2 n)
    (h : ∀ i, OwnedId m' i → OwnedId m i ∨ n ≤ i) : Avoids m' a2 := by
  intro i hi
  rcases h i hi with h | h
  · exact hav i h
  · exact hf i h

/-- A3.2: ... and so does one that owns besides a payload's addresses of `m`,
    when the part has none. -/
theorem Avoids.mono3 {m m' : Mem} {a2 : Nat → Bool} {n : Nat} (hav : Avoids m a2) (hf : FreshFrom a2 n)
    (hpo : PayOff m a2) (h : ∀ i, OwnedId m' i → OwnedId m i ∨ n ≤ i ∨ PayAddr m i) : Avoids m' a2 := by
  intro i hi
  rcases h i hi with h | h | h
  · exact hav i h
  · exact hf i h
  · obtain ⟨k, bl, hk, hik⟩ := h
    exact hpo i (.inl ⟨k, bl, hk, hik⟩)

theorem TakeVal.avoids {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) (hb : BorFree m)
    {a2 : Nat → Bool} (hav : Avoids m a2) : Avoids m1 a2 ∧ ∀ i ∈ v.ids, a2 i = false :=
  ⟨fun i hi => hav i ((TakeVal.ownedId h hb).2 i hi), fun i hi => hav i ((TakeVal.ownedId h hb).1 i hi)⟩

theorem EvalR.avoids {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    (hb : BorFree m) {a2 : Nat → Bool} (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) :
    Avoids m1 a2 ∧ (o = true → ∀ i ∈ v.ids, a2 i = false ∨ PayAddr m i) := by
  refine ⟨Avoids.mono hav hf (EvalR.ownedId h hb).2, fun ho i hi => ?_⟩
  rcases (EvalR.ownedId h hb).1 ho i hi with h | h | h
  · exact .inl (hav i h)
  · exact .inl (hf i h)
  · exact .inr h

theorem BindParams.avoids {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (hb : BorFree m) {a2 : Nat → Bool} (hav : Avoids m a2) :
    Avoids m' a2 :=
  fun j hj => hav j (BindParams.ownedId h hb j hj)

/-- **A step keeps avoiding** a part its start's owned trees avoid, if the
    part has no fresh address. -/
theorem Step.avoids {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hb : BorFree m)
    {a2 : Nat → Bool} (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) (hpo : PayOff m a2) : Avoids r.mem a2 :=
  Avoids.mono3 hav hf hpo (Step.ownedId h hb)

/-- A panicking step keeps avoiding every part its start's owned trees avoid. -/
theorem Step.avoids_panic {P : Prog} {m m1 : Mem} {s : Stmt} (h : Step P m s (.panic m1))
    {a2 : Nat → Bool} (hav : Avoids m a2) : Avoids m1 a2 :=
  fun i hi => hav i (Step.ownedId_panic h i hi)

end A3
