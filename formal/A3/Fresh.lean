import A3.Frame

/-! A3.0 — what one step does to the address space: it allocates only fresh
addresses, and `nid` never goes back.  A thread's step therefore never
allocates an address another thread owns: every other thread's addresses
are below `nid`. -/

namespace A3
open A2

/-- The memory a step leaves. -/
def _root_.A2.Res.mem : Res → Mem
  | .ok m _ => m
  | .panic m => m

/-- From `m` to `m'` nothing was allocated but fresh addresses, and `nid`
    did not go back. -/
structure Grows (m m' : Mem) : Prop where
  nid   : m.nid ≤ m'.nid
  fresh : ∀ i, m'.alloc i = true → m.alloc i = true ∨ m.nid ≤ i

theorem Grows.refl (m : Mem) : Grows m m := ⟨Nat.le_refl _, fun _ h => .inl h⟩

theorem Grows.trans {m1 m2 m3 : Mem} (h1 : Grows m1 m2) (h2 : Grows m2 m3) : Grows m1 m3 :=
  ⟨Nat.le_trans h1.nid h2.nid, fun i h => by
    rcases h2.fresh i h with h | h
    · exact h1.fresh i h
    · exact .inr (Nat.le_trans h1.nid h)⟩

/-- The same address space and `nid`: a slot or `nv` changed. -/
theorem Grows.of_eq {m m' : Mem} (ha : m'.alloc = m.alloc) (hn : m'.nid = m.nid) : Grows m m' :=
  ⟨by rw [hn]; exact Nat.le_refl _, fun _ h => .inl (by rw [← ha]; exact h)⟩

/-- An address space that only lost addresses, `nid` as it was. -/
theorem Grows.shrink {m m' : Mem} (h : ∀ {i}, m'.alloc i = true → m.alloc i = true)
    (hn : m'.nid = m.nid) : Grows m m' :=
  ⟨by rw [hn]; exact Nat.le_refl _, fun _ hi => .inl (h hi)⟩

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
    refine ⟨by show m.nid ≤ m.nid + 2; omega, fun i hi => ?_⟩
    change upd (upd m.alloc m.nid true) (m.nid + 1) true i = true at hi
    by_cases h1 : i = m.nid + 1
    · exact .inr (by omega)
    · by_cases h2 : i = m.nid
      · exact .inr (by omega)
      · simp only [upd, if_neg h1, if_neg h2] at hi; exact .inl hi
  | pair h1 h2 => exact (TakeVal.grows h1).trans (TakeVal.grows h2)
  | inl h1 => exact TakeVal.grows h1
  | inr h1 => exact TakeVal.grows h1
  | pack h1 => exact TakeVal.grows h1
  | _ => exact Grows.of_eq rfl rfl

theorem BindParams.grows {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : Grows m m' := by
  induction h with
  | nil => exact Grows.refl _
  | inp _ _ _ ih => refine Grows.trans ?_ ih; exact Grows.of_eq rfl rfl
  | sink _ _ ih => refine Grows.trans ?_ ih; exact Grows.of_eq rfl rfl
  | inout _ ih => exact ih

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
  | @pushRealloc m1 _ _ _ _ _ d _ ht _ _ _ =>
    refine (TakeVal.grows ht).trans ⟨by show m1.nid ≤ m1.nid + 1; omega, fun i hi => ?_⟩
    change upd (upd m1.alloc d false) m1.nid true i = true at hi
    by_cases h1 : i = m1.nid
    · exact .inr (by omega)
    · simp only [upd, if_neg h1] at hi
      by_cases h2 : i = d
      · rw [if_pos h2] at hi; cases hi
      · rw [if_neg h2] at hi; exact .inl hi
  | free _ hf => exact Grows.shrink (Frees.le hf) rfl
  | panic => exact Grows.refl _
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

end A3
