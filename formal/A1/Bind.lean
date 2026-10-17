import A1.Call

/-! A1 — the memory a call's parameter binding produces. -/

namespace A1

/-- The slots after binding the parameters, read off the store before. -/
def bindSt (m0 : Mem) : List (PMode × Ty) → List Var → Nat → Nat → (Var → Option Slot) → Var → Option Slot
  | (.inp, _) :: ps, a :: as, base, i, st =>
      bindSt m0 ps as base (i + 1) (upd st (base + i) (some ⟨false, (m0.st a).bind lendSlot⟩))
  | (.sink, _) :: ps, a :: as, base, i, st =>
      bindSt m0 ps as base (i + 1)
        (upd (upd st a (some ⟨true, none⟩)) (base + i) (some ⟨true, (m0.st a).bind Slot.val⟩))
  | (.inout _, _) :: ps, _ :: as, base, i, st => bindSt m0 ps as base (i + 1) st
  | _, _, _, _, st => st

theorem bind_spec {m0 : Mem} :
    ∀ {m m1 : Mem} {ps : List (PMode × Ty)} {as : List Var} {base i : Nat},
      BindParams m ps as base i m1 →
      (∀ a ∈ as, a < base) →
      (∀ (k k' : Nat) (a : Var), k < k' → (∃ t, ps[k]? = some (PMode.sink, t)) → as[k]? = some a → as[k']? ≠ some a) →
      (∀ a ∈ as, m.st a = m0.st a) →
      m1.alloc = m.alloc ∧ m1.nid = m.nid ∧ m1.nv = m.nv ∧ m1.st = bindSt m0 ps as base i m.st := by
  intro m m1 ps as base i hb
  induction hb with
  | nil => intro _ _ _; exact ⟨rfl, rfl, rfl, by simp [bindSt]⟩
  | @inp m m' t ps a as base i sl v hsl hlv _ ih =>
    intro hlt hd hsame
    have hlt' : ∀ a' ∈ as, a' < base := fun a' h => hlt a' (by simp [h])
    have hd' : ∀ (k k' : Nat) (a' : Var), k < k' → (∃ t, ps[k]? = some (PMode.sink, t)) → as[k]? = some a' →
        as[k']? ≠ some a' :=
      fun (k k' : Nat) (a' : Var) hk h1 h2 => by
        have := hd (k + 1) (k' + 1) a' (by omega) (by simpa using h1) (by simpa using h2)
        simpa using this
    have hsame' : ∀ a' ∈ as, (m.set (base + i) ⟨false, some v⟩).st a' = m0.st a' := by
      intro a' ha'
      have hne : a' ≠ base + i := fun he => by have h1 := vlt (hlt' a' ha'); have h2 := veq he; omega
      simp [upd_ne _ _ hne, hsame a' (by simp [ha'])]
    obtain ⟨h1, h2, h3, h4⟩ := ih hlt' hd' hsame'
    refine ⟨h1, h2, h3, ?_⟩
    rw [h4]; simp only [bindSt, Mem.set_st]
    congr 2
    rw [← hsame a (by simp), hsl]; simp [hlv]
  | @sink m m' t ps a as base i v hsl _ ih =>
    intro hlt hd hsame
    have hlt' : ∀ a' ∈ as, a' < base := fun a' h => hlt a' (by simp [h])
    have hd' : ∀ (k k' : Nat) (a' : Var), k < k' → (∃ t, ps[k]? = some (PMode.sink, t)) → as[k]? = some a' →
        as[k']? ≠ some a' :=
      fun (k k' : Nat) (a' : Var) hk h1 h2 => by
        have := hd (k + 1) (k' + 1) a' (by omega) (by simpa using h1) (by simpa using h2)
        simpa using this
    have hsame' : ∀ a' ∈ as, ((m.set a ⟨true, none⟩).set (base + i) ⟨true, some v⟩).st a' = m0.st a' := by
      intro a' ha'
      have hne : a' ≠ base + i := fun he => by have h1 := vlt (hlt' a' ha'); have h2 := veq he; omega
      have hna : a' ≠ a := by
        intro he; subst he
        obtain ⟨k', hk', hka⟩ := List.getElem_of_mem ha'
        exact hd 0 (k' + 1) a' (by omega) ⟨t, by simp⟩ (by simp) (by simp [List.getElem?_eq_getElem hk', hka])
      simp [upd_ne _ _ hne, upd_ne _ _ hna, hsame a' (by simp [ha'])]
    obtain ⟨h1, h2, h3, h4⟩ := ih hlt' hd' hsame'
    refine ⟨h1, h2, h3, ?_⟩
    rw [h4]; simp only [bindSt, Mem.set_st]
    congr 2
    rw [← hsame a (by simp), hsl]; rfl
  | @inout m m' b t ps a as base i _ ih =>
    intro hlt hd hsame
    have hlt' : ∀ a' ∈ as, a' < base := fun a' h => hlt a' (by simp [h])
    have hd' : ∀ (k k' : Nat) (a' : Var), k < k' → (∃ t, ps[k]? = some (PMode.sink, t)) → as[k]? = some a' →
        as[k']? ≠ some a' :=
      fun (k k' : Nat) (a' : Var) hk h1 h2 => by
        have := hd (k + 1) (k' + 1) a' (by omega) (by simpa using h1) (by simpa using h2)
        simpa using this
    obtain ⟨h1, h2, h3, h4⟩ := ih hlt' hd' (fun a' ha' => hsame a' (by simp [ha']))
    exact ⟨h1, h2, h3, by rw [h4]; rfl⟩

/-- A slot the binding does not write keeps its contents. -/
theorem bindSt_other {m0 : Mem} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (base i : Nat) (st : Var → Option Slot) (y : Var),
      (∀ (k : Nat) (p : PMode × Ty), ps[k]? = some p → (∀ b, p.1 ≠ .inout b) → y ≠ base + i + k) →
      (∀ (k : Nat) (t : Ty), ps[k]? = some (PMode.sink, t) → as[k]? ≠ some y) →
      bindSt m0 ps as base i st y = st y := by
  intro ps
  induction ps with
  | nil => intro as base i st y _ _; cases as <;> rfl
  | cons p ps ih =>
    intro as base i st y hy hs
    obtain ⟨pm, t⟩ := p
    cases as with
    | nil => cases pm <;> rfl
    | cons a as =>
      have hy' : ∀ (k : Nat) (p : PMode × Ty), ps[k]? = some p → (∀ b, p.1 ≠ .inout b) → y ≠ base + (i + 1) + k := by
        intro k p hk hp
        have := hy (k + 1) p (by simpa using hk) hp
        rwa [show base + i + (k + 1) = base + (i + 1) + k by omega] at this
      have hs' : ∀ (k : Nat) (t : Ty), ps[k]? = some (PMode.sink, t) → as[k]? ≠ some y :=
        fun (k : Nat) (t : Ty) hk => by have := hs (k + 1) t (by simpa using hk); simpa using this
      have h0 : (∀ b, pm ≠ .inout b) → y ≠ base + i := by
        intro hb; have := hy 0 (pm, t) (by simp) hb; simpa using this
      cases pm with
      | inp =>
        simp only [bindSt]; rw [ih as base (i + 1) _ y hy' hs']
        exact upd_ne _ _ (h0 (fun b h => by cases h))
      | sink =>
        simp only [bindSt]; rw [ih as base (i + 1) _ y hy' hs']
        have hya : y ≠ a := fun he => hs 0 t (by simp) (by simp [he])
        rw [upd_ne _ _ (h0 (fun b h => by cases h)), upd_ne _ _ hya]
      | inout b => simp only [bindSt]; exact ih as base (i + 1) _ y hy' hs'

theorem bindSt_slot {m0 : Mem} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (base i : Nat) (st : Var → Option Slot),
      (∀ a ∈ as, a < base) →
      ∀ (k : Nat) (a : Var) (pm : PMode) (t : Ty), ps[k]? = some (pm, t) → as[k]? = some a →
        (pm = .inp → bindSt m0 ps as base i st (base + i + k) = some ⟨false, (m0.st a).bind lendSlot⟩) ∧
        (pm = .sink → bindSt m0 ps as base i st (base + i + k) = some ⟨true, (m0.st a).bind Slot.val⟩) := by
  intro ps
  induction ps with
  | nil => intro as base i st _ k a pm t hk; simp at hk
  | cons p ps ih =>
    intro as base i st hlt k a pm t hk ha
    obtain ⟨pm0, t0⟩ := p
    cases as with
    | nil => simp at ha
    | cons a0 as =>
      have hlt' : ∀ a' ∈ as, a' < base := fun a' h => hlt a' (by simp [h])
      cases k with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq, Prod.mk.injEq] at hk ha
        obtain ⟨rfl, rfl⟩ := hk; subst ha
        -- later writes are to other slots or to arguments
        have hrest : ∀ st', bindSt m0 ps as base (i + 1) st' (base + i + 0) = st' (base + i + 0) := by
          intro st'
          refine bindSt_other ps as base (i + 1) st' _ (fun k p _ _ he => by have := veq he; omega)
            (fun k t' hk' he => ?_)
          have hk2 : k < as.length := (List.getElem?_eq_some_iff.mp he).1
          have := vlt (hlt' _ (List.mem_of_getElem? he)); omega
        cases pm0 with
        | inp => refine ⟨fun _ => ?_, fun h => (by cases h)⟩; simp only [bindSt]; rw [hrest]; simp
        | sink => refine ⟨fun h => (by cases h), fun _ => ?_⟩; simp only [bindSt]; rw [hrest]; simp
        | inout b => exact ⟨fun h => (by cases h), fun h => (by cases h)⟩
      | succ k =>
        have hk' : ps[k]? = some (pm, t) := by simpa using hk
        have ha' : as[k]? = some a := by simpa using ha
        have := fun st' => ih as base (i + 1) st' hlt' k a pm t hk' ha'
        rw [show base + i + (k + 1) = base + (i + 1) + k by omega]
        cases pm0 with
        | inp => exact this _
        | sink => exact this _
        | inout b => exact this _

theorem bindSt_arg {m0 : Mem} :
    ∀ (ps : List (PMode × Ty)) (as : List Var) (base i : Nat) (st : Var → Option Slot),
      (∀ a ∈ as, a < base) →
      ∀ (k : Nat) (a : Var) (t : Ty), ps[k]? = some (PMode.sink, t) → as[k]? = some a →
        (∀ (k' : Nat) (t' : Ty), k < k' → ps[k']? = some (PMode.sink, t') → as[k']? ≠ some a) →
        bindSt m0 ps as base i st a = some ⟨true, none⟩ := by
  intro ps
  induction ps with
  | nil => intro as base i st _ k a t hk; simp at hk
  | cons p ps ih =>
    intro as base i st hlt k a t hk ha hu
    obtain ⟨pm0, t0⟩ := p
    cases as with
    | nil => simp at ha
    | cons a0 as =>
      have hlt' : ∀ a' ∈ as, a' < base := fun a' h => hlt a' (by simp [h])
      cases k with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq, Prod.mk.injEq] at hk ha
        obtain ⟨rfl, rfl⟩ := hk; subst ha
        simp only [bindSt]
        have hab := vlt (hlt _ (by simp : a0 ∈ a0 :: as))
        rw [bindSt_other ps as base (i + 1) _ a0 (fun k p _ _ he => by have := veq he; omega)
          (fun k' t' hk' => by have := hu (k' + 1) t' (by omega) (by simpa using hk'); simpa using this)]
        rw [upd_ne _ _ (fun he => by have := veq he; omega)]
        simp
      | succ k =>
        have hk' : ps[k]? = some (PMode.sink, t) := by simpa using hk
        have ha' : as[k]? = some a := by simpa using ha
        have hu' : ∀ (k' : Nat) (t' : Ty), k < k' → ps[k']? = some (PMode.sink, t') → as[k']? ≠ some a := by
          intro k' t' hkk h1
          have := hu (k' + 1) t' (by omega) (by simpa using h1); simpa using this
        cases pm0 with
        | inp => exact ih as base (i + 1) _ hlt' k a t hk' ha' hu'
        | sink => exact ih as base (i + 1) _ hlt' k a t hk' ha' hu'
        | inout b => exact ih as base (i + 1) _ hlt' k a t hk' ha' hu'

end A1
