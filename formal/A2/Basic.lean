import A2.Invariant

/-! A2 — basic facts: updates, trees and their addresses. -/

namespace A2

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

@[simp] theorem ids_pair (v w : Val) : (Val.pair v w).ids = v.ids ++ w.ids := by simp [Val.ids]
@[simp] theorem ids_inl (v : Val) : (Val.inl v).ids = v.ids := by simp [Val.ids]
@[simp] theorem ids_inr (v : Val) : (Val.inr v).ids = v.ids := by simp [Val.ids]
@[simp] theorem ids_pkg (fs : List Nat) (te : Ty) (ms : List Nat) (v : Val) (cs : List (Var × PMode × Ty)) :
    (Val.pkg fs te ms v cs).ids = v.ids := by
  simp [Val.ids]

theorem Child.ids {e t : Val} (h : Child e t) : ∀ i ∈ e.ids, i ∈ t.ids := by
  intro i hi
  cases h with
  | elem he => simp only [ids_node, List.mem_cons]; exact Or.inr (Or.inr (mem_idsL he hi))
  | fst => simp [hi]
  | snd => simp [hi]
  | inl => simpa using hi
  | inr => simpa using hi
  | pkg => simpa using hi

theorem Child.sub {e t n : Val} (h : Child e t) (hs : Sub n e) : Sub n t := by
  cases h with
  | elem he => exact Sub.child he hs
  | fst => exact Sub.fst hs
  | snd => exact Sub.snd hs
  | inl => exact Sub.inl hs
  | inr => exact Sub.inr hs
  | pkg => exact Sub.pkg hs

theorem Sub.cases' {v t : Val} (h : Sub v t) : v = t ∨ ∃ e, Child e t ∧ Sub v e := by
  cases h with
  | refl => exact Or.inl rfl
  | child he hs => exact Or.inr ⟨_, Child.elem he, hs⟩
  | fst hs => exact Or.inr ⟨_, Child.fst, hs⟩
  | snd hs => exact Or.inr ⟨_, Child.snd, hs⟩
  | inl hs => exact Or.inr ⟨_, Child.inl, hs⟩
  | inr hs => exact Or.inr ⟨_, Child.inr, hs⟩
  | pkg hs => exact Or.inr ⟨_, Child.pkg, hs⟩

theorem Sub.ids {a b : Val} (h : Sub a b) : ∀ i ∈ a.ids, i ∈ b.ids := by
  induction h with
  | refl => exact fun i hi => hi
  | child he _ ih => exact fun i hi => (Child.elem he).ids i (ih i hi)
  | fst _ ih => exact fun i hi => Child.fst.ids i (ih i hi)
  | snd _ ih => exact fun i hi => Child.snd.ids i (ih i hi)
  | inl _ ih => exact fun i hi => Child.inl.ids i (ih i hi)
  | inr _ ih => exact fun i hi => Child.inr.ids i (ih i hi)
  | pkg _ ih => exact fun i hi => Child.pkg.ids i (ih i hi)

theorem Sub.trans {a b c : Val} (h1 : Sub a b) (h2 : Sub b c) : Sub a c := by
  induction h2 with
  | refl => exact h1
  | child he _ ih => exact Sub.child he ih
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih
  | pkg _ ih => exact Sub.pkg ih

/-! ### Reaching through shares (A3.1) -/

theorem SubS.trans_sub {a b c : Val} (h1 : SubS a b) (h2 : Sub b c) : SubS a c := by
  cases h1 with
  | sub h => exact .sub (h.trans h2)
  | arc hk hp => exact .arc (hk.trans h2) hp

theorem SubS.of_sub {a b c : Val} (h1 : Sub a b) (h2 : SubS b c) : SubS a c := by
  induction h2 with
  | sub h => exact .sub (h1.trans h)
  | arc hk _ ih => exact .arc hk ih

theorem SubS.trans {a b c : Val} (h1 : SubS a b) (h2 : SubS b c) : SubS a c := by
  induction h2 with
  | sub h => exact h1.trans_sub h
  | arc hk _ ih => exact .arc hk ih

theorem Below.sub {n t : Val} (h : Below n t) : Sub n t := by
  obtain ⟨e, hc, hs⟩ := h
  exact hc.sub hs

theorem Below.of_sub_below {a b c : Val} (h1 : Sub a b) (h2 : Below b c) : Below a c := by
  obtain ⟨e, hc, hs⟩ := h2
  exact ⟨e, hc, h1.trans hs⟩

theorem Sub.of_below_sub {a b c : Val} (h1 : Below a b) (h2 : Sub b c) : Below a c := by
  induction h2 with
  | refl => exact h1
  | child he _ ih => exact ⟨_, Child.elem he, ih.sub⟩
  | fst _ ih => exact ⟨_, Child.fst, ih.sub⟩
  | snd _ ih => exact ⟨_, Child.snd, ih.sub⟩
  | inl _ ih => exact ⟨_, Child.inl, ih.sub⟩
  | inr _ ih => exact ⟨_, Child.inr, ih.sub⟩
  | pkg _ ih => exact ⟨_, Child.pkg, ih.sub⟩

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

theorem Child.nodup {e t : Val} (h : Child e t) (hn : t.ids.Nodup) : e.ids.Nodup := by
  cases h with
  | elem he => simp only [ids_node, List.nodup_cons] at hn; exact nodup_of_mem_idsL hn.2.2 he
  | fst => simp only [ids_pair, List.nodup_append] at hn; exact hn.1
  | snd => simp only [ids_pair, List.nodup_append] at hn; exact hn.2.1
  | inl => simpa using hn
  | inr => simpa using hn
  | pkg => simpa using hn

/-- Two parts of a tree with distinct addresses that share an address are
    the same part. -/
theorem Child.same {e1 e2 t : Val} (h1 : Child e1 t) (h2 : Child e2 t) (hn : t.ids.Nodup) {i : Nat}
    (hi1 : i ∈ e1.ids) (hi2 : i ∈ e2.ids) : e1 = e2 := by
  cases h1 with
  | elem he1 =>
    cases h2 with
    | elem he2 =>
      simp only [ids_node, List.nodup_cons] at hn
      exact nodup_idsL_same hn.2.2 he1 he2 hi1 hi2
  | fst =>
    cases h2 with
    | fst => rfl
    | snd =>
      simp only [ids_pair, List.nodup_append] at hn
      exact absurd rfl (hn.2.2 i hi1 i hi2)
  | snd =>
    cases h2 with
    | fst =>
      simp only [ids_pair, List.nodup_append] at hn
      exact absurd rfl (hn.2.2 i hi2 i hi1)
    | snd => rfl
  | inl => cases h2; rfl
  | inr => cases h2; rfl
  | pkg => cases h2; rfl

/-- The head addresses of a node: its control block and its buffer. -/
def Val.head : Val → List Nat
  | .node _ c d _ => [c, d]
  | _ => []

theorem Val.head_ids (v : Val) : ∀ i ∈ v.head, i ∈ v.ids := by
  cases v <;> simp [Val.head]

theorem head_not_below {t : Val} (hn : t.ids.Nodup) {e : Val} (hc : Child e t) {n : Val} (hs : Sub n e)
    {i : Nat} (hi1 : i ∈ t.head) (hi2 : i ∈ n.head) : False := by
  cases hc with
  | elem he =>
    have hin : i ∈ idsL _ := mem_idsL he (hs.ids i (Val.head_ids _ i hi2))
    simp only [Val.head, List.mem_cons, List.not_mem_nil, or_false] at hi1
    simp only [ids_node, List.nodup_cons, List.mem_cons] at hn
    rcases hi1 with rfl | rfl
    · exact hn.1 (Or.inr hin)
    · exact hn.2.1 hin
  | fst => simp [Val.head] at hi1
  | snd => simp [Val.head] at hi1
  | inl => simp [Val.head] at hi1
  | inr => simp [Val.head] at hi1
  | pkg => simp [Val.head] at hi1

/-- In a tree whose addresses are distinct, two subtrees sharing a head
    address are the same subtree. -/
theorem sub_unique {t n1 n2 : Val} (hn : t.ids.Nodup) (h1 : Sub n1 t) (h2 : Sub n2 t) {i : Nat}
    (hi1 : i ∈ n1.head) (hi2 : i ∈ n2.head) : n1 = n2 := by
  have step : ∀ {e t : Val}, Child e t → Sub n1 e → t.ids.Nodup →
      (∀ {n2 : Val}, e.ids.Nodup → Sub n2 e → i ∈ n2.head → n1 = n2) →
      ∀ {n2 : Val}, Sub n2 t → i ∈ n2.head → n1 = n2 := by
    intro e t hc hs hn ih n2 h2 hi2
    rcases h2.cases' with h | ⟨e2, hc2, hs2⟩
    · subst h; exact (head_not_below hn hc hs hi2 hi1).elim
    · have heq := Child.same hc hc2 hn (hs.ids i (Val.head_ids _ i hi1))
        (hs2.ids i (Val.head_ids _ i hi2))
      subst heq
      exact ih (hc.nodup hn) hs2 hi2
  induction h1 generalizing n2 with
  | refl =>
    rcases h2.cases' with h | ⟨e, hc, hs⟩
    · exact h.symm
    · exact (head_not_below hn hc hs hi1 hi2).elim
  | child he hs ih => exact step (Child.elem he) hs hn (fun hn' h2' hi2' => ih hn' h2' hi2') h2 hi2
  | fst hs ih => exact step Child.fst hs hn (fun hn' h2' hi2' => ih hn' h2' hi2') h2 hi2
  | snd hs ih => exact step Child.snd hs hn (fun hn' h2' hi2' => ih hn' h2' hi2') h2 hi2
  | inl hs ih => exact step Child.inl hs hn (fun hn' h2' hi2' => ih hn' h2' hi2') h2 hi2
  | inr hs ih => exact step Child.inr hs hn (fun hn' h2' hi2' => ih hn' h2' hi2') h2 hi2
  | pkg hs ih => exact step Child.pkg hs hn (fun hn' h2' hi2' => ih hn' h2' hi2') h2 hi2

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

/-- Two subtrees of owned trees (a slot's, or a block's payload) sharing a
    head address are the same. -/
theorem treeAt_unique {m : Mem} (hh : HeapOK m) {t u n1 n2 : Val} (ht : TreeAt m t) (hu : TreeAt m u)
    (h1 : Sub n1 t) (h2 : Sub n2 u) {i : Nat} (hi1 : i ∈ n1.head) (hi2 : i ∈ n2.head) : n1 = n2 := by
  have hi1' := h1.ids i (Val.head_ids _ i hi1)
  have hi2' := h2.ids i (Val.head_ids _ i hi2)
  rcases ht with ⟨x, hx⟩ | ⟨k, a, hk⟩ <;> rcases hu with ⟨y, hy⟩ | ⟨k', b, hk'⟩
  · exact (owned_unique hh hx hy h1 h2 hi1 hi2).2
  · exact absurd hi1' (hh.bdisj k' _ x _ hk' hx i (List.mem_cons_of_mem _ hi2'))
  · exact absurd hi2' (hh.bdisj k _ y _ hk hy i (List.mem_cons_of_mem _ hi1'))
  · by_cases hkk : k = k'
    · subst hkk
      rw [hk] at hk'; cases hk'
      exact sub_unique (List.nodup_cons.mp (hh.bnodup k _ hk)).2 h1 h2 hi1 hi2
    · exact absurd (List.mem_cons_of_mem _ hi2')
        (hh.bdisj2 k k' _ _ hkk hk hk' i (List.mem_cons_of_mem _ hi1'))

/-- A share a well-formed tree holds is one at some type. -/
theorem WFv.arcIn {τ : Ty} {T : Val} (hw : WFv τ T) {k : Nat} {p : Val} (hs : Sub (.arc k p) T) :
    ∃ u, ArcIn τ T u k p := by
  induction hw with
  | int => cases hs
  | view => cases hs
  | node _ ih =>
    cases hs with
    | child he hs' => obtain ⟨u, ha⟩ := ih _ he hs'; exact ⟨u, .child he ha⟩
  | pair _ _ ihv ihw =>
    cases hs with
    | fst hs' => obtain ⟨u, ha⟩ := ihv hs'; exact ⟨u, .fst ha⟩
    | snd hs' => obtain ⟨u, ha⟩ := ihw hs'; exact ⟨u, .snd ha⟩
  | inl _ ih => cases hs with | inl hs' => obtain ⟨u, ha⟩ := ih hs'; exact ⟨u, .inl ha⟩
  | inr _ ih => cases hs with | inr hs' => obtain ⟨u, ha⟩ := ih hs'; exact ⟨u, .inr ha⟩
  | pkg _ ih => cases hs with | pkg hs' => obtain ⟨u, ha⟩ := ih hs'; exact ⟨u, .pkg ha⟩
  | arc => cases hs; exact ⟨_, .here⟩

/-- What an owned tree reaches through its shares lies in it, or in some
    block's payload. -/
theorem SubS.loc {m : Mem} (hs : SharesHeld m) {n T : Val} (h : SubS n T) :
    TreeAt m T → Sub n T ∨ ∃ k u p, m.blk k = some ⟨u, p⟩ ∧ Sub n p := by
  induction h with
  | sub h => exact fun _ => Or.inl h
  | arc hk _ ih =>
    intro hT
    obtain ⟨u, hb⟩ := hs _ hT _ _ hk
    rcases ih (Or.inr ⟨_, u, hb⟩) with h | h
    · exact Or.inr ⟨_, u, _, hb, h⟩
    · exact Or.inr h

theorem SubS.tree {m : Mem} (hs : SharesHeld m) {n T : Val} (hT : TreeAt m T) (h : SubS n T) :
    ∃ T', TreeAt m T' ∧ Sub n T' := by
  rcases h.loc hs hT with h | ⟨k, u, p, hb, h⟩
  · exact ⟨T, hT, h⟩
  · exact ⟨p, Or.inr ⟨k, u, hb⟩, h⟩

/-- The invariant ties every share in memory to its block. -/
theorem MInv.sharesHeld {m : Mem} {Γ : Ctx} (hi : MInv m Γ) : SharesHeld m := by
  intro T hT k p hs
  rcases hT with ⟨x, hx⟩ | ⟨kb, u, hk⟩
  · have hd := hi.dom x
    rw [hx] at hd
    obtain ⟨E, hE⟩ := Option.isSome_iff_exists.mp hd
    obtain ⟨sl, hsl, _, hso, hown, _⟩ := hi.slot x E hE
    rw [hx] at hsl; cases hsl
    obtain ⟨u, ha⟩ := ((hown hso.symm).2.1 T rfl).arcIn hs
    exact ⟨u, hi.shares x E _ T hE hx rfl rfl u k p ha⟩
  · obtain ⟨_, _, hw, hsh⟩ := hi.blocks kb ⟨u, T⟩ hk
    obtain ⟨u', ha⟩ := hw.arcIn hs
    exact ⟨u', hsh u' k p ha⟩

/-- Every address of an owned tree (a slot's, or a block's payload) is live. -/
theorem HeapOK.treeAt_alloc {m : Mem} (hh : HeapOK m) {T : Val} (hT : TreeAt m T) :
    ∀ i ∈ T.ids, m.alloc i = true ∧ i < m.nid := by
  rcases hT with ⟨x, hx⟩ | ⟨k, u, hk⟩
  · exact hh.alloc x T hx
  · exact fun i hi => hh.balloc k ⟨u, T⟩ hk i (List.mem_cons_of_mem _ hi)

theorem nodeAt_unique {m : Mem} (hh : HeapOK m) {c : Nat} {n1 n2 : Val}
    (h1 : NodeAt m c n1) (h2 : NodeAt m c n2) : n1 = n2 := by
  obtain ⟨t, ht, hs1, ty1, d1, es1, rfl⟩ := h1
  obtain ⟨u, hu, hs2, ty2, d2, es2, rfl⟩ := h2
  exact treeAt_unique hh ht hu hs1 hs2 (i := c) (by simp [Val.head]) (by simp [Val.head])

theorem dataAt_unique {m : Mem} (hh : HeapOK m) {d : Nat} {n1 n2 : Val}
    (h1 : DataAt m d n1) (h2 : DataAt m d n2) : n1 = n2 := by
  obtain ⟨t, ht, hs1, ty1, c1, es1, rfl⟩ := h1
  obtain ⟨u, hu, hs2, ty2, c2, es2, rfl⟩ := h2
  exact treeAt_unique hh ht hu hs1 hs2 (i := d) (by simp [Val.head]) (by simp [Val.head])

end A2
