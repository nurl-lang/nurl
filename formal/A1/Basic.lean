import A1.Invariant

/-! A1 — basic facts: updates, trees and their addresses. -/

namespace A1

@[simp] theorem upd_same {α : Type} (f : Nat → α) (k : Nat) (v : α) : upd f k v k = v := by
  simp [upd]

@[simp] theorem upd_ne {α : Type} (f : Nat → α) {k i : Nat} (v : α) (h : i ≠ k) :
    upd f k v i = f i := by
  simp [upd, h]

theorem upd_apply {α : Type} (f : Nat → α) (k : Nat) (v : α) (i : Nat) :
    upd f k v i = if i = k then v else f i := rfl

@[simp] theorem Mem.set_st (m : Mem) (x : Var) (s : Slot) :
    (m.set x s).st = upd m.st x (some s) := rfl
@[simp] theorem Mem.set_alloc (m : Mem) (x : Var) (s : Slot) : (m.set x s).alloc = m.alloc := rfl
@[simp] theorem Mem.set_nid (m : Mem) (x : Var) (s : Slot) : (m.set x s).nid = m.nid := rfl
@[simp] theorem Mem.set_nv (m : Mem) (x : Var) (s : Slot) : (m.set x s).nv = m.nv := rfl
@[simp] theorem Mem.remove_st (m : Mem) (x : Var) : (m.remove x).st = upd m.st x none := rfl
@[simp] theorem Mem.remove_alloc (m : Mem) (x : Var) : (m.remove x).alloc = m.alloc := rfl
@[simp] theorem Mem.remove_nid (m : Mem) (x : Var) : (m.remove x).nid = m.nid := rfl
@[simp] theorem Mem.remove_nv (m : Mem) (x : Var) : (m.remove x).nv = m.nv := rfl

/-! ### Addresses of a tree -/

@[simp] theorem ids_node (t : Ty) (c d : Nat) (es : List Val) :
    (Val.node t c d es).ids = c :: d :: idsL es := by simp [Val.ids]
@[simp] theorem ids_int (n : Nat) : (Val.int n).ids = [] := by simp [Val.ids]
@[simp] theorem ids_view (d o l : Nat) : (Val.view d o l).ids = [] := by simp [Val.ids]
@[simp] theorem ids_href (c : Nat) : (Val.href c).ids = [] := by simp [Val.ids]
@[simp] theorem idsL_nil : idsL [] = [] := by simp [idsL]
@[simp] theorem idsL_cons (e : Val) (es : List Val) : idsL (e :: es) = e.ids ++ idsL es := by
  simp [idsL]

theorem idsL_append (a b : List Val) : idsL (a ++ b) = idsL a ++ idsL b := by
  induction a with
  | nil => simp
  | cons x xs ih => simp [ih]

theorem mem_idsL {e : Val} {es : List Val} (h : e ∈ es) {i : Nat} (hi : i ∈ e.ids) :
    i ∈ idsL es := by
  induction es with
  | nil => simp at h
  | cons x xs ih =>
    simp only [idsL_cons, List.mem_append]
    rcases List.mem_cons.mp h with rfl | h
    · exact Or.inl hi
    · exact Or.inr (ih h)

theorem mem_idsL_iff {es : List Val} {i : Nat} : i ∈ idsL es ↔ ∃ e ∈ es, i ∈ e.ids := by
  induction es with
  | nil => simp
  | cons x xs ih => simp [ih]

theorem Sub.ids {a b : Val} (h : Sub a b) : ∀ i ∈ a.ids, i ∈ b.ids := by
  induction h with
  | refl => exact fun i hi => hi
  | child he _ ih =>
    intro i hi
    simp only [ids_node, List.mem_cons]
    exact Or.inr (Or.inr (mem_idsL he (ih i hi)))

theorem Sub.trans {a b c : Val} (h1 : Sub a b) (h2 : Sub b c) : Sub a c := by
  induction h2 with
  | refl => exact h1
  | child he _ ih => exact Sub.child he ih

theorem Below.sub {n t : Val} (h : Below n t) : Sub n t := by
  obtain ⟨ty, c, d, es, e, rfl, he, hs⟩ := h
  exact Sub.child he hs

theorem Below.of_sub_below {a b c : Val} (h1 : Sub a b) (h2 : Below b c) : Below a c := by
  obtain ⟨ty, c', d, es, e, rfl, he, hs⟩ := h2
  exact ⟨ty, c', d, es, e, rfl, he, h1.trans hs⟩

theorem Sub.of_below_sub {a b c : Val} (h1 : Below a b) (h2 : Sub b c) : Below a c := by
  induction h2 with
  | refl => exact h1
  | child he _ ih => exact ⟨_, _, _, _, _, rfl, he, ih.sub⟩

theorem nodup_idsL_same {es : List Val} (hn : (idsL es).Nodup) {e1 e2 : Val}
    (h1 : e1 ∈ es) (h2 : e2 ∈ es) {i : Nat} (hi1 : i ∈ e1.ids) (hi2 : i ∈ e2.ids) : e1 = e2 := by
  induction es with
  | nil => simp at h1
  | cons x xs ih =>
    simp only [idsL_cons, List.nodup_append] at hn
    obtain ⟨hx, hxs, hdis⟩ := hn
    rcases List.mem_cons.mp h1 with k1 | k1 <;> rcases List.mem_cons.mp h2 with k2 | k2
    · rw [k1, k2]
    · subst k1; exact absurd rfl (hdis i hi1 i (mem_idsL k2 hi2))
    · subst k2; exact absurd rfl (hdis i hi2 i (mem_idsL k1 hi1))
    · exact ih hxs k1 k2

theorem nodup_of_mem_idsL {es : List Val} (hn : (idsL es).Nodup) {e : Val} (he : e ∈ es) :
    e.ids.Nodup := by
  induction es with
  | nil => simp at he
  | cons x xs ih =>
    simp only [idsL_cons, List.nodup_append] at hn
    rcases List.mem_cons.mp he with he | he
    · subst he; exact hn.1
    · exact ih hn.2.1 he

theorem Sub.cases' {v t : Val} (h : Sub v t) :
    v = t ∨ ∃ ty c d es e, t = .node ty c d es ∧ e ∈ es ∧ Sub v e := by
  cases h with
  | refl => exact Or.inl rfl
  | child he hs => exact Or.inr ⟨_, _, _, _, _, rfl, he, hs⟩

/-- The head addresses of a node: its control block and its buffer. -/
def Val.head : Val → List Nat
  | .node _ c d _ => [c, d]
  | _ => []

theorem Val.head_ids (v : Val) : ∀ i ∈ v.head, i ∈ v.ids := by
  cases v <;> simp [Val.head]

theorem head_not_below {ty : Ty} {c d : Nat} {es : List Val} {n : Val}
    (hn : (Val.node ty c d es).ids.Nodup) {e : Val} (he : e ∈ es) (hs : Sub n e) {i : Nat}
    (hi1 : i ∈ (Val.node ty c d es).head) (hi2 : i ∈ n.head) : False := by
  have hin : i ∈ idsL es := mem_idsL he (hs.ids i (Val.head_ids _ i hi2))
  simp only [Val.head, List.mem_cons, List.not_mem_nil, or_false] at hi1
  simp only [ids_node, List.nodup_cons, List.mem_cons] at hn
  rcases hi1 with rfl | rfl
  · exact hn.1 (Or.inr hin)
  · exact hn.2.1 hin

/-- In a tree whose addresses are distinct, two subtrees sharing a head
    address are the same subtree. -/
theorem sub_unique {t n1 n2 : Val} (hn : t.ids.Nodup) (h1 : Sub n1 t) (h2 : Sub n2 t) {i : Nat}
    (hi1 : i ∈ n1.head) (hi2 : i ∈ n2.head) : n1 = n2 := by
  induction h1 generalizing n2 with
  | refl =>
    rcases h2.cases' with h | ⟨ty, c, d, es, e, rfl, he, hs⟩
    · exact h.symm
    · exact (head_not_below hn he hs hi1 hi2).elim
  | child he hs ih =>
    rcases h2.cases' with h | ⟨ty, c, d, es, e2, heq, he2, hs2⟩
    · subst h; exact (head_not_below hn he hs hi2 hi1).elim
    · cases heq
      simp only [ids_node, List.nodup_cons] at hn
      have heq := nodup_idsL_same hn.2.2 he he2 (hs.ids i (Val.head_ids _ i hi1))
        (hs2.ids i (Val.head_ids _ i hi2))
      subst heq
      exact ih (nodup_of_mem_idsL hn.2.2 he) hs2 hi2

/-- Two owned subtrees sharing a head address are the same, wherever they
    are owned. -/
theorem owned_unique {m : Mem} (hh : HeapOK m) {x y : Var} {t u n1 n2 : Val}
    (hx : OwnedAt m x t) (hy : OwnedAt m y u) (h1 : Sub n1 t) (h2 : Sub n2 u) {i : Nat}
    (hi1 : i ∈ n1.head) (hi2 : i ∈ n2.head) : x = y ∧ n1 = n2 := by
  have hxy : x = y := by
    refine Classical.byContradiction fun hne => ?_
    exact hh.disj x y t u hne hx hy i (h1.ids i (Val.head_ids _ i hi1))
      (h2.ids i (Val.head_ids _ i hi2))
  subst hxy
  have htu : t = u := by
    unfold OwnedAt at hx hy; rw [hx] at hy; cases hy; rfl
  subst htu
  exact ⟨rfl, sub_unique (hh.nodup x t hx) h1 h2 hi1 hi2⟩

theorem nodeAt_unique {m : Mem} (hh : HeapOK m) {c : Nat} {n1 n2 : Val}
    (h1 : NodeAt m c n1) (h2 : NodeAt m c n2) : n1 = n2 := by
  obtain ⟨x, t, hx, hs1, ty1, d1, es1, rfl⟩ := h1
  obtain ⟨y, u, hy, hs2, ty2, d2, es2, rfl⟩ := h2
  exact (owned_unique hh hx hy hs1 hs2 (i := c) (by simp [Val.head]) (by simp [Val.head])).2

theorem dataAt_unique {m : Mem} (hh : HeapOK m) {d : Nat} {n1 n2 : Val}
    (h1 : DataAt m d n1) (h2 : DataAt m d n2) : n1 = n2 := by
  obtain ⟨x, t, hx, hs1, ty1, c1, es1, rfl⟩ := h1
  obtain ⟨y, u, hy, hs2, ty2, c2, es2, rfl⟩ := h2
  exact (owned_unique hh hx hy hs1 hs2 (i := d) (by simp [Val.head]) (by simp [Val.head])).2

end A1
