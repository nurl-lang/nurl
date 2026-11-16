import A2.Basic

/-!
# A Vec's control block is never another Vec's buffer (Agora #879)

A `Vec` value is `Val.node t c d es`: `c` its control block, `d` its buffer,
two allocations (`Step`'s `new`: `nid` and `nid + 1`).  nurlc's lowering tags
every access to a control block's header words `nurl vec ctl` and every
element access through a buffer `nurl vec elem` (TBAA, `mem_velem_tag`), which
tells LLVM that no byte is accessed under both: that no control block is a
buffer.  This module states that fact of the calculus's store, for every tree
it owns — the slots' (`HeapOK.nodup`, `HeapOK.disj`) and the blocks' payloads
(`BlkOwn`) — so the lowering's alias claim rests on a theorem of the model:

* `ctl_ne_data`: the control block of any node of any owned tree is not the
  buffer of any node of any owned tree (the same tree, the same node, or
  another).

The proof splits a tree's addresses into its nodes' control blocks (`ctls`)
and buffers (`datas`), whose concatenation is a permutation of `Val.ids`
(`ctls_datas_perm`), so the invariants' `Nodup` and disjointness of `ids`
carry over to them.
-/

namespace A2

mutual
/-- The control blocks of a tree's nodes (`Val.ids` without the buffers). -/
def Val.ctls : Val → List Nat
  | .node _ c _ es => c :: ctlsL es
  | .pair v w => v.ctls ++ w.ctls
  | .inl v => v.ctls
  | .inr v => v.ctls
  | .pkg _ _ _ v _ => v.ctls
  | _ => []
def ctlsL : List Val → List Nat
  | [] => []
  | e :: es => e.ctls ++ ctlsL es
end

mutual
/-- The buffers of a tree's nodes. -/
def Val.datas : Val → List Nat
  | .node _ _ d es => d :: datasL es
  | .pair v w => v.datas ++ w.datas
  | .inl v => v.datas
  | .inr v => v.datas
  | .pkg _ _ _ v _ => v.datas
  | _ => []
def datasL : List Val → List Nat
  | [] => []
  | e :: es => e.datas ++ datasL es
end

/-- Interleaving two lists' pairs of parts: `(a ++ b) ++ (c ++ d) ~ (a ++ c) ++ (b ++ d)`. -/
private theorem perm_swap4 (a b c d : List Nat) :
    ((a ++ b) ++ (c ++ d)).Perm ((a ++ c) ++ (b ++ d)) := by
  simp only [List.append_assoc]
  exact List.Perm.append_left a (by
    rw [← List.append_assoc, ← List.append_assoc]
    exact List.Perm.append_right d List.perm_append_comm)

mutual
/-- A tree's addresses are its control blocks and its buffers. -/
theorem ctls_datas_perm : ∀ v : Val, (v.ctls ++ v.datas).Perm v.ids
  | .int _ => by simp [Val.ctls, Val.datas, Val.ids]
  | .node _ c d es => by
    simp only [Val.ctls, Val.datas, Val.ids, List.cons_append]
    refine List.Perm.cons c ?_
    exact (List.perm_middle).trans (List.Perm.cons d (ctlsL_datasL_perm es))
  | .href _ => by simp [Val.ctls, Val.datas, Val.ids]
  | .view _ _ _ => by simp [Val.ctls, Val.datas, Val.ids]
  | .pair v w => by
    simp only [Val.ctls, Val.datas, Val.ids]
    exact (perm_swap4 _ _ _ _).trans
      (List.Perm.append (ctls_datas_perm v) (ctls_datas_perm w))
  | .inl v => by simpa [Val.ctls, Val.datas, Val.ids] using ctls_datas_perm v
  | .inr v => by simpa [Val.ctls, Val.datas, Val.ids] using ctls_datas_perm v
  | .pkg _ _ _ v _ => by simpa [Val.ctls, Val.datas, Val.ids] using ctls_datas_perm v
  | .arc _ _ => by simp [Val.ctls, Val.datas, Val.ids]
  | .lk _ => by simp [Val.ctls, Val.datas, Val.ids]
  | .cell _ => by simp [Val.ctls, Val.datas, Val.ids]
theorem ctlsL_datasL_perm : ∀ es : List Val, (ctlsL es ++ datasL es).Perm (idsL es)
  | [] => by simp [ctlsL, datasL, idsL]
  | e :: es => by
    simp only [ctlsL, datasL, idsL]
    exact (perm_swap4 _ _ _ _).trans
      (List.Perm.append (ctls_datas_perm e) (ctlsL_datasL_perm es))
end

theorem ctls_sub_ids {v : Val} {i : Nat} (h : i ∈ v.ctls) : i ∈ v.ids :=
  (ctls_datas_perm v).mem_iff.mp (List.mem_append_left _ h)

theorem datas_sub_ids {v : Val} {i : Nat} (h : i ∈ v.datas) : i ∈ v.ids :=
  (ctls_datas_perm v).mem_iff.mp (List.mem_append_right _ h)

/-- In a tree whose addresses are distinct, no control block is a buffer. -/
theorem ctls_datas_disj {v : Val} (h : v.ids.Nodup) {i : Nat} (hc : i ∈ v.ctls) (hd : i ∈ v.datas) :
    False :=
  (List.nodup_append.mp ((ctls_datas_perm v).nodup_iff.mpr h)).2.2 i hc i hd rfl

theorem mem_ctlsL {e : Val} {es : List Val} (h : e ∈ es) {i : Nat} (hi : i ∈ e.ctls) : i ∈ ctlsL es := by
  induction es with
  | nil => cases h
  | cons x xs ih =>
    simp only [ctlsL, List.mem_append]
    rcases List.mem_cons.mp h with rfl | h
    · exact Or.inl hi
    · exact Or.inr (ih h)

theorem mem_datasL {e : Val} {es : List Val} (h : e ∈ es) {i : Nat} (hi : i ∈ e.datas) : i ∈ datasL es := by
  induction es with
  | nil => cases h
  | cons x xs ih =>
    simp only [datasL, List.mem_append]
    rcases List.mem_cons.mp h with rfl | h
    · exact Or.inl hi
    · exact Or.inr (ih h)

/-- A node inside a tree: its control block is one of the tree's. -/
theorem Sub.ctl_mem {t : Ty} {c d : Nat} {es : List Val} {v : Val} (h : Sub (.node t c d es) v) :
    c ∈ v.ctls := by
  generalize hn : Val.node t c d es = n at h
  induction h with
  | refl => subst hn; simp [Val.ctls]
  | child he _ ih => simp only [Val.ctls, List.mem_cons]; exact Or.inr (mem_ctlsL he ih)
  | fst _ ih => simp only [Val.ctls, List.mem_append]; exact Or.inl ih
  | snd _ ih => simp only [Val.ctls, List.mem_append]; exact Or.inr ih
  | inl _ ih => simpa [Val.ctls] using ih
  | inr _ ih => simpa [Val.ctls] using ih
  | pkg _ ih => simpa [Val.ctls] using ih

/-- … and its buffer is one of the tree's buffers. -/
theorem Sub.data_mem {t : Ty} {c d : Nat} {es : List Val} {v : Val} (h : Sub (.node t c d es) v) :
    d ∈ v.datas := by
  generalize hn : Val.node t c d es = n at h
  induction h with
  | refl => subst hn; simp [Val.datas]
  | child he _ ih => simp only [Val.datas, List.mem_cons]; exact Or.inr (mem_datasL he ih)
  | fst _ ih => simp only [Val.datas, List.mem_append]; exact Or.inl ih
  | snd _ ih => simp only [Val.datas, List.mem_append]; exact Or.inr ih
  | inl _ ih => simpa [Val.datas] using ih
  | inr _ ih => simpa [Val.datas] using ih
  | pkg _ ih => simpa [Val.datas] using ih

/-- A tree the store owns: a slot's owned value, or a block's payload. -/
def OwnedTree (m : Mem) (T : Val) : Prop :=
  (∃ x, OwnedAt m x T) ∨ ∃ k bl, m.blk k = some bl ∧ bl.tree = T

/-- Two owned trees with an address in common are the same tree, and their
    addresses are distinct (`HeapOK`, `BlkOwn`). -/
theorem OwnedTree.share {m : Mem} (h : HeapOK m) {T U : Val} (hT : OwnedTree m T) (hU : OwnedTree m U)
    {i : Nat} (hiT : i ∈ T.ids) (hiU : i ∈ U.ids) : T = U ∧ T.ids.Nodup := by
  rcases hT with ⟨x, hx⟩ | ⟨k, bl, hk, rfl⟩ <;> rcases hU with ⟨y, hy⟩ | ⟨k', bl', hk', rfl⟩
  · by_cases hxy : x = y
    · subst hxy
      have : T = U := by
        unfold OwnedAt at hx hy; rw [hx] at hy; injection hy with hy; injection hy with _ hy
        injection hy
      exact ⟨this, h.nodup x T hx⟩
    · exact absurd hiU (h.disj x y T U hxy hx hy i hiT)
  · exact absurd hiT ((h.blk k' bl' hk').2.2 i hiU |>.2.2.1 x T hx)
  · exact absurd hiU ((h.blk k bl hk).2.2 i hiT |>.2.2.1 y U hy)
  · by_cases hkk : k' = k
    · subst hkk; rw [hk] at hk'; injection hk' with hk'; subst hk'
      exact ⟨rfl, (h.blk _ bl hk).2.1⟩
    · exact absurd hiU ((h.blk k bl hk).2.2 i hiT |>.2.2.2 k' bl' hkk hk')

/-- The control block of a node of any tree the store owns is not the buffer
    of a node of any tree it owns: the fact nurlc's `nurl vec ctl` /
    `nurl vec elem` TBAA tags assert (Agora #879). -/
theorem ctl_ne_data {m : Mem} (h : HeapOK m) {T U : Val} (hT : OwnedTree m T) (hU : OwnedTree m U)
    {t₁ t₂ : Ty} {c₁ d₁ c₂ d₂ : Nat} {es₁ es₂ : List Val}
    (h₁ : Sub (.node t₁ c₁ d₁ es₁) T) (h₂ : Sub (.node t₂ c₂ d₂ es₂) U) : c₁ ≠ d₂ := by
  intro heq
  have hc : c₁ ∈ T.ctls := h₁.ctl_mem
  have hd : d₂ ∈ U.datas := h₂.data_mem
  obtain ⟨rfl, hnd⟩ := OwnedTree.share h hT hU (ctls_sub_ids hc) (heq ▸ datas_sub_ids hd)
  exact ctls_datas_disj hnd hc (heq ▸ hd)

end A2
