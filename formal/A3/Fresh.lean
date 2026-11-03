import A3.Frame

/-! A3.0 — what one step does to the address space: it allocates only fresh
addresses, and `nid` never goes back.  A thread's step therefore never
allocates an address another thread owns: every other thread's addresses
are below `nid`. -/

namespace A3
open A2

/-- From `m` to `m'` nothing was allocated but fresh addresses, and `nid`
    did not go back. -/
structure Grows (m m' : Mem) : Prop where
  nid   : m.nid ≤ m'.nid
  fresh : ∀ i, m'.alloc i = true → m.alloc i = true ∨ m.nid ≤ i
  /-- A3.1: the counted blocks only grow (`arcNew`); (A3.2) a lock block's
      payload may be checked out or back in (`BlkLe`). -/
  blk   : BlkLe m.blk m'.blk

theorem Grows.refl (m : Mem) : Grows m m := ⟨Nat.le_refl _, fun _ h => .inl h, BlkLe.refl _⟩

theorem Grows.trans {m1 m2 m3 : Mem} (h1 : Grows m1 m2) (h2 : Grows m2 m3) : Grows m1 m3 :=
  ⟨Nat.le_trans h1.nid h2.nid, fun i h => by
    rcases h2.fresh i h with h | h
    · exact h1.fresh i h
    · exact .inr (Nat.le_trans h1.nid h), h1.blk.trans h2.blk⟩

/-- The same address space and `nid`: a slot or `nv` changed. -/
theorem Grows.of_eq {m m' : Mem} (ha : m'.alloc = m.alloc) (hn : m'.nid = m.nid)
    (hb : m'.blk = m.blk := by rfl) : Grows m m' :=
  ⟨by rw [hn]; exact Nat.le_refl _, fun _ h => .inl (by rw [← ha]; exact h), BlkLe.of_eq hb⟩

/-- An address space that only lost addresses, `nid` as it was. -/
theorem Grows.shrink {m m' : Mem} (h : ∀ {i}, m'.alloc i = true → m.alloc i = true)
    (hn : m'.nid = m.nid) (hb : m'.blk = m.blk := by rfl) : Grows m m' :=
  ⟨by rw [hn]; exact Nat.le_refl _, fun _ hi => .inl (h hi), BlkLe.of_eq hb⟩

theorem DropSlot.le {a a' : Nat → Bool} {sl : Slot} (h : DropSlot a sl a') :
    ∀ {i}, a' i = true → a i = true := by
  intro i hi
  cases h with
  | owned hf => exact Frees.le hf hi
  | moved => exact hi
  | borrowed => exact hi

theorem TakeVal.grows {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) : Grows m m1 := by
  cases h <;> exact Grows.of_eq rfl rfl

theorem EvalR.grows {m m' : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m')) :
    Grows m m' := by
  cases h with
  | new =>
    refine ⟨(by show m.nid ≤ m.nid + 2; omega), fun i hi => ?_, BlkLe.refl _⟩
    change upd (upd m.alloc m.nid true) (m.nid + 1) true i = true at hi
    by_cases h1 : i = m.nid + 1
    · exact .inr (by omega)
    · by_cases h2 : i = m.nid
      · exact .inr (by omega)
      · simp only [upd, ite_eq_right h1, ite_eq_right h2] at hi; exact .inl hi
  | pair h1 h2 => exact (TakeVal.grows h1).trans (TakeVal.grows h2)
  | inl h1 => exact TakeVal.grows h1
  | inr h1 => exact TakeVal.grows h1
  | pack h1 => exact TakeVal.grows h1
  | arcNew h1 hfr =>
    exact (TakeVal.grows h1).trans ⟨Nat.le_succ _, fun _ hi => .inl hi, BlkLe.fresh hfr _⟩
  | lockNew h1 hfr =>
    exact (TakeVal.grows h1).trans ⟨Nat.le_succ _, fun _ hi => .inl hi, BlkLe.fresh hfr _⟩
  | cellNew h1 hfr =>
    exact (TakeVal.grows h1).trans ⟨Nat.le_succ _, fun _ hi => .inl hi, BlkLe.fresh hfr _⟩
  | atomic _ hk _ _ => exact ⟨Nat.le_refl _, fun _ hi => .inl hi, BlkLe.setLock hk _⟩
  | chanSend _ h1 hk _ _ =>
    exact (TakeVal.grows h1).trans ⟨Nat.le_refl _, fun _ hi => .inl hi, BlkLe.setLock hk _⟩
  | chanSendClosed _ h1 _ hf => exact (TakeVal.grows h1).trans (Grows.shrink (Frees.le hf) rfl)
  | chanRecv _ hk _ _ => exact ⟨Nat.le_refl _, fun _ hi => .inl hi, BlkLe.setLock hk _⟩
  | chanClose _ hk => exact ⟨Nat.le_refl _, fun _ hi => .inl hi, BlkLe.setLock hk _⟩
  | rwRead _ _ hfr => exact ⟨Nat.le_succ _, fun _ hi => .inl hi, BlkLe.fresh hfr _⟩
  | _ => exact Grows.of_eq rfl rfl

theorem BindParams.grows {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : Grows m m' := by
  induction h with
  | nil => exact Grows.refl _
  | inp _ _ _ ih => refine Grows.trans ?_ ih; exact Grows.of_eq rfl rfl
  | sink _ _ ih => refine Grows.trans ?_ ih; exact Grows.of_eq rfl rfl
  | inout _ ih => exact ih

/-- A lock scope's end, on either path, gives a payload back or drops a slot. -/
theorem Release.grows {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') : Grows m m' := by
  cases h with
  | put _ _ hk => exact ⟨Nat.le_refl _, fun _ h => .inl h, BlkLe.setLock hk _⟩
  | drop _ _ hd => exact Grows.shrink (DropSlot.le hd) rfl

/-- **A step allocates only fresh addresses**, and `nid` never goes back. -/
theorem Step.grows {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) : Grows m r.mem := by
  induction h with
  | seqSkip => exact Grows.refl _
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he => exact (EvalR.grows he).trans (Grows.of_eq rfl rfl)
  | letvP _ => exact Grows.refl _
  | letcall _ _ hb => exact (BindParams.grows hb).trans (Grows.of_eq rfl rfl)
  | scopeSkip _ hd => exact Grows.shrink (DropSlot.le hd) rfl
  | scopeIn _ ih => exact ih
  | scopeP _ _ hd ih => exact ih.trans (Grows.shrink (DropSlot.le hd) rfl)
  | rbindSkip _ => exact Grows.of_eq rfl rfl
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact ih.trans (Grows.of_eq rfl rfl)
  | frozenSkip => exact Grows.refl _
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ hd => exact (EvalR.grows he).trans (Grows.shrink (DropSlot.le hd) rfl)
  | assignP _ => exact Grows.refl _
  | iteT _ _ => exact Grows.refl _
  | iteF _ => exact Grows.refl _
  | «while» => exact Grows.refl _
  | push ht _ _ _ => exact (TakeVal.grows ht).trans (Grows.of_eq rfl rfl)
  | insert _ ht _ _ _ => exact (TakeVal.grows ht).trans (Grows.of_eq rfl rfl)
  | @pushRealloc m1 _ _ _ _ _ d _ ht _ _ _ =>
    refine (TakeVal.grows ht).trans ⟨(by show m1.nid ≤ m1.nid + 1; omega), fun i hi => ?_, BlkLe.refl _⟩
    change upd (upd m1.alloc d false) m1.nid true i = true at hi
    by_cases h1 : i = m1.nid
    · exact .inr (by omega)
    · simp only [upd, ite_eq_right h1] at hi
      by_cases h2 : i = d
      · rw [ite_eq_left h2] at hi; cases hi
      · rw [ite_eq_right h2] at hi; exact .inl hi
  | free _ hf => exact Grows.shrink (Frees.le hf) rfl
  | editPush ht _ _ => exact (TakeVal.grows ht).trans (Grows.of_eq rfl rfl)
  | @editPushRealloc m1 _ _ _ _ _ _ _ _ _ d _ ht _ _ =>
    refine (TakeVal.grows ht).trans ⟨by show m1.nid ≤ m1.nid + 1; omega, fun i hi => ?_, BlkLe.refl _⟩
    change upd (upd m1.alloc d false) m1.nid true i = true at hi
    by_cases h1 : i = m1.nid
    · exact .inr (by omega)
    · simp only [upd, ite_eq_right h1] at hi
      by_cases h2 : i = d
      · rw [ite_eq_left h2] at hi; cases hi
      · rw [ite_eq_right h2] at hi; exact .inl hi
  | editTrunc _ _ hf _ => exact Grows.shrink (FreesL.le hf) rfl
  | editSet _ _ ht _ hf _ => exact (TakeVal.grows ht).trans (Grows.shrink (Frees.le hf) rfl)
  | editSetOOB _ ht _ _ hf => exact (TakeVal.grows ht).trans (Grows.shrink (Frees.le hf) rfl)
  | panic => exact Grows.refl _
  | waitPanic _ => exact Grows.refl _
  | letrec _ _ _ => exact Grows.of_eq rfl rfl
  | catchIn _ ih => exact ih
  | catchSkip => exact Grows.refl _
  | unpair _ _ _ _ => exact Grows.of_eq rfl rfl
  | callc _ _ _ _ hb =>
    refine Grows.trans (Grows.trans ?_ (BindParams.grows hb)) (Grows.of_eq rfl rfl)
    exact Grows.of_eq rfl rfl
  | catchP _ _ ih => exact ih.trans (Grows.of_eq rfl rfl)
  | letd _ he => exact (EvalR.grows he).trans (Grows.of_eq rfl rfl)
  | letdP _ => exact Grows.refl _
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ => exact Grows.of_eq rfl rfl
  | scopeDMoved _ => exact Grows.of_eq rfl rfl
  | scopeDP _ _ ih => exact ih.trans (Grows.of_eq rfl rfl)
  | scopeDPMoved _ _ ih => exact ih.trans (Grows.of_eq rfl rfl)
  | withLock _ hk _ =>
    exact ⟨Nat.le_refl _, fun _ h => .inl h, (BlkLe.setLock hk none).trans (BlkLe.refl _)⟩
  | scopeLIn _ ih => exact ih
  | scopeLSkip hrl => exact Release.grows hrl
  | scopeLP _ hrl ih => exact ih.trans (Release.grows hrl)

/-! ### A3.6: no step writes a module global -/

theorem TakeVal.gl {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) : m1.gl = m.gl := by
  cases h <;> rfl

theorem EvalR.gl {m m' : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m')) :
    m'.gl = m.gl := by
  cases h with
  | pair h1 h2 => have h := (TakeVal.gl h2).trans (TakeVal.gl h1); exact h
  | inl h1 => have h := TakeVal.gl h1; exact h
  | inr h1 => have h := TakeVal.gl h1; exact h
  | pack h1 => have h := TakeVal.gl h1; exact h
  | arcNew h1 _ => have h := TakeVal.gl h1; exact h
  | lockNew h1 _ => have h := TakeVal.gl h1; exact h
  | cellNew h1 _ => have h := TakeVal.gl h1; exact h
  | chanSend _ h1 _ _ _ => have h := TakeVal.gl h1; exact h
  | chanSendClosed _ h1 _ _ => have h := TakeVal.gl h1; exact h
  | _ => rfl

theorem BindParams.gl {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : m'.gl = m.gl := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih => exact ih
  | sink _ _ ih => exact ih
  | inout _ ih => exact ih

theorem Release.gl {m m' : Mem} {k : Nat} {t : Ty} {x : Var} (h : Release m k t x m') : m'.gl = m.gl := by
  cases h <;> rfl

/-- **No step writes a module global** (A3.6): the globals set at start stay
    as they were made, for every thread. -/
theorem Step.gl {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) : r.mem.gl = m.gl := by
  induction h with
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he => have h := EvalR.gl he; exact h
  | letcall _ _ hb => have h := BindParams.gl hb; exact h
  | scopeIn _ ih => exact ih
  | scopeP _ _ _ ih => exact ih
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact ih
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ _ => have h := EvalR.gl he; exact h
  | push ht _ _ _ => have h := TakeVal.gl ht; exact h
  | pushRealloc ht _ _ _ => have h := TakeVal.gl ht; exact h
  | insert _ ht _ _ _ => have h := TakeVal.gl ht; exact h
  | editPush ht _ _ => have h := TakeVal.gl ht; exact h
  | editPushRealloc ht _ _ => have h := TakeVal.gl ht; exact h
  | editSet _ _ ht _ _ _ => have h := TakeVal.gl ht; exact h
  | editSetOOB _ ht _ _ _ => have h := TakeVal.gl ht; exact h
  | catchIn _ ih => exact ih
  | callc _ _ _ _ hb => have h := BindParams.gl hb; exact h
  | catchP _ _ ih => exact ih
  | letd _ he => have h := EvalR.gl he; exact h
  | scopeDIn _ ih => exact ih
  | scopeDP _ _ ih => exact ih
  | scopeDPMoved _ _ ih => exact ih
  | scopeLIn _ ih => exact ih
  | scopeLSkip hrl => have h := Release.gl hrl; exact h
  | scopeLP _ hrl ih => have h := (Release.gl hrl).trans ih; exact h
  | _ => rfl

end A3
