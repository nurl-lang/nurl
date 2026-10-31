import A3.Owned

/-! A3.0 — a thread's step leaves the other threads' addresses as they were.

What a step frees is in a tree the thread owns, and what it allocates is
fresh; a part the thread's trees avoid, with no fresh address, is neither. -/

namespace A3
open A2

theorem DropSlot.keep {a a' a2 : Nat → Bool} {sl : Slot} (h : DropSlot a sl a')
    (hav : ∀ T, sl = ⟨true, some T⟩ → ∀ i ∈ T.ids, a2 i = false) : ∀ i, a2 i = true → a' i = a i := by
  intro i hi
  cases h with
  | owned hf =>
    exact Frees.other hf (fun hm => by have := hav _ rfl i hm; rw [hi] at this; cases this)
  | moved => rfl
  | borrowed => rfl

theorem BindParams.alloc_eq {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') : m'.alloc = m.alloc := by
  induction h with
  | nil => rfl
  | inp _ _ _ ih => exact ih
  | sink _ _ ih => exact ih
  | inout _ ih => exact ih

theorem EvalR.keep {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    {a2 : Nat → Bool} (hf : FreshFrom a2 m.nid) : ∀ i, a2 i = true → m1.alloc i = m.alloc i := by
  intro i hi
  cases h with
  | new =>
    show upd (upd m.alloc m.nid true) (m.nid + 1) true i = m.alloc i
    have h1 : i ≠ m.nid + 1 := fun he => by rw [hf i (by omega)] at hi; cases hi
    have h2 : i ≠ m.nid := fun he => by rw [hf i (by omega)] at hi; cases hi
    simp only [upd, ite_eq_right h1, ite_eq_right h2]
  | pair h1 h2 => rw [TakeVal.alloc h2, TakeVal.alloc h1]
  | inl h1 => rw [TakeVal.alloc h1]
  | inr h1 => rw [TakeVal.alloc h1]
  | pack h1 => rw [TakeVal.alloc h1]
  | _ => rfl

/-- **A step leaves another part as it was.** -/
theorem Step.keep {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hb : BorFree m)
    {a2 : Nat → Bool} (hav : Avoids m a2) (hf : FreshFrom a2 m.nid) :
    ∀ i, a2 i = true → r.mem.alloc i = m.alloc i := by
  induction h with
  | seqSkip => intro _ _; rfl
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he => exact EvalR.keep he hf
  | letvP _ => intro _ _; rfl
  | letcall _ _ hbp => intro i _; exact congrFun (BindParams.alloc_eq hbp) i
  | scopeSkip hx hd =>
    exact DropSlot.keep hd (fun T hT i hi => hav i (OwnedId.of_slot (hx.trans (congrArg some hT)) hi))
  | scopeIn _ ih => exact ih
  | scopeP hs hx hd ih =>
    intro i hi
    have hav1 := Step.avoids_panic hs hav
    rw [← ih i hi]
    exact DropSlot.keep hd (fun T hT j hj => hav1 j (OwnedId.of_slot (hx.trans (congrArg some hT)) hj)) i hi
  | rbindSkip _ => intro _ _; rfl
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact ih
  | frozenSkip => intro _ _; rfl
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he hx hd =>
    intro i hi
    have hav1 := (EvalR.avoids he hb hav hf).1
    show _ = m.alloc i
    rw [← EvalR.keep he hf i hi]
    exact DropSlot.keep hd (fun T hT j hj => hav1 j (OwnedId.of_slot (hx.trans (congrArg some hT)) hj)) i hi
  | assignP _ => intro _ _; rfl
  | iteT _ _ => intro _ _; rfl
  | iteF _ => intro _ _; rfl
  | «while» => intro _ _; rfl
  | push ht _ _ _ => intro i _; exact congrFun (TakeVal.alloc ht) i
  | @pushRealloc m1 x _ _ _ _ d _ ht hx _ _ =>
    intro i hi
    have hav1 := (TakeVal.avoids ht hb hav).1
    have hn : m1.nid = m.nid := by cases ht <;> rfl
    show upd (upd m1.alloc d false) m1.nid true i = m.alloc i
    have h1 : i ≠ m1.nid := fun he => by rw [hf i (by omega)] at hi; cases hi
    have h2 : i ≠ d := fun he => by
      have := hav1 d ⟨x, _, hx, by simp [Val.ids]⟩
      rw [← he, hi] at this; cases this
    simp only [upd, ite_eq_right h1, ite_eq_right h2]
    exact congrFun (TakeVal.alloc ht) i
  | free hx hf' =>
    intro i hi
    exact Frees.other hf' (fun hm => by have := hav i ⟨_, _, hx, hm⟩; rw [hi] at this; cases this)
  | panic => intro _ _; rfl
  | letrec _ _ _ => intro _ _; rfl
  | catchIn _ ih => exact ih
  | catchSkip => intro _ _; rfl
  | unpair _ _ _ _ => intro _ _; rfl
  | callc _ _ _ _ hbp => intro i _; exact congrFun (BindParams.alloc_eq hbp) i
  | catchP _ _ ih => exact ih
  | letd _ he => exact EvalR.keep he hf
  | letdP _ => intro _ _; rfl
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ => intro _ _; rfl
  | scopeDMoved _ => intro _ _; rfl
  | scopeDP _ _ ih => exact ih
  | scopeDPMoved _ _ ih => exact ih

end A3
