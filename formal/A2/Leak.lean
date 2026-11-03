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

/-- Dropping a slot releases its tree; every other live address keeps its
    owner, or (A3.1) is a payload's (no owned tree holds one). -/
theorem covers_drop {m : Mem} (hc : Covers m) {x : Var} {sl : Slot} (hx : m.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') :
    ∀ i, a' i = true → (∃ o U, o ≠ x ∧ OwnedAt m o U ∧ i ∈ U.ids) ∨ PayAddr m i := by
  intro i hi
  cases hd with
  | owned hf =>
    rename_i t
    have hni : i ∉ t.ids := fun h => by rw [hf.freed h] at hi; cases hi
    rcases hc i (hf.le hi) with ⟨o, U, hU, hiU⟩ | hp
    · refine Or.inl ⟨o, U, fun e => ?_, hU, hiU⟩
      subst e; unfold OwnedAt at hU; rw [hx] at hU; cases hU; exact hni hiU
    · exact Or.inr hp
  | moved =>
    rcases hc i hi with ⟨o, U, hU, hiU⟩ | hp
    · exact Or.inl ⟨o, U, fun e => (by subst e; unfold OwnedAt at hU; rw [hx] at hU; cases hU), hU, hiU⟩
    · exact Or.inr hp
  | borrowed =>
    rcases hc i hi with ⟨o, U, hU, hiU⟩ | hp
    · exact Or.inl ⟨o, U, fun e => (by subst e; unfold OwnedAt at hU; rw [hx] at hU; cases hU), hU, hiU⟩
    · exact Or.inr hp

theorem covers_remove {m : Mem} (hc : Covers m) {x : Var} {sl : Slot} (hx : m.st x = some sl)
    {a' : Nat → Bool} (hd : DropSlot m.alloc sl a') : Covers ({ m with alloc := a' }.remove x) := by
  intro i hi
  rcases covers_drop hc hx hd i hi with ⟨o, U, hox, hU, hiU⟩ | hp
  · exact Or.inl ⟨o, U, ownedAt_remove.mpr ⟨hox, hU⟩, hiU⟩
  · exact Or.inr hp

theorem covers_remove_bor {m : Mem} (hc : Covers m) {p : Var} {w : Option Val}
    (hp : m.st p = some ⟨false, w⟩) : Covers (m.remove p) := by
  have := covers_remove hc hp DropSlot.borrowed
  exact this

/-- A slot that owns nothing is set to another that owns nothing. -/
theorem covers_set_none {m : Mem} (hc : Covers m) {x : Var} (hx : ∀ T, ¬ OwnedAt m x T)
    {sl : Slot} (_hsl : ∀ T, sl ≠ ⟨true, some T⟩) : Covers (m.set x sl) := by
  intro i hi
  rcases hc i hi with ⟨o, U, hU, hiU⟩ | hp
  · exact Or.inl ⟨o, U, ownedAt_set.mpr (Or.inr ⟨fun e => by subst e; exact hx U hU, hU⟩), hiU⟩
  · exact Or.inr hp

/-- Covered, except for the value in flight `v`, which the binding that
    takes it will own when `o` says it is owned. -/
def CoversBut (m : Mem) (v : Val) (o : Bool) : Prop :=
  ∀ i, m.alloc i = true → Covered m i ∨ (o = true ∧ i ∈ v.ids)

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
        exact Or.inl (hc i hi)
  | @moveOwn y _ hy =>
    rcases hc i hi with ⟨o', U, hU, hiU⟩ | hp
    · by_cases hoy : o' = y
      · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU; exact Or.inr ⟨rfl, hiU⟩
      · exact Or.inl (Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩)
    · exact Or.inl (Or.inr hp)
  | copy _ => exact Or.inl (hc i hi)
  | borrowOwn _ => exact Or.inl (hc i hi)
  | borrowBor _ => exact Or.inl (hc i hi)
  | «at» _ _ _ => exact Or.inl (hc i hi)
  | view _ => exact Or.inl (hc i hi)
  | sat _ _ _ _ _ _ => exact Or.inl (hc i hi)
  | pop hy ha hb =>
    rename_i y t c d es
    rcases hc i hi with ⟨o', U, hU, hiU⟩ | hp
    · by_cases hoy : o' = y
      · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU
        simp only [ids_node, List.mem_cons, idsL_append, List.mem_append, idsL_cons, idsL_nil,
          List.append_nil] at hiU
        rcases hiU with h | h | h | h
        · exact Or.inl (Or.inl ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), by simp [h]⟩)
        · exact Or.inl (Or.inl ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), by simp [h]⟩)
        · exact Or.inl (Or.inl ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), by simp [h]⟩)
        · cases hn : v.owns
          · rw [ids_nonNode hn] at h; cases h
          · exact Or.inr ⟨rfl, h⟩
      · exact Or.inl (Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩)
    · exact Or.inl (Or.inr hp)
  | pair h1 h2 =>
    rw [h2.alloc, h1.alloc] at hi
    rcases hc i hi with ⟨o', U, hU, hiU⟩ | hp
    · rcases h1.owned hU with hU1 | ⟨_, rfl⟩
      · rcases h2.owned hU1 with hU2 | ⟨_, rfl⟩
        · exact Or.inl (Or.inl ⟨o', U, hU2, hiU⟩)
        · exact Or.inr ⟨rfl, by simp [hiU]⟩
      · exact Or.inr ⟨rfl, by simp [hiU]⟩
    · refine Or.inl (Or.inr ?_)
      unfold PayAddr; rw [h2.blk, h1.blk]; exact hp
  | fst _ => exact Or.inl (hc i hi)
  | snd _ => exact Or.inl (hc i hi)
  | inl h1 | inr h1 | pack h1 =>
    rw [h1.alloc] at hi
    rcases hc i hi with ⟨o', U, hU, hiU⟩ | hp
    · rcases h1.owned hU with hU1 | ⟨_, rfl⟩
      · exact Or.inl (Or.inl ⟨o', U, hU1, hiU⟩)
      · exact Or.inr ⟨rfl, by simpa using hiU⟩
    · refine Or.inl (Or.inr ?_)
      unfold PayAddr; rw [h1.blk]; exact hp
  | getl _ | getr _ => exact Or.inl (hc i hi)
  | @takel y v hy | @taker y v hy =>
    rcases hc i hi with ⟨o', U, hU, hiU⟩ | hp
    · by_cases hoy : o' = y
      · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU
        have hv : v.owns = true := by
          cases h : v.owns
          · simp only [ids_inl, ids_inr] at hiU; rw [ids_nonNode h] at hiU; simp at hiU
          · rfl
        exact Or.inr ⟨hv, by simpa using hiU⟩
      · exact Or.inl (Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩)
    · exact Or.inl (Or.inr hp)
  | @arcNew t y w m1 htk hfr =>
    -- A3.1: what `arc_new` moves into the new block is the block's payload
    have hi' : m.alloc i = true := by rw [← htk.alloc]; exact hi
    have hgrow : ∀ {j}, PayAddr m1 j →
        PayAddr { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .arc, some w⟩) } j := by
      intro j ⟨k, bl, hk, hj⟩
      have hne : k ≠ m1.nid := fun e => by rw [e, hfr] at hk; cases hk
      exact ⟨k, bl, by simpa [upd, hne] using hk, hj⟩
    rcases hc i hi' with ⟨o', U, hU, hiU⟩ | hp
    · rcases htk.owned hU with hU1 | ⟨_, hUw⟩
      · exact Or.inl (Or.inl ⟨o', U, hU1, hiU⟩)
      · exact Or.inl (Or.inr ⟨m1.nid, ⟨t, .arc, some w⟩, by simp [upd], by rw [← hUw]; exact hiU⟩)
    · refine Or.inl (Or.inr (hgrow ?_))
      unfold PayAddr; rw [htk.blk]; exact hp
  | arcClone _ | arcGet _ _ => exact Or.inl (hc i hi)

/-- The binding that takes the value in flight owns it. -/
theorem covers_take {m : Mem} {v : Val} {o : Bool} (hc : CoversBut m v o) {x : Var}
    (hx : ∀ T, ¬ OwnedAt m x T) : Covers (m.set x ⟨o, some v⟩) := by
  intro i hi
  rcases hc i hi with (⟨o', U, hU, hiU⟩ | hp) | ⟨rfl, hiv⟩
  · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨fun e => by subst e; exact hx U hU, hU⟩), hiU⟩
  · exact Or.inr hp
  · exact Or.inl ⟨x, v, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), hiv⟩

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
  rcases hc i hi0 with (⟨o', U, hU, hiU⟩ | hp) | ⟨rfl, hiv⟩
  · by_cases hox : o' = x
    · subst hox
      unfold OwnedAt at hU; rw [hx] at hU; cases hU
      cases hd with
      | owned hf => rw [hf.freed hiU] at hi; cases hi
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩
  · exact Or.inr hp
  · exact Or.inl ⟨x, v, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), hiv⟩

theorem covers_free {m : Mem} (hc : Covers m) {x : Var} {t : Val}
    (hx : m.st x = some ⟨true, some t⟩) {a' : Nat → Bool} (hf : Frees m.alloc t a') :
    Covers ({ m with alloc := a' }.set x ⟨true, none⟩) := by
  intro i hi
  rcases covers_drop hc hx (DropSlot.owned hf) i hi with ⟨o, U, hox, hU, hiU⟩ | hp
  · exact Or.inl ⟨o, U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩
  · exact Or.inr hp

theorem covers_takeVal {m m1 : Mem} (hc : Covers m) {y : Var} {v : Val} (ht : TakeVal m y v m1) :
    CoversBut m1 v true := by
  intro i hi
  cases ht with
  | own hy =>
    rcases hc i hi with ⟨o', U, hU, hiU⟩ | hp
    · by_cases hoy : o' = y
      · subst hoy; unfold OwnedAt at hU; rw [hy] at hU; cases hU; exact Or.inr ⟨rfl, hiU⟩
      · exact Or.inl (Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoy, hU⟩), hiU⟩)
    · exact Or.inl (Or.inr hp)
  | bor _ => exact Or.inl (hc i hi)

theorem covers_push {m : Mem} {v : Val} (hc : CoversBut m v true) {x : Var} {t : Ty} {c d : Nat}
    {es : List Val} (hx : m.st x = some ⟨true, some (.node t c d es)⟩) :
    Covers (m.set x ⟨true, some (.node t c d (es ++ [v]))⟩) := by
  intro i hi
  rcases hc i hi with (⟨o', U, hU, hiU⟩ | hp) | ⟨_, hiv⟩
  · by_cases hox : o' = x
    · subst hox; unfold OwnedAt at hU; rw [hx] at hU; cases hU
      refine Or.inl ⟨o', _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), ?_⟩
      simp only [ids_node, List.mem_cons, idsL_append, List.mem_append] at hiU ⊢
      rcases hiU with h | h | h
      · exact Or.inl h
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr (Or.inl h))
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩
  · exact Or.inr hp
  · refine Or.inl ⟨x, _, ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩), ?_⟩
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
  · subst hn; exact Or.inl ⟨x, _, hmine, by simp⟩
  rw [upd_ne _ _ hn] at hi
  by_cases hd : i = d
  · subst hd; simp [upd] at hi
  rw [upd_ne _ _ hd] at hi
  rcases hc i hi with (⟨o', U, hU, hiU⟩ | hp) | ⟨_, hiv⟩
  · by_cases hox : o' = x
    · subst hox; unfold OwnedAt at hU; rw [hx] at hU; cases hU
      refine Or.inl ⟨o', _, hmine, ?_⟩
      simp only [ids_node, List.mem_cons, idsL_append, List.mem_append] at hiU ⊢
      rcases hiU with h | h | h
      · exact Or.inl h
      · exact absurd h hd
      · exact Or.inr (Or.inr (Or.inl h))
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hox, hU⟩), hiU⟩
  · exact Or.inr hp
  · exact Or.inl ⟨x, _, hmine, by simp [idsL_append, hiv]⟩

/-! ### Agora #295: a node of an owned tree rewritten in place -/

theorem covers_editPush {m : Mem} {v : Val} (hc : CoversBut m v true) {o : Var} {T T' : Val}
    {t : Ty} {c d : Nat} {es : List Val} (hT : m.st o = some ⟨true, some T⟩)
    (hr : Repl (.node t c d es) (.node t c d (es ++ [v])) T T') :
    Covers (m.set o ⟨true, some T'⟩) := by
  obtain ⟨A, B, h1, h2⟩ := hr.ids_split
  have hmine : OwnedAt (m.set o ⟨true, some T'⟩) o T' := ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩)
  intro i hi
  rcases hc i hi with (⟨o', U, hU, hiU⟩ | hp) | ⟨_, hiv⟩
  · by_cases hoo : o' = o
    · subst hoo; unfold OwnedAt at hU; rw [hT] at hU; cases hU
      refine Or.inl ⟨o', T', hmine, ?_⟩
      rw [h1] at hiU; rw [h2]
      simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.mem_append,
        List.mem_cons] at hiU ⊢
      rcases hiU with (h | h | h | h) | h
      · exact Or.inl (Or.inl h)
      · exact Or.inl (Or.inr (Or.inl h))
      · exact Or.inl (Or.inr (Or.inr (Or.inl h)))
      · exact Or.inl (Or.inr (Or.inr (Or.inr (Or.inl h))))
      · exact Or.inr h
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoo, hU⟩), hiU⟩
  · exact Or.inr hp
  · refine Or.inl ⟨o, T', hmine, ?_⟩
    rw [h2]
    simp [idsL_append, hiv]

theorem covers_editPushRealloc {m : Mem} {v : Val} (hc : CoversBut m v true) {o : Var}
    {T T' : Val} {t : Ty} {c d : Nat} {es : List Val} (hT : m.st o = some ⟨true, some T⟩)
    (hr : Repl (.node t c d es) (.node t c m.nid (es ++ [v])) T T') :
    Covers ({ m with alloc := upd (upd m.alloc d false) m.nid true, nid := m.nid + 1 }.set o
      ⟨true, some T'⟩) := by
  obtain ⟨A, B, h1, h2⟩ := hr.ids_split
  have hmine : OwnedAt ({ m with alloc := upd (upd m.alloc d false) m.nid true, nid := m.nid + 1 }.set o
      ⟨true, some T'⟩) o T' := ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩)
  intro i hi
  simp only [Mem.set_alloc] at hi
  by_cases hn : i = m.nid
  · subst hn; exact Or.inl ⟨o, T', hmine, by rw [h2]; simp⟩
  rw [upd_ne _ _ hn] at hi
  by_cases hd : i = d
  · subst hd; simp [upd] at hi
  rw [upd_ne _ _ hd] at hi
  rcases hc i hi with (⟨o', U, hU, hiU⟩ | hp) | ⟨_, hiv⟩
  · by_cases hoo : o' = o
    · subst hoo; unfold OwnedAt at hU; rw [hT] at hU; cases hU
      refine Or.inl ⟨o', T', hmine, ?_⟩
      rw [h1] at hiU; rw [h2]
      simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.mem_append,
        List.mem_cons] at hiU ⊢
      rcases hiU with (h | h | h | h) | h
      · exact Or.inl (Or.inl h)
      · exact Or.inl (Or.inr (Or.inl h))
      · exact absurd h hd
      · exact Or.inl (Or.inr (Or.inr (Or.inr (Or.inl h))))
      · exact Or.inr h
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoo, hU⟩), hiU⟩
  · exact Or.inr hp
  · refine Or.inl ⟨o, T', hmine, ?_⟩
    rw [h2]
    simp [idsL_append, hiv]

theorem covers_editTrunc {m : Mem} (hc : Covers m) {o : Var} {T T' : Val} {t : Ty} {c d n : Nat}
    {es : List Val} (hT : m.st o = some ⟨true, some T⟩) {a' : Nat → Bool}
    (hf : FreesL m.alloc (es.drop n) a')
    (hr : Repl (.node t c d es) (.node t c d (es.take n)) T T') :
    Covers ({ m with alloc := a' }.set o ⟨true, some T'⟩) := by
  obtain ⟨A, B, h1, h2⟩ := hr.ids_split
  have hmine : OwnedAt ({ m with alloc := a' }.set o ⟨true, some T'⟩) o T' :=
    ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩)
  intro i hi
  simp only [Mem.set_alloc] at hi
  have hi0 : m.alloc i = true := hf.le hi
  have hnd : i ∉ idsL (es.drop n) := fun h => by rw [hf.freed h] at hi; cases hi
  rcases hc i hi0 with ⟨o', U, hU, hiU⟩ | hp
  · by_cases hoo : o' = o
    · subst hoo; unfold OwnedAt at hU; rw [hT] at hU; cases hU
      refine Or.inl ⟨o', T', hmine, ?_⟩
      rw [h1] at hiU; rw [h2]
      have hes : idsL es = idsL (es.take n) ++ idsL (es.drop n) := by
        rw [← idsL_append, List.take_append_drop]
      simp only [ids_node, hes, List.mem_append, List.mem_cons] at hiU ⊢
      rcases hiU with (h | h | h | h | h) | h
      · exact Or.inl (Or.inl h)
      · exact Or.inl (Or.inr (Or.inl h))
      · exact Or.inl (Or.inr (Or.inr (Or.inl h)))
      · exact Or.inl (Or.inr (Or.inr (Or.inr h)))
      · exact absurd h hnd
      · exact Or.inr h
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoo, hU⟩), hiU⟩
  · exact Or.inr hp

/-- An element set: the value taken in replaces the element it frees. -/
theorem covers_editSet {m : Mem} {v : Val} (hc : CoversBut m v true) {o : Var} {T T' : Val}
    {t : Ty} {c d n : Nat} {es : List Val} (hT : m.st o = some ⟨true, some T⟩) (hn : n < es.length)
    {a' : Nat → Bool} (hf : Frees m.alloc es[n] a')
    (hr : Repl (.node t c d es) (.node t c d (es.set n v)) T T') :
    Covers ({ m with alloc := a' }.set o ⟨true, some T'⟩) := by
  obtain ⟨A, B, h1, h2⟩ := hr.ids_split
  obtain ⟨he, he'⟩ := idsL_set hn v
  have hmine : OwnedAt ({ m with alloc := a' }.set o ⟨true, some T'⟩) o T' :=
    ownedAt_set.mpr (Or.inl ⟨rfl, rfl⟩)
  intro i hi
  simp only [Mem.set_alloc] at hi
  have hi0 : m.alloc i = true := hf.le hi
  have hnd : i ∉ es[n].ids := fun h => by rw [hf.freed h] at hi; cases hi
  rcases hc i hi0 with (⟨o', U, hU, hiU⟩ | hp) | ⟨_, hiv⟩
  · by_cases hoo : o' = o
    · subst hoo; unfold OwnedAt at hU; rw [hT] at hU; cases hU
      refine Or.inl ⟨o', T', hmine, ?_⟩
      rw [h1] at hiU; rw [h2]
      simp only [ids_node, he, he', List.mem_append, List.mem_cons] at hiU ⊢
      rcases hiU with (h | h | h | ((h | h) | h)) | h
      · exact Or.inl (Or.inl h)
      · exact Or.inl (Or.inr (Or.inl h))
      · exact Or.inl (Or.inr (Or.inr (Or.inl h)))
      · exact Or.inl (Or.inr (Or.inr (Or.inr (Or.inl (Or.inl h)))))
      · exact absurd h hnd
      · exact Or.inl (Or.inr (Or.inr (Or.inr (Or.inr h))))
      · exact Or.inr h
    · exact Or.inl ⟨o', U, ownedAt_set.mpr (Or.inr ⟨hoo, hU⟩), hiU⟩
  · exact Or.inr hp
  · refine Or.inl ⟨o, T', hmine, ?_⟩
    rw [h2]
    simp [he', hiv]

/-- An element set out of range: the value taken in is freed. -/
theorem covers_editSetOOB {m : Mem} {v : Val} (hc : CoversBut m v true) {a' : Nat → Bool}
    (hf : Frees m.alloc v a') : Covers { m with alloc := a' } := by
  intro i hi
  rcases hc i (hf.le hi) with (⟨o', U, hU, hiU⟩ | hp) | ⟨_, hiv⟩
  · exact Or.inl ⟨o', U, hU, hiU⟩
  · exact Or.inr hp
  · have := hf.freed hiv
    change a' i = true at hi
    rw [this] at hi; cases hi

end A2
