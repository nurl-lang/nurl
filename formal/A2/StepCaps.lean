import A2.CapsEval

/-! A2 — AGORA-963 step 3: **every step keeps the closure-capture clause's
slot half at a root that is none of the running statement's killable
names.** A step stores what a right-hand side yields (`EvalR.capsInp`), a
value moved, a part of one, one lent, a block's payload (which holds no
names), or nothing; it empties or drops slots. A call binds its parameters
to its arguments' values, lent (`BindParams.slotsCaps`), and a call through
a package lends or hands over the package's environment, a part of it. The
block half comes from the next store's `MInv` (`CapsInpAt.of_slots`). -/

namespace A2

theorem SlotsCaps.remove {m : Mem} {w : Var} (h : SlotsCaps m w) (x : Var) : SlotsCaps (m.remove x) w := by
  intro y o' V hy
  by_cases hyx : y = x
  · subst hyx; simp at hy
  · simp [upd_ne _ _ hyx] at hy; exact h.slot hy

theorem SlotsCaps.set_none {m : Mem} {w : Var} (h : SlotsCaps m w) (x : Var) (o : Bool) :
    SlotsCaps (m.set x ⟨o, none⟩) w :=
  h.set (fun _ e => by cases e)

theorem BindParams.slotsCaps {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    {w : Var} (hb : BindParams m ps as base i m') (h : SlotsCaps m w) : SlotsCaps m' w := by
  induction hb with
  | nil => exact h
  | @inp m _ _ _ a _ _ _ sl v ha hl _ ih =>
    refine ih (h.set (fun V e => ?_))
    cases e
    obtain ⟨o, val⟩ := sl
    cases o <;> cases val <;> simp [lendSlot] at hl
    · subst hl; exact h.slot ha
    · subst hl; exact (h.slot ha).lend
  | sink ha _ ih => exact ih ((h.set_none _ _).set (fun V e => by cases e; exact h.slot ha))
  | inout _ ih => exact ih h

theorem res_ok {m1 : Mem} {s0 : Stmt} {w : Var} (h : SlotsCaps m1 w) :
    (∀ m' s', Res.ok m1 s0 = .ok m' s' → SlotsCaps m' w) ∧ (∀ m', Res.ok m1 s0 = .panic m' → SlotsCaps m' w) :=
  ⟨fun _ _ e => (by cases e; exact h), fun _ e => (by cases e)⟩

theorem res_panic {m1 : Mem} {w : Var} (h : SlotsCaps m1 w) :
    (∀ m' s', Res.panic m1 = .ok m' s' → SlotsCaps m' w) ∧ (∀ m', Res.panic m1 = .panic m' → SlotsCaps m' w) :=
  ⟨fun _ _ e => (by cases e), fun _ e => (by cases e; exact h)⟩

/-- **A step keeps the slot half of the clause** at a root that is none of
    the statement's killable names. -/
theorem Step.slotsCaps {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) :
    ∀ {Γ : Ctx}, MInv m Γ → ∀ {w : Var}, w ∉ s.killVars → SlotsCaps m w →
      (∀ m' s', r = .ok m' s' → SlotsCaps m' w) ∧ (∀ m', r = .panic m' → SlotsCaps m' w) := by
  induction h with
  | seqSkip => intro _ _ _ _ hc; exact res_ok hc
  | seqL _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | seqP _ ih =>
    intro Γ hM w hw hc
    exact res_panic ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl)
  | letv _ he =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := he.capsInp hM hc (fun h => hw (by simp [Stmt.killVars, h]))
    exact res_ok (hs1.set (fun V e => by cases e; exact hv))
  | letvP _ => intro _ _ _ _ hc; exact res_panic hc
  | letcall _ _ hb =>
    intro Γ hM w hw hc
    exact res_ok (((hb.slotsCaps hc).set_none _ _).set_none _ _)
  | scopeSkip _ _ => intro _ _ _ _ hc; exact res_ok ((hc.of_st rfl).remove _)
  | scopeIn _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | scopeP _ _ _ ih =>
    intro Γ hM w hw hc
    exact res_panic ((((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl).of_st rfl).remove _)
  | rbindSkip _ => intro _ _ _ _ hc; exact res_ok (hc.remove _)
  | rbindIn _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | rbindP _ _ ih =>
    intro Γ hM w hw hc
    exact res_panic (((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl).remove _)
  | frozenSkip => intro _ _ _ _ hc; exact res_ok hc
  | frozenIn _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | frozenP _ ih =>
    intro Γ hM w hw hc
    exact res_panic ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl)
  | assign _ he _ _ =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := he.capsInp hM hc (fun h => hw (by simp [Stmt.killVars, h]))
    exact res_ok (hs1.set_of hv rfl)
  | assignP _ => intro _ _ _ _ hc; exact res_panic hc
  | iteT _ _ => intro _ _ _ _ hc; exact res_ok hc
  | iteF _ => intro _ _ _ _ hc; exact res_ok hc
  | «while» => intro _ _ _ _ hc; exact res_ok hc
  | push htk hT _ _ =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := htk.capsInp hc
    exact res_ok (hs1.set (fun V e => by cases e; exact (hs1.slot hT).push hv))
  | pushRealloc htk hT _ _ =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := htk.capsInp hc
    exact res_ok (hs1.set_of ((hs1.slot hT).push hv) rfl)
  | editPush htk hno hr =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := htk.capsInp hc
    obtain ⟨hT, hN⟩ := hs1.nodeOf hno
    exact res_ok (hs1.set_of (hr.capsInp hT (hN.push hv)) rfl)
  | editPushRealloc htk hno hr =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := htk.capsInp hc
    obtain ⟨hT, hN⟩ := hs1.nodeOf hno
    exact res_ok (hs1.set_of (hr.capsInp hT (hN.push hv)) rfl)
  | editTrunc _ hno _ hr =>
    intro Γ hM w hw hc
    obtain ⟨hT, hN⟩ := hc.nodeOf hno
    exact res_ok (hc.set_of (hr.capsInp hT (hN.node_sub fun e he => List.mem_of_mem_take he)) rfl)
  | editSet hn _ htk hno _ hr =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := htk.capsInp hc
    obtain ⟨hT, hN⟩ := hs1.nodeOf hno
    refine res_ok (hs1.set_of (hr.capsInp hT (ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he)
      (fun e hc' => ?_))) rfl)
    cases hc' with
    | elem he =>
      rcases List.mem_or_eq_of_mem_set he with he | rfl
      · exact hN.child (Child.elem he)
      · exact hv
  | editSetOOB _ htk _ _ _ =>
    intro Γ hM w hw hc
    exact res_ok ((htk.capsInp hc).2.of_st rfl)
  | insert _ htk hT _ _ =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := htk.capsInp hc
    refine res_ok (hs1.set (fun V e => ?_))
    cases e
    refine ValCapsInp.of_children (fun _ _ _ _ _ he => by cases he) (fun e hc' => ?_)
    cases hc' with
    | elem he =>
      have hN := hs1.slot hT
      rcases List.mem_append.mp he with he | he
      · exact hN.child (Child.elem (List.mem_of_mem_take he))
      · rcases List.mem_cons.mp he with rfl | he
        · exact hv
        · exact hN.child (Child.elem (List.mem_of_mem_drop he))
  | withElem hn hT _ _ _ _ =>
    intro Γ hM w hw hc
    have hN := hc.slot hT
    refine res_ok ((hc.set (fun V e => ?_)).set (fun V e => ?_))
    · cases e; exact hN.node_sub fun e he => by
        rcases List.mem_append.mp he with he | he
        · exact List.mem_of_mem_take he
        · exact List.mem_of_mem_drop he
    · cases e; exact hN.child (Child.elem (List.getElem_mem hn))
  | withElemOOB _ _ _ _ => intro _ _ _ _ hc; exact res_panic hc
  | takeB hn _ hno _ hr =>
    intro Γ hM w hw hc
    obtain ⟨hT, hN⟩ := hc.nodeOf hno
    refine res_ok ((hc.set (fun V e => ?_)).set (fun V e => ?_))
    · cases e; exact hr.capsInp hT (hN.node_sub fun e he => List.mem_of_mem_eraseIdx he)
    · cases e; exact hN.child (Child.elem (List.getElem_mem hn))
  | takeBOOB _ _ _ => intro _ _ _ _ hc; exact res_panic hc
  | free _ _ => intro _ _ _ _ hc; exact res_ok ((hc.of_st rfl).set_none _ _)
  | panic => intro _ _ _ _ hc; exact res_panic hc
  | waitPanic _ => intro _ _ _ _ hc; exact res_panic hc
  | letrec _ _ _ => intro _ _ _ _ hc; exact res_ok ((hc.set_none _ _).set_none _ _)
  | catchIn _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | catchSkip => intro _ _ _ _ hc; exact res_ok hc
  | unpair hy _ _ _ =>
    intro Γ hM w hw hc
    have hP := hc.slot hy
    exact res_ok (((hc.set_none _ _).set (fun V e => by cases e; exact hP.child Child.fst)).set
      (fun V e => by cases e; exact hP.child Child.snd))
  | callc hc0 _ _ _ hb =>
    intro Γ hM w hw hc
    -- the environment, lent, was the package's
    have he : SlotsCaps (envMem _ _) w :=
      SlotsCaps.set_of hc (((hc.slot hc0).child Child.pkg).lend) rfl
    exact res_ok (((hb.slotsCaps he).set_none _ _).set_none _ _)
  | callcE hc0 _ _ _ _ =>
    intro Γ hM w hw hc
    exact res_ok ((((hc.set_none _ _).set (fun V e => by cases e; exact (hc.slot hc0).child Child.pkg)).set_none _ _).of_st rfl)
  | callcD hc0 _ _ _ _ =>
    intro Γ hM w hw hc
    exact res_ok ((((hc.set_none _ _).set (fun V e => by cases e; exact (hc.slot hc0).child Child.pkg)).set_none _ _).of_st rfl)
  | catchP _ _ ih =>
    intro Γ hM w hw hc
    exact res_ok (((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl).set
      (fun V e => by cases e; exact ValCapsInp.int _ w))
  | letd _ he =>
    intro Γ hM w hw hc
    obtain ⟨hv, hs1⟩ := he.capsInp hM hc (fun h => hw (by simp [Stmt.killVars, h]))
    exact res_ok (hs1.set (fun V e => by cases e; exact hv))
  | letdP _ => intro _ _ _ _ hc; exact res_panic hc
  | scopeDIn _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | scopeDEnd _ _ => intro _ _ _ _ hc; exact res_ok (hc.of_st rfl)
  | scopeDMoved _ => intro _ _ _ _ hc; exact res_ok (hc.remove _)
  | scopeDDrain _ => intro _ _ _ _ hc; exact res_ok (hc.of_st rfl)
  | scopeDEmpty _ => intro _ _ _ _ hc; exact res_ok hc
  | scopeDP _ _ _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl)
  | scopeDPDrain _ _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl)
  | scopeDPMoved _ _ ih =>
    intro Γ hM w hw hc
    exact res_panic (((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl).remove _)
  | withLock _ hk _ _ =>
    intro Γ hM w hw hc
    exact res_ok (SlotsCaps.set_of hc (hM.blkCapsInp w _ _ _ hk rfl) rfl)
  | scopeLIn _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | scopeLSkip hrl _ =>
    intro Γ hM w hw hc
    cases hrl with
    | put _ _ _ _ => exact res_ok ((hc.of_st rfl).remove _)
    | drop _ _ _ _ => exact res_ok ((hc.of_st rfl).remove _)
  | scopeLFail _ _ => intro _ _ _ _ hc; exact res_ok hc
  | scopeLP _ hrl ih =>
    intro Γ hM w hw hc
    have h1 := (ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl
    cases hrl with
    | put _ _ _ _ => exact res_panic ((h1.of_st rfl).remove _)
    | drop _ _ _ _ => exact res_panic ((h1.of_st rfl).remove _)
  | scopeLPD _ _ _ _ _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl)
  | reap _ hk _ =>
    intro Γ hM w hw hc
    exact res_ok (SlotsCaps.set_of hc (hM.blkCapsInp w _ _ _ hk rfl) rfl)
  | blockIn _ ih =>
    intro Γ hM w hw hc
    exact res_ok ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).1 _ _ rfl)
  | blockSkip => intro _ _ _ _ hc; exact res_ok hc
  | blockExit _ => intro _ _ _ _ hc; exact res_ok hc
  | blockP _ ih =>
    intro Γ hM w hw hc
    exact res_panic ((ih hM (fun h => hw (by simp [Stmt.killVars, h])) hc).2 _ rfl)
  | loop => intro _ _ _ _ hc; exact res_ok hc

end A2
