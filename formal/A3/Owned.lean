import A3.Rel

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
    (o = true → ∀ i ∈ v.ids, OwnedId m i ∨ m.nid ≤ i) ∧ ∀ i, OwnedId m1 i → OwnedId m i ∨ m.nid ≤ i := by
  cases h with
  | new =>
    refine ⟨fun _ i hi => .inr ?_, fun i hi => .inl hi⟩
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
    ∀ i, OwnedId r.mem i → OwnedId m i ∨ m.nid ≤ i := by
  induction h with
  | seqSkip => exact fun i hi => .inl hi
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he =>
    intro i hi
    rcases OwnedId.set_some hi with ⟨ho, hiv⟩ | hi
    · exact (EvalR.ownedId he hb).1 ho i hiv
    · exact (EvalR.ownedId he hb).2 i hi
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
    · exact (EvalR.ownedId he hb).2 i hi
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
  | pushRealloc ht hx _ _ =>
    obtain ⟨a1, b1⟩ := TakeVal.ownedId ht hb
    intro i hi
    rcases OwnedId.set_some hi with ⟨_, hiv⟩ | hi
    · rcases mem_ids_push hiv with hi | hi
      · simp only [ids_node, List.mem_cons] at hi
        rcases hi with hi | hi | hi
        · exact .inl (b1 i (OwnedId.of_slot hx (by simp [hi])))
        · subst hi; exact .inr (TakeVal.grows ht).nid
        · exact .inl (b1 i (OwnedId.of_slot hx (by simp [hi])))
      · exact .inl (a1 i hi)
    · exact .inl (b1 i hi)
  | free _ _ => exact fun i hi => .inl (OwnedId.set_none hi)
  | panic => exact fun i hi => .inl hi
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
    · exact (EvalR.ownedId he hb).2 i hi
  | letdP _ => exact fun i hi => .inl hi
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ => exact fun i hi => .inl (OwnedId.of_nv hi)
  | scopeDMoved _ => exact fun i hi => .inl (OwnedId.of_remove hi)
  | scopeDP _ _ ih => exact fun i hi => ih i (OwnedId.of_nv hi)
  | scopeDPMoved _ _ ih => exact fun i hi => ih i (OwnedId.of_remove hi)

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
  | letdP _ => cases hr; exact fun i hi => hi
  | scopeDPMoved _ _ ih => cases hr; exact fun i hi => ih rfl i (OwnedId.of_remove hi)
  | _ => cases hr

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

theorem TakeVal.avoids {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) (hb : BorFree m)
    {a2 : Nat → Bool} (hav : Avoids m a2) : Avoids m1 a2 ∧ ∀ i ∈ v.ids, a2 i = false :=
  ⟨fun i hi => hav i ((TakeVal.ownedId h hb).2 i hi), fun i hi => hav i ((TakeVal.ownedId h hb).1 i hi)⟩

theorem EvalR.avoids {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    (hb : BorFree m) {a2 : Nat → Bool} (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) :
    Avoids m1 a2 ∧ (o = true → ∀ i ∈ v.ids, a2 i = false) := by
  refine ⟨Avoids.mono hav hf (EvalR.ownedId h hb).2, fun ho i hi => ?_⟩
  rcases (EvalR.ownedId h hb).1 ho i hi with h | h
  · exact hav i h
  · exact hf i h

theorem BindParams.avoids {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (hb : BorFree m) {a2 : Nat → Bool} (hav : Avoids m a2) :
    Avoids m' a2 :=
  fun j hj => hav j (BindParams.ownedId h hb j hj)

/-- **A step keeps avoiding** a part its start's owned trees avoid, if the
    part has no fresh address. -/
theorem Step.avoids {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hb : BorFree m)
    {a2 : Nat → Bool} (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) : Avoids r.mem a2 :=
  Avoids.mono hav hf (Step.ownedId h hb)

/-- A panicking step keeps avoiding every part its start's owned trees avoid. -/
theorem Step.avoids_panic {P : Prog} {m m1 : Mem} {s : Stmt} (h : Step P m s (.panic m1))
    {a2 : Nat → Bool} (hav : Avoids m a2) : Avoids m1 a2 :=
  fun i hi => hav i (Step.ownedId_panic h i hi)

end A3
