import A2.Steps

/-! A2 — nothing leaks: every live address is in a tree some binding owns
(`Covers`), and every step keeps it so. -/

namespace A2

mutual
theorem Frees.le {a a' : Nat → Bool} {T : Val} (h : Frees a T a') :
    ∀ {i : Nat}, a' i = true → a i = true := by
  intro i hi
  match h with
  | .int => exact hi
  | .view => exact hi
  | .arc => exact hi
  | @Frees.node _ _ _ c d _ _ _ hl =>
    have := FreesL.le hl hi
    by_cases hd : i = d
    · subst hd; simp [upd] at this
    · rw [upd_ne _ _ hd] at this
      by_cases hc : i = c
      · subst hc; simp [upd] at this
      · rwa [upd_ne _ _ hc] at this
  | .pair h1 h2 => exact Frees.le h1 (Frees.le h2 hi)
  | .inl h1 => exact Frees.le h1 hi
  | .inr h1 => exact Frees.le h1 hi
  | .pkg h1 => exact Frees.le h1 hi
theorem FreesL.le {a a' : Nat → Bool} {es : List Val} (h : FreesL a es a') :
    ∀ {i : Nat}, a' i = true → a i = true := by
  intro i hi
  match h with
  | .nil => exact hi
  | .cons h1 h2 => exact Frees.le h1 (FreesL.le h2 hi)
end

mutual
theorem Frees.freed {a a' : Nat → Bool} {T : Val} (h : Frees a T a') :
    ∀ {i : Nat}, i ∈ T.ids → a' i = false := by
  intro i hi
  match h with
  | .int => simp at hi
  | .view => simp at hi
  | @Frees.node _ _ _ c d _ _ _ hl =>
    simp only [ids_node, List.mem_cons] at hi
    rcases hi with rfl | rfl | hi
    · cases h' : a' i with
      | false => rfl
      | true =>
        have := FreesL.le hl h'
        by_cases hcd : i = d
        · rw [hcd] at this; simp [upd] at this
        · rw [upd_ne _ _ hcd] at this; simp [upd] at this
    · cases h' : a' i with
      | false => rfl
      | true => have := FreesL.le hl h'; simp [upd] at this
    · exact FreesL.freed hl hi
  | .pair h1 h2 =>
    simp only [ids_pair, List.mem_append] at hi
    rcases hi with hi | hi
    · cases h' : a' i with
      | false => rfl
      | true => have := Frees.le h2 h'; rw [Frees.freed h1 hi] at this; cases this
    · exact Frees.freed h2 hi
  | .inl h1 => exact Frees.freed h1 (by simpa using hi)
  | .inr h1 => exact Frees.freed h1 (by simpa using hi)
  | .pkg h1 => exact Frees.freed h1 (by simpa using hi)
theorem FreesL.freed {a a' : Nat → Bool} {es : List Val} (h : FreesL a es a') :
    ∀ {i : Nat}, i ∈ idsL es → a' i = false := by
  intro i hi
  match h with
  | .nil => simp at hi
  | @FreesL.cons _ a1 _ _ _ h1 h2 =>
    simp only [idsL_cons, List.mem_append] at hi
    rcases hi with hi | hi
    · cases h' : a' i with
      | false => rfl
      | true => have := FreesL.le h2 h'; rw [Frees.freed h1 hi] at this; cases this
    · exact FreesL.freed h2 hi
end

/-! ### What each change of memory does to `Covers` -/

theorem ids_nonNode {v : Val} (h : v.owns = false) : v.ids = [] := by
  cases v <;> simp_all [Val.owns]

theorem TakeVal.alloc {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1) : m1.alloc = m.alloc := by
  cases ht <;> rfl

/-- Taking a value out of a binding: every other tree stays owned. -/
theorem TakeVal.owned {m m1 : Mem} {y : Var} {v : Val} (ht : TakeVal m y v m1) {o : Var} {U : Val}
    (hU : OwnedAt m o U) : OwnedAt m1 o U ∨ (o = y ∧ U = v) := by
  cases ht with
  | own hy =>
    by_cases hoy : o = y
    · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU; exact Or.inr ⟨rfl, rfl⟩
    · exact Or.inl (ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩))
  | bor _ => exact Or.inl hU

/-- Dropping a slot releases its tree; every other live address keeps its owner. -/
theorem covers_drop {m : Mem} (hc : Covers m) {x : Var} {sl : Slot} (hx : m.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') :
    ∀ i, a' i = true → ∃ o U, o ≠ x ∧ OwnedAt m o U ∧ i ∈ U.ids := by
  intro i hi
  cases hd with
  | owned hf =>
    rename_i t
    have hni : i ∉ t.ids := fun h => by rw [hf.freed h] at hi; cases hi
    obtain ⟨o, U, hU, hiU⟩ := hc i (hf.le hi)
    refine ⟨o, U, fun e => ?_, hU, hiU⟩
    subst e; unfold OwnedAt at hU; rw [hx] at hU; cases hU; exact hni hiU
  | moved =>
    obtain ⟨o, U, hU, hiU⟩ := hc i hi
    exact ⟨o, U, fun e => (by subst e; unfold OwnedAt at hU; rw [hx] at hU; cases hU), hU, hiU⟩
  | borrowed =>
    obtain ⟨o, U, hU, hiU⟩ := hc i hi
    exact ⟨o, U, fun e => (by subst e; unfold OwnedAt at hU; rw [hx] at hU; cases hU), hU, hiU⟩

theorem covers_remove {m : Mem} (hc : Covers m) {x : Var} {sl : Slot} (hx : m.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') : Covers ({ m with alloc := a' }.remove x) := by
  intro i hi
  obtain ⟨o, U, hox, hU, hiU⟩ := covers_drop hc hx hd i hi
  exact ⟨o, U, ownedAt_remove.mpr ⟨hox, hU⟩, hiU⟩

theorem covers_remove_bor {m : Mem} (hc : Covers m) {p : Var} {w : Option Val}
    (hp : m.st p = some ⟨false, w⟩) : Covers (m.remove p) := by
  have := covers_remove hc hp DropSlot.borrowed
  exact this

/-- A slot that owns nothing is set to another that owns nothing. -/
theorem covers_set_none {m : Mem} (hc : Covers m) {x : Var} (hx : ∀ T, ¬ OwnedAt m x T)
    {sl : Slot} (_hsl : ∀ T, sl ≠ ⟨true, some T⟩) : Covers (m.set x sl) := by
  intro i hi
  obtain ⟨o, U, hU, hiU⟩ := hc i hi
  exact ⟨o, U, ownedAt_set.mpr (Or.inr ⟨fun e => by subst e; exact hx U hU, hU⟩), hiU⟩

/-- Covered, except for the value in flight `v`, which the binding that
    takes it will own when `o` says it is owned. -/
def CoversBut (m : Mem) (v : Val) (o : Bool) : Prop :=
  ∀ i, m.alloc i = true → (∃ x t, OwnedAt m x t ∧ i ∈ t.ids) ∨ (o = true ∧ i ∈ v.ids)

theorem covers_evalR {m m1 : Mem} {r : Rhs} {v : Val} {o : Bool} (hc : Covers m)
    (he : EvalR m r (.ok v o m1)) : CoversBut m1 v o := by
  intro i hi
  cases he with
  | expr _ => exact Or.inl (hc i hi)
  | new =>
    simp only at hi
    by_cases h1 : i = m.nid + 1
    · subst h1; exact Or.inr ⟨rfl, by simp⟩
    · rw [upd_ne _ _ h1] at hi
      by_cases h0 : i = m.nid
      · subst h0; exact Or.inr ⟨rfl, by simp⟩
      · rw [upd_ne _ _ h0] at hi
        obtain ⟨o', U, hU, hiU⟩ := hc i hi
        exact Or.inl ⟨o', U, hU, hiU⟩
  | @moveOwn y _ hy =>
    obtain ⟨o', U, hU, hiU⟩ := hc i hi
    by_cases hoy : o' = y
    · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU; exact Or.inr ⟨rfl, hiU⟩
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩
  | copy _ => exact Or.inl (hc i hi)
  | borrowOwn _ => exact Or.inl (hc i hi)
  | borrowBor _ => exact Or.inl (hc i hi)
  | «at» _ _ _ => exact Or.inl (hc i hi)
  | view _ => exact Or.inl (hc i hi)
  | sat _ _ _ _ _ _ => exact Or.inl (hc i hi)
  | pop hy ha hb =>
    rename_i y t c d es
    obtain ⟨o', U, hU, hiU⟩ := hc i hi
    by_cases hoy : o' = y
    · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU
      simp only [ids_node, List.mem_cons, idsL_append, List.mem_append, idsL_cons, idsL_nil,
        List.append_nil] at hiU
      rcases hiU with h | h | h | h
      · exact Or.inl ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), by simp [h]⟩
      · exact Or.inl ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), by simp [h]⟩
      · exact Or.inl ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), by simp [h]⟩
      · cases hn : v.owns
        · rw [ids_nonNode hn] at h; cases h
        · exact Or.inr ⟨rfl, h⟩
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩
  | pair h1 h2 =>
    rw [h2.alloc, h1.alloc] at hi
    obtain ⟨o', U, hU, hiU⟩ := hc i hi
    rcases h1.owned hU with hU1 | ⟨_, rfl⟩
    · rcases h2.owned hU1 with hU2 | ⟨_, rfl⟩
      · exact Or.inl ⟨o', U, hU2, hiU⟩
      · exact Or.inr ⟨rfl, by simp [hiU]⟩
    · exact Or.inr ⟨rfl, by simp [hiU]⟩
  | fst _ => exact Or.inl (hc i hi)
  | snd _ => exact Or.inl (hc i hi)
  | inl h1 | inr h1 | pack h1 =>
    rw [h1.alloc] at hi
    obtain ⟨o', U, hU, hiU⟩ := hc i hi
    rcases h1.owned hU with hU1 | ⟨_, rfl⟩
    · exact Or.inl ⟨o', U, hU1, hiU⟩
    · exact Or.inr ⟨rfl, by simpa using hiU⟩
  | getl _ | getr _ => exact Or.inl (hc i hi)
  | @takel y v hy | @taker y v hy =>
    obtain ⟨o', U, hU, hiU⟩ := hc i hi
    by_cases hoy : o' = y
    · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU
      have hv : v.owns = true := by
        cases h : v.owns
        · simp only [ids_inl, ids_inr] at hiU; rw [ids_nonNode h] at hiU; simp at hiU
        · rfl
      exact Or.inr ⟨hv, by simpa using hiU⟩
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩

/-- The binding that takes the value in flight owns it. -/
theorem covers_take {m : Mem} {v : Val} {o : Bool} (hc : CoversBut m v o) {x : Var}
    (hx : ∀ T, ¬ OwnedAt m x T) : Covers (m.set x ⟨o, some v⟩) := by
  intro i hi
  rcases hc i hi with ⟨o', U, hU, hiU⟩ | ⟨rfl, hiv⟩
  · exact ⟨o', U, ownedAt_set.mpr (Or.inr ⟨fun e => by subst e; exact hx U hU, hU⟩), hiU⟩
  · exact ⟨x, v, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), hiv⟩

/-- An assignment: the old value is dropped, the new one taken. -/
theorem covers_assign {m : Mem} {v : Val} {o : Bool} (hc : CoversBut m v o) {x : Var} {sl : Slot}
    (hx : m.st x = some sl) {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') :
    Covers ({ m with alloc := a' }.set x ⟨o, some v⟩) := by
  intro i hi
  simp only [Mem.set_alloc] at hi
  have hi0 : m.alloc i = true := by
    cases hd with
    | owned hf => exact hf.le hi
    | moved => exact hi
    | borrowed => exact hi
  rcases hc i hi0 with ⟨o', U, hU, hiU⟩ | ⟨rfl, hiv⟩
  · by_cases hox : o' = x
    · subst hox
      unfold OwnedAt at hU; rw [hx] at hU; cases hU
      cases hd with
      | owned hf => rw [hf.freed hiU] at hi; cases hi
    · exact ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩
  · exact ⟨x, v, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), hiv⟩

theorem covers_free {m : Mem} (hc : Covers m) {x : Var} {t : Val}
    (hx : m.st x = some ⟨true, some t⟩) {a' : Nat → Bool} (hf : Frees m.alloc t a') :
    Covers ({ m with alloc := a' }.set x ⟨true, none⟩) := by
  intro i hi
  obtain ⟨o, U, hox, hU, hiU⟩ := covers_drop hc hx (DropSlot.owned hf) i hi
  exact ⟨o, U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩

theorem covers_takeVal {m m1 : Mem} (hc : Covers m) {y : Var} {v : Val} (ht : TakeVal m y v m1) :
    CoversBut m1 v true := by
  intro i hi
  cases ht with
  | own hy =>
    obtain ⟨o', U, hU, hiU⟩ := hc i hi
    by_cases hoy : o' = y
    · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU; exact Or.inr ⟨rfl, hiU⟩
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩
  | bor _ => exact Or.inl (hc i hi)

theorem covers_push {m : Mem} {v : Val} (hc : CoversBut m v true) {x : Var} {t : Ty} {c d : Nat}
    {es : List Val} (hx : m.st x = some ⟨true, some (.node t c d es)⟩) :
    Covers (m.set x ⟨true, some (.node t c d (es ++ [v]))⟩) := by
  intro i hi
  rcases hc i hi with ⟨o', U, hU, hiU⟩ | ⟨_, hiv⟩
  · by_cases hox : o' = x
    · subst hox; unfold OwnedAt at hU; rw [hx] at hU; cases hU
      refine ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), ?_⟩
      simp only [ids_node, List.mem_cons, idsL_append, List.mem_append] at hiU ⊢
      rcases hiU with h | h | h
      · exact Or.inl h
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr (Or.inl h))
    · exact ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩
  · refine ⟨x, _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), ?_⟩
    simp [idsL_append, hiv]

theorem covers_pushRealloc {m : Mem} {v : Val} (hc : CoversBut m v true) {x : Var} {t : Ty}
    {c d : Nat} {es : List Val} (hx : m.st x = some ⟨true, some (.node t c d es)⟩) :
    Covers ({ m with alloc := upd (upd m.alloc d false) m.nid true, nid := m.nid + 1 }.set x
      ⟨true, some (.node t c m.nid (es ++ [v]))⟩) := by
  intro i hi
  simp only [Mem.set_alloc] at hi
  have hmine : OwnedAt ({ m with alloc := upd (upd m.alloc d false) m.nid true, nid := m.nid + 1 }.set x
      ⟨true, some (.node t c m.nid (es ++ [v]))⟩) x (.node t c m.nid (es ++ [v])) :=
    ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩)
  by_cases hn : i = m.nid
  · subst hn; exact ⟨x, _, hmine, by simp⟩
  rw [upd_ne _ _ hn] at hi
  by_cases hd : i = d
  · subst hd; simp [upd] at hi
  rw [upd_ne _ _ hd] at hi
  rcases hc i hi with ⟨o', U, hU, hiU⟩ | ⟨_, hiv⟩
  · by_cases hox : o' = x
    · subst hox; unfold OwnedAt at hU; rw [hx] at hU; cases hU
      refine ⟨o', _, hmine, ?_⟩
      simp only [ids_node, List.mem_cons, idsL_append, List.mem_append] at hiU ⊢
      rcases hiU with h | h | h
      · exact Or.inl h
      · exact absurd h hd
      · exact Or.inr (Or.inr (Or.inl h))
    · exact ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩
  · exact ⟨x, _, hmine, by simp [idsL_append, hiv]⟩

end A2
