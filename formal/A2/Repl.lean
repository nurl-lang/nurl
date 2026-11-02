import A2.Stability

/-! A2 — one-hole replacement in a value (Agora #295).

`Repl n n' T T'`: `T'` is `T` with one occurrence of `n` replaced by `n'`.
A change made through a borrowed handle (`href c`) rewrites the node at
cell `c` wherever it lies in its owner's tree, and leaves the rest of the
tree as it was: that rewrite is a `Repl` of the owner's tree. The lemmas
here are what the invariant needs of it: where the hole is (`sub`,
`sub'`), that every occurrence can be rewritten (`exists`), how the
addresses and the captured names of the two trees relate (`ids_split`,
`names_split`), and that a rewrite of a tree at its own top is the
replacement itself (`here_inv`, by size: a tree is no part of itself). -/

namespace A2

-- (`Repl` itself is in `Semantics.lean`, where the steps that rewrite a
-- tree through a borrowed handle use it.)

/-! ### Sizes: a tree is no part of itself -/

theorem Child.sizeOf_lt {e t : Val} (h : Child e t) : sizeOf e < sizeOf t := by
  cases h with
  | elem he =>
    have := List.sizeOf_lt_of_mem he
    simp only [Val.node.sizeOf_spec]; omega
  | fst => simp only [Val.pair.sizeOf_spec]; omega
  | snd => simp only [Val.pair.sizeOf_spec]; omega
  | inl => simp only [Val.inl.sizeOf_spec]; omega
  | inr => simp only [Val.inr.sizeOf_spec]; omega
  | pkg => simp only [Val.pkg.sizeOf_spec]; omega

theorem Sub.sizeOf_le {a b : Val} (h : Sub a b) : sizeOf a ≤ sizeOf b := by
  induction h with
  | refl => exact Nat.le_refl _
  | child he _ ih => exact Nat.le_trans ih (Nat.le_of_lt (Child.elem he).sizeOf_lt)
  | fst _ ih => exact Nat.le_trans ih (Nat.le_of_lt Child.fst.sizeOf_lt)
  | snd _ ih => exact Nat.le_trans ih (Nat.le_of_lt Child.snd.sizeOf_lt)
  | inl _ ih => exact Nat.le_trans ih (Nat.le_of_lt Child.inl.sizeOf_lt)
  | inr _ ih => exact Nat.le_trans ih (Nat.le_of_lt Child.inr.sizeOf_lt)
  | pkg _ ih => exact Nat.le_trans ih (Nat.le_of_lt Child.pkg.sizeOf_lt)

/-- A tree lies strictly below none of its own parts. -/
theorem Below.not_self {n : Val} (h : Below n n) : False := by
  obtain ⟨e, hc, hs⟩ := h
  have h1 := hs.sizeOf_le
  have h2 := hc.sizeOf_lt
  omega

private theorem namesL_app (es fs : List Val) : namesL (es ++ fs) = namesL es ++ namesL fs := by
  induction es with
  | nil => simp [namesL]
  | cons x xs ih => simp [namesL, ih]

namespace Repl
variable {n n' : Val}

/-- The replaced node lies in the old tree. -/
theorem sub {T T' : Val} (h : Repl n n' T T') : Sub n T := by
  induction h with
  | here => exact Sub.refl _
  | elem _ ih => exact Sub.child (List.mem_append_right _ (List.mem_cons_self ..)) ih
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih
  | pkg _ ih => exact Sub.pkg ih

/-- Its replacement lies in the new one. -/
theorem sub' {T T' : Val} (h : Repl n n' T T') : Sub n' T' := by
  induction h with
  | here => exact Sub.refl _
  | elem _ ih => exact Sub.child (List.mem_append_right _ (List.mem_cons_self ..)) ih
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih
  | pkg _ ih => exact Sub.pkg ih

/-- Every occurrence of a node in a tree can be replaced. -/
theorem «exists» {T : Val} (h : Sub n T) (n' : Val) : ∃ T', Repl n n' T T' := by
  induction h with
  | refl => exact ⟨_, .here⟩
  | child he _ ih =>
    obtain ⟨T', hr⟩ := ih
    obtain ⟨pre, post, rfl⟩ := List.append_of_mem he
    exact ⟨_, .elem hr⟩
  | fst _ ih => obtain ⟨_, hr⟩ := ih; exact ⟨_, .fst hr⟩
  | snd _ ih => obtain ⟨_, hr⟩ := ih; exact ⟨_, .snd hr⟩
  | inl _ ih => obtain ⟨_, hr⟩ := ih; exact ⟨_, .inl hr⟩
  | inr _ ih => obtain ⟨_, hr⟩ := ih; exact ⟨_, .inr hr⟩
  | pkg _ ih => obtain ⟨_, hr⟩ := ih; exact ⟨_, .pkg hr⟩

/-- The addresses of the two trees: the same around the hole, the old
    node's in the old tree and the new node's in the new one. -/
theorem ids_split {T T' : Val} (h : Repl n n' T T') :
    ∃ A B, T.ids = A ++ n.ids ++ B ∧ T'.ids = A ++ n'.ids ++ B := by
  induction h with
  | here => exact ⟨[], [], by simp, by simp⟩
  | @elem t c d pre post e e' _ ih =>
    obtain ⟨A, B, h1, h2⟩ := ih
    refine ⟨c :: d :: (idsL pre ++ A), B ++ idsL post, ?_, ?_⟩
    · simp [idsL_append, h1]
    · simp [idsL_append, h2]
  | @fst a a' b _ ih =>
    obtain ⟨A, B, h1, h2⟩ := ih
    exact ⟨A, B ++ b.ids, by simp [h1], by simp [h2]⟩
  | @snd a b b' _ ih =>
    obtain ⟨A, B, h1, h2⟩ := ih
    exact ⟨a.ids ++ A, B, by simp [h1], by simp [h2]⟩
  | inl _ ih => simpa using ih
  | inr _ ih => simpa using ih
  | pkg _ ih => simpa using ih

/-- An address of the new tree is the new node's, or one the old tree had. -/
theorem mem_ids {T T' : Val} (h : Repl n n' T T') {i : Nat} (hi : i ∈ T'.ids) :
    i ∈ n'.ids ∨ i ∈ T.ids := by
  obtain ⟨A, B, h1, h2⟩ := h.ids_split
  rw [h2] at hi; rw [h1]
  simp only [List.mem_append] at hi ⊢
  rcases hi with (hi | hi) | hi
  · exact .inr (.inl (.inl hi))
  · exact .inl hi
  · exact .inr (.inr hi)

/-- The captured names of the two trees, the same way: what a package
    deeper in the tree captured is untouched around the hole. -/
theorem names_split {T T' : Val} (h : Repl n n' T T') :
    ∃ A B, T.names = A ++ n.names ++ B ∧ T'.names = A ++ n'.names ++ B := by
  induction h with
  | here => exact ⟨[], [], by simp, by simp⟩
  | @elem t c d pre post e e' _ ih =>
    obtain ⟨A, B, h1, h2⟩ := ih
    refine ⟨namesL pre ++ A, B ++ namesL post, ?_, ?_⟩
    · simp [Val.names, namesL_app, namesL, h1]
    · simp [Val.names, namesL_app, namesL, h2]
  | @fst a a' b _ ih =>
    obtain ⟨A, B, h1, h2⟩ := ih
    exact ⟨A, B ++ b.names, by simp [Val.names, h1], by simp [Val.names, h2]⟩
  | @snd a b b' _ ih =>
    obtain ⟨A, B, h1, h2⟩ := ih
    exact ⟨a.names ++ A, B, by simp [Val.names, h1], by simp [Val.names, h2]⟩
  | inl _ ih => simpa [Val.names] using ih
  | inr _ ih => simpa [Val.names] using ih
  | @pkg fs te ms cs a a' _ ih =>
    obtain ⟨A, B, h1, h2⟩ := ih
    exact ⟨cs ++ A, B, by simp [Val.names, h1], by simp [Val.names, h2]⟩

/-- A rewrite of a tree at its own top is the replacement itself: the
    node cannot also lie strictly inside itself. -/
theorem here_inv {T' : Val} (h : Repl n n' n T') : T' = n' := by
  suffices ∀ T, Repl n n' T T' → T = n → T' = n' from this n h rfl
  intro T hr hT
  cases hr with
  | here => rfl
  | elem hr' =>
    exact (Below.not_self (n := n) ⟨_, hT ▸ Child.elem (List.mem_append_right _ (List.mem_cons_self ..)), hr'.sub⟩).elim
  | fst hr' => exact (Below.not_self (n := n) ⟨_, hT ▸ Child.fst, hr'.sub⟩).elim
  | snd hr' => exact (Below.not_self (n := n) ⟨_, hT ▸ Child.snd, hr'.sub⟩).elim
  | inl hr' => exact (Below.not_self (n := n) ⟨_, hT ▸ Child.inl, hr'.sub⟩).elim
  | inr hr' => exact (Below.not_self (n := n) ⟨_, hT ▸ Child.inr, hr'.sub⟩).elim
  | pkg hr' => exact (Below.not_self (n := n) ⟨_, hT ▸ Child.pkg, hr'.sub⟩).elim

/-- A rewritten node keeps its type, cell and buffer unless it is the hole:
    a rewrite below a node only rewrites its elements. -/
theorem node_shape {t : Ty} {c d : Nat} {es : List Val} {T' : Val}
    (h : Repl n n' (.node t c d es) T') :
    (n = .node t c d es ∧ T' = n') ∨ ∃ es', T' = .node t c d es' := by
  cases h with
  | here => exact Or.inl ⟨rfl, rfl⟩
  | elem _ => exact Or.inr ⟨_, rfl⟩

/-- A part of the old tree at its top (through fields, payloads and
    environments, never a `Vec`'s elements) lies inside the hole, or has a
    part of the new tree at its top as its counterpart: the same value, or
    the value with the hole rewritten in it. -/
theorem top {T T' m : Val} (hr : Repl n n' T T') (ht : Top m T) :
    Sub m n ∨ ∃ m', Top m' T' ∧ (m' = m ∨ Repl n n' m m') := by
  induction ht generalizing T' with
  | refl => exact Or.inr ⟨T', Top.refl _, Or.inr hr⟩
  | fst h ih =>
    cases hr with
    | here => exact Or.inl (Sub.fst h.sub)
    | fst hr' =>
      rcases ih hr' with h' | ⟨m', ht', hm⟩
      · exact Or.inl h'
      · exact Or.inr ⟨m', Top.fst ht', hm⟩
    | snd _ => exact Or.inr ⟨_, Top.fst h, Or.inl rfl⟩
  | snd h ih =>
    cases hr with
    | here => exact Or.inl (Sub.snd h.sub)
    | fst _ => exact Or.inr ⟨_, Top.snd h, Or.inl rfl⟩
    | snd hr' =>
      rcases ih hr' with h' | ⟨m', ht', hm⟩
      · exact Or.inl h'
      · exact Or.inr ⟨m', Top.snd ht', hm⟩
  | inl h ih =>
    cases hr with
    | here => exact Or.inl (Sub.inl h.sub)
    | inl hr' =>
      rcases ih hr' with h' | ⟨m', ht', hm⟩
      · exact Or.inl h'
      · exact Or.inr ⟨m', Top.inl ht', hm⟩
  | inr h ih =>
    cases hr with
    | here => exact Or.inl (Sub.inr h.sub)
    | inr hr' =>
      rcases ih hr' with h' | ⟨m', ht', hm⟩
      · exact Or.inl h'
      · exact Or.inr ⟨m', Top.inr ht', hm⟩
  | pkg h ih =>
    cases hr with
    | here => exact Or.inl (Sub.pkg h.sub)
    | pkg hr' =>
      rcases ih hr' with h' | ⟨m', ht', hm⟩
      · exact Or.inl h'
      · exact Or.inr ⟨m', Top.pkg ht', hm⟩

/-- A node of a tree replaced by itself: the tree is unchanged (an element
    set out of range, Agora #295). -/
theorem self {T : Val} (h : Sub n T) : Repl n n T T := by
  induction h with
  | refl => exact .here
  | child he _ ih =>
    obtain ⟨pre, post, rfl⟩ := List.append_of_mem he
    exact .elem ih
  | fst _ ih => exact .fst ih
  | snd _ ih => exact .snd ih
  | inl _ ih => exact .inl ih
  | inr _ ih => exact .inr ih
  | pkg _ ih => exact .pkg ih

end Repl

/-- The addresses of a node's elements, around its `n`-th one, before and
    after an element set replaces it by `v` (Agora #295). -/
theorem idsL_set {es : List Val} {n : Nat} (hn : n < es.length) (v : Val) :
    idsL es = idsL (es.take n) ++ es[n].ids ++ idsL (es.drop (n + 1)) ∧
    idsL (es.set n v) = idsL (es.take n) ++ v.ids ++ idsL (es.drop (n + 1)) := by
  have h1 : es = es.take n ++ es[n] :: es.drop (n + 1) := by
    rw [← List.drop_eq_getElem_cons hn, List.take_append_drop]
  have h2 : es.set n v = es.take n ++ v :: es.drop (n + 1) := by
    rw [List.set_eq_take_append_cons_drop]; simp [hn]
  refine ⟨?_, ?_⟩
  · calc idsL es = idsL (es.take n ++ es[n] :: es.drop (n + 1)) := congrArg idsL h1
      _ = _ := by rw [idsL_append, idsL_cons, List.append_assoc]
  · rw [h2, idsL_append, idsL_cons, List.append_assoc]

/-- What an element set replaces is in the node's tree. -/
theorem ids_get_sub {t : Ty} {c d : Nat} {es : List Val} {n i : Nat} (hn : n < es.length)
    (hi : i ∈ es[n].ids) : i ∈ (Val.node t c d es).ids := by
  simp only [ids_node, List.mem_cons]
  exact .inr (.inr (mem_idsL (List.getElem_mem hn) hi))

/-- What a truncation drops is in the node's tree. -/
theorem ids_drop_sub {t : Ty} {c d : Nat} {es : List Val} {n i : Nat} (hi : i ∈ idsL (es.drop n)) :
    i ∈ (Val.node t c d es).ids := by
  obtain ⟨e, he, hie⟩ := mem_idsL_iff.mp hi
  simp only [ids_node, List.mem_cons]
  exact .inr (.inr (mem_idsL (List.mem_of_mem_drop he) hie))

/-- A3.1: a rewrite keeps every share of a tree naming a block of `B` when
    the replacement's do, at every type the hole is well-formed at (a share
    is a leaf: no rewrite reaches into what it carries). -/
theorem SharesIn.repl {B : Nat → Option Blk} {n n' : Val}
    (hn : ∀ σ, WFv σ n → SharesIn B σ n → SharesIn B σ n') {T T' : Val} (hr : Repl n n' T T') :
    ∀ {τ : Ty}, WFv τ T → SharesIn B τ T → SharesIn B τ T' := by
  induction hr with
  | here => exact fun h hs => hn _ h hs
  | @elem t c d pre post e e' _ ih =>
    intro τ h hs
    cases h with
    | node hes =>
      intro u k p ha
      cases ha with
      | child hx ha' =>
        rcases List.mem_append.mp hx with hx | hx
        · exact hs u k p (.child (List.mem_append_left _ hx) ha')
        · rcases List.mem_cons.mp hx with rfl | hx
          · exact ih (hes e (List.mem_append_right _ (List.mem_cons_self ..)))
              (fun u k p ha => hs u k p (.child (List.mem_append_right _ (List.mem_cons_self ..)) ha))
              u k p ha'
          · exact hs u k p (.child (List.mem_append_right _ (List.mem_cons_of_mem _ hx)) ha')
  | fst _ ih =>
    intro τ h hs
    cases h with
    | pair ha _ =>
      intro u k p hA
      cases hA with
      | fst h' => exact ih ha (fun u k p h => hs u k p (.fst h)) u k p h'
      | snd h' => exact hs u k p (.snd h')
  | snd _ ih =>
    intro τ h hs
    cases h with
    | pair _ hb =>
      intro u k p hA
      cases hA with
      | fst h' => exact hs u k p (.fst h')
      | snd h' => exact ih hb (fun u k p h => hs u k p (.snd h)) u k p h'
  | inl _ ih =>
    intro τ h hs
    cases h with
    | inl ha =>
      intro u k p hA
      cases hA with | inl h' => exact ih ha (fun u k p h => hs u k p (.inl h)) u k p h'
  | inr _ ih =>
    intro τ h hs
    cases h with
    | inr ha =>
      intro u k p hA
      cases hA with | inr h' => exact ih ha (fun u k p h => hs u k p (.inr h)) u k p h'
  | pkg _ ih =>
    intro τ h hs
    cases h with
    | pkg ha =>
      intro u k p hA
      cases hA with | pkg h' => exact ih ha (fun u k p h => hs u k p (.pkg h)) u k p h'

/-- ... over a memory's blocks, for a node rewritten to one of its own type. -/
theorem SharesOK.repl {m : Mem} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hn : SharesOK m (.vec t) (.node t c d' es')) {T T' : Val}
    (hr : Repl (.node t c d es) (.node t c d' es') T T') {τ : Ty} (hw : WFv τ T)
    (hs : SharesOK m τ T) : SharesOK m τ T' :=
  SharesIn.repl (fun σ h _ => by cases h; exact hn) hr hw hs

/-- The node a `NodeOf` finds lies in its owner's tree. -/
theorem NodeOf.sub {m : Mem} {x o : Var} {T : Val} {t : Ty} {c d : Nat} {es : List Val}
    (h : NodeOf m x o T t c d es) : Sub (.node t c d es) T := by
  rcases h.2.2.2 with ⟨_, rfl⟩ | ⟨_, hs⟩
  · exact Sub.refl _
  · exact hs

end A2
