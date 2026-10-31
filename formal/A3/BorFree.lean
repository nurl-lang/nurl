import A3.Fresh

/-! A3.0 — a borrowed slot holds no address of its own.

A borrow is a handle (`href`, `view`), an integer, or a struct of those:
what `lendOf` makes of an owned tree.  So every address a thread's slots
name is in a tree one of its owned slots holds, and a step that packs a
borrowed value into an owned struct (`pair`, `inl`, `pack`) adds no
address to it.  This is a fact of the semantics, kept by every step; A2's
invariant says it only of the live entries. -/

namespace A3
open A2

/-- Every borrowed slot holds a value with no addresses. -/
def BorFree (m : Mem) : Prop := ∀ y v, m.st y = some ⟨false, some v⟩ → v.ids = []

theorem lendOf_ids : (v : Val) → (lendOf v).ids = []
  | .int _ => rfl
  | .node .. => rfl
  | .href _ => rfl
  | .view .. => rfl
  | .pair a b => by simp only [lendOf, Val.ids, lendOf_ids a, lendOf_ids b, List.append_nil]
  | .inl a => by simp only [lendOf, Val.ids, lendOf_ids a]
  | .inr a => by simp only [lendOf, Val.ids, lendOf_ids a]
  | .pkg _ _ _ a _ => by simp only [lendOf, Val.ids, lendOf_ids a]

/-- A slot that is owned, or borrowed with an address-free value. -/
def SlotFree (sl : Slot) : Prop := sl.own = false → ∀ v, sl.val = some v → v.ids = []

theorem BorFree.of_st {m m' : Mem} (h : BorFree m) (hst : m'.st = m.st) : BorFree m' := by
  intro y v hy; rw [hst] at hy; exact h y v hy

theorem BorFree.set {m : Mem} (h : BorFree m) (x : Var) {sl : Slot} (hsl : SlotFree sl) :
    BorFree (m.set x sl) := by
  intro y v hy
  simp only [Mem.set, upd] at hy
  by_cases hyx : y = x
  · rw [if_pos hyx] at hy; cases hy; exact hsl rfl v rfl
  · rw [if_neg hyx] at hy; exact h y v hy

theorem BorFree.remove {m : Mem} (h : BorFree m) (x : Var) : BorFree (m.remove x) := by
  intro y v hy
  simp only [Mem.remove, upd] at hy
  by_cases hyx : y = x
  · rw [if_pos hyx] at hy; cases hy
  · rw [if_neg hyx] at hy; exact h y v hy

theorem SlotFree.own (v : Option Val) : SlotFree ⟨true, v⟩ := fun h => by cases h

theorem SlotFree.none (o : Bool) : SlotFree ⟨o, none⟩ := fun _ _ h => by cases h

theorem SlotFree.ids {o : Bool} {v : Val} (h : o = false → v.ids = []) : SlotFree ⟨o, some v⟩ :=
  fun ho w hw => by cases hw; exact h ho

theorem TakeVal.borFree {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) (hb : BorFree m) :
    BorFree m1 ∧ (∀ o, m.st y = some ⟨o, some v⟩ → o = false → v.ids = []) := by
  cases h with
  | own hy =>
    refine ⟨hb.set y (SlotFree.own _), fun o ho hf => ?_⟩
    rw [hy] at ho; cases ho; cases hf
  | bor hy => exact ⟨hb, fun _ _ _ => hb y v hy⟩

/-- What `TakeVal` hands on: an owner's tree, or a borrowed (address-free) value. -/
theorem TakeVal.val {m m1 : Mem} {y : Var} {v : Val} (h : TakeVal m y v m1) (hb : BorFree m) :
    m.st y = some ⟨true, some v⟩ ∨ v.ids = [] := by
  cases h with
  | own hy => exact .inl hy
  | bor hy => exact .inr (hb y v hy)

/-- Evaluating a right-hand side keeps borrowed slots address-free, and what
    it hands back unowned has no address. -/
theorem EvalR.borFree {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (h : EvalR m r (.ok v o m1))
    (hb : BorFree m) : BorFree m1 ∧ (o = false → v.ids = []) := by
  cases h with
  | expr _ => exact ⟨hb, fun _ => rfl⟩
  | new => exact ⟨hb.of_st rfl, fun h => by cases h⟩
  | moveOwn _ => exact ⟨hb.set _ (SlotFree.own _), fun h => by cases h⟩
  | copy hy => exact ⟨hb, fun _ => hb _ _ hy⟩
  | borrowOwn _ => exact ⟨hb, fun _ => rfl⟩
  | borrowBor hy => exact ⟨hb, fun _ => hb _ _ hy⟩
  | «at» _ _ _ => exact ⟨hb, fun _ => lendOf_ids _⟩
  | view _ => exact ⟨hb, fun _ => rfl⟩
  | sat _ _ _ _ _ _ => exact ⟨hb, fun _ => lendOf_ids _⟩
  | pop _ _ _ => exact ⟨hb.set _ (SlotFree.own _), fun h => ids_nonNode h⟩
  | pair h1 h2 =>
    exact ⟨(TakeVal.borFree h2 (TakeVal.borFree h1 hb).1).1, fun h => by cases h⟩
  | fst _ => exact ⟨hb, fun _ => lendOf_ids _⟩
  | snd _ => exact ⟨hb, fun _ => lendOf_ids _⟩
  | inl h1 => exact ⟨(TakeVal.borFree h1 hb).1, fun h => by cases h⟩
  | inr h1 => exact ⟨(TakeVal.borFree h1 hb).1, fun h => by cases h⟩
  | getl _ => exact ⟨hb, fun _ => lendOf_ids _⟩
  | getr _ => exact ⟨hb, fun _ => lendOf_ids _⟩
  | takel _ => exact ⟨hb.set _ (SlotFree.own _), fun h => ids_nonNode h⟩
  | taker _ => exact ⟨hb.set _ (SlotFree.own _), fun h => ids_nonNode h⟩
  | pack h1 => exact ⟨(TakeVal.borFree h1 hb).1, fun h => by cases h⟩

theorem lendSlot_ids {m : Mem} (hb : BorFree m) {a : Var} {sl : Slot} {v : Val} (ha : m.st a = some sl)
    (hl : lendSlot sl = some v) : v.ids = [] := by
  rcases sl with ⟨o, w⟩
  cases o <;> cases w <;> simp [lendSlot] at hl
  · subst hl; exact hb a _ ha
  · subst hl; exact lendOf_ids _

theorem BindParams.borFree {m m' : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat}
    (h : BindParams m ps as base i m') (hb : BorFree m) : BorFree m' := by
  induction h with
  | nil => exact hb
  | inp ha hl _ ih => exact ih (hb.set _ (SlotFree.ids fun _ => lendSlot_ids hb ha hl))
  | sink _ _ ih => exact ih ((hb.set _ (SlotFree.own _)).set _ (SlotFree.own _))
  | inout _ ih => exact ih hb

theorem envMem_borFree {m : Mem} (hb : BorFree m) (env : Val) : BorFree (envMem m env) :=
  (hb.set m.nv (SlotFree.ids fun _ => lendOf_ids env)).of_st rfl

/-- **A step keeps every borrowed slot address-free.** -/
theorem Step.borFree {P : Prog} {m : Mem} {s : Stmt} {r : Res} (h : Step P m s r) (hb : BorFree m) :
    BorFree r.mem := by
  induction h with
  | seqSkip => exact hb
  | seqL _ ih => exact ih
  | seqP _ ih => exact ih
  | letv _ he =>
    have := EvalR.borFree he hb
    exact this.1.set _ (SlotFree.ids this.2)
  | letvP _ => exact hb
  | letcall _ _ hbp =>
    exact (((BindParams.borFree hbp hb).set _ (SlotFree.none _)).set _ (SlotFree.none _)).of_st rfl
  | scopeSkip _ _ => exact (hb.of_st rfl).remove _
  | scopeIn _ ih => exact ih
  | scopeP _ _ _ ih => exact (ih.of_st rfl).remove _
  | rbindSkip _ => exact hb.remove _
  | rbindIn _ ih => exact ih
  | rbindP _ _ ih => exact ih.remove _
  | frozenSkip => exact hb
  | frozenIn _ ih => exact ih
  | frozenP _ ih => exact ih
  | assign _ he _ _ =>
    have := EvalR.borFree he hb
    exact (this.1.of_st rfl).set _ (SlotFree.ids this.2)
  | assignP _ => exact hb
  | iteT _ _ => exact hb
  | iteF _ => exact hb
  | «while» => exact hb
  | push ht _ _ _ => exact (TakeVal.borFree ht hb).1.set _ (SlotFree.own _)
  | pushRealloc ht _ _ _ => exact (((TakeVal.borFree ht hb).1).of_st rfl).set _ (SlotFree.own _)
  | free _ _ => exact (hb.of_st rfl).set _ (SlotFree.own _)
  | panic => exact hb
  | letrec _ _ _ => exact ((hb.set _ (SlotFree.none _)).set _ (SlotFree.none _)).of_st rfl
  | catchIn _ ih => exact ih
  | catchSkip => exact hb
  | unpair _ _ _ _ =>
    refine ((hb.set _ (SlotFree.own _)).set _ (SlotFree.ids ids_nonNode)).set _ (SlotFree.ids ids_nonNode)
  | callc _ _ _ _ hbp =>
    exact (((BindParams.borFree hbp (envMem_borFree hb _)).set _ (SlotFree.none _)).set _ (SlotFree.none _)).of_st rfl
  | catchP _ _ ih => exact ih.set _ (SlotFree.ids fun _ => rfl)
  | letd _ he =>
    have := EvalR.borFree he hb
    exact this.1.set _ (SlotFree.ids this.2)
  | letdP _ => exact hb
  | scopeDIn _ ih => exact ih
  | scopeDEnd _ => exact hb.of_st rfl
  | scopeDMoved _ => exact hb.remove _
  | scopeDP _ _ ih => exact ih.of_st rfl
  | scopeDPMoved _ _ ih => exact ih.remove _

end A3
