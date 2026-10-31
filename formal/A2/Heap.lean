import A2.Stability

/-! A2 — releasing trees, and the one-owner-per-allocation invariant. -/

namespace A2

mutual
theorem Frees.other {a a' : Nat → Bool} {T : Val} (h : Frees a T a') :
    ∀ {i : Nat}, i ∉ T.ids → a' i = a i := by
  intro i hi
  match h with
  | .int => rfl
  | .view => rfl
  | .arc => rfl
  | .node _ _ hl =>
    simp only [ids_node, List.mem_cons, not_or] at hi
    rw [FreesL.other hl hi.2.2, upd_ne _ _ hi.2.1, upd_ne _ _ hi.1]
  | .pair h1 h2 =>
    simp only [ids_pair, List.mem_append, not_or] at hi
    rw [Frees.other h2 hi.2, Frees.other h1 hi.1]
  | .inl h1 => exact Frees.other h1 (by simpa using hi)
  | .inr h1 => exact Frees.other h1 (by simpa using hi)
  | .pkg h1 => exact Frees.other h1 (by simpa using hi)
theorem FreesL.other {a a' : Nat → Bool} {es : List Val} (h : FreesL a es a') :
    ∀ {i : Nat}, i ∉ idsL es → a' i = a i := by
  intro i hi
  match h with
  | .nil => rfl
  | .cons h1 h2 =>
    simp only [idsL_cons, List.mem_append, not_or] at hi
    rw [FreesL.other h2 hi.2, Frees.other h1 hi.1]
end

/-- A well-formed tree whose addresses are distinct and live can be freed. -/
theorem frees_exists {τ : Ty} {T : Val} (hw : WFv τ T) :
    ∀ a : Nat → Bool, T.ids.Nodup → (∀ i ∈ T.ids, a i = true) → ∃ a', Frees a T a' := by
  induction hw with
  | int => exact fun a _ _ => ⟨a, Frees.int⟩
  | view => exact fun a _ _ => ⟨a, Frees.view⟩
  | node hes ih =>
    rename_i t c d es
    intro a hn ha
    simp only [ids_node, List.nodup_cons, List.mem_cons] at hn
    have hc : a c = true := ha c (by simp)
    have hd : upd a c false d = true := by
      rw [upd_ne _ _ (fun h => hn.1 (Or.inl h.symm))]; exact ha d (by simp)
    -- free the elements one by one
    have key : ∀ (l : List Val) (b : Nat → Bool), (∀ e ∈ l, e ∈ es) → (idsL l).Nodup →
        (∀ i ∈ idsL l, b i = true) → ∃ b', FreesL b l b' := by
      intro l
      induction l with
      | nil => exact fun b _ _ _ => ⟨b, FreesL.nil⟩
      | cons e l ihl =>
        intro b hsub hnd hb
        simp only [idsL_cons, List.nodup_append] at hnd
        obtain ⟨b1, h1⟩ := ih e (hsub e (by simp)) b hnd.1 (fun i hi => hb i (by simp [hi]))
        obtain ⟨b2, h2⟩ := ihl b1 (fun x hx => hsub x (by simp [hx])) hnd.2.1 (by
          intro i hi
          have hne : i ∉ e.ids := fun h => hnd.2.2 i h i hi rfl
          rw [h1.other hne]; exact hb i (by simp [hi]))
        exact ⟨b2, FreesL.cons h1 h2⟩
    obtain ⟨a', h⟩ := key es (upd (upd a c false) d false) (fun e he => he) hn.2.2 (by
      intro i hi
      have h1 : i ≠ c := fun h => hn.1 (Or.inr (h ▸ hi))
      have h2 : i ≠ d := fun h => hn.2.1 (h ▸ hi)
      rw [upd_ne _ _ h2, upd_ne _ _ h1]; exact ha i (by simp [hi]))
    exact ⟨a', Frees.node hc hd h⟩
  | pair _ _ ihv ihw =>
    intro a hn ha
    simp only [ids_pair, List.nodup_append] at hn
    obtain ⟨a1, h1⟩ := ihv a hn.1 (fun i hi => ha i (by simp [hi]))
    obtain ⟨a2, h2⟩ := ihw a1 hn.2.1 (fun i hi => by
      have hne : i ∉ _ := fun h => hn.2.2 i h i hi rfl
      rw [h1.other hne]; exact ha i (by simp [hi]))
    exact ⟨a2, Frees.pair h1 h2⟩
  | inl _ ih =>
    intro a hn ha
    obtain ⟨a1, h1⟩ := ih a (by simpa using hn) (fun i hi => ha i (by simpa using hi))
    exact ⟨a1, Frees.inl h1⟩
  | inr _ ih =>
    intro a hn ha
    obtain ⟨a1, h1⟩ := ih a (by simpa using hn) (fun i hi => ha i (by simpa using hi))
    exact ⟨a1, Frees.inr h1⟩
  | pkg _ ih =>
    intro a hn ha
    obtain ⟨a1, h1⟩ := ih a (by simpa using hn) (fun i hi => ha i (by simpa using hi))
    exact ⟨a1, Frees.pkg h1⟩

/-! ### Owned slots after an update -/

theorem ownedAt_set {m : Mem} {x o : Var} {sl : Slot} {T : Val} :
    OwnedAt (m.set x sl) o T ↔ (o = x ∧ sl = ⟨true, some T⟩) ∨ (o ≠ x ∧ OwnedAt m o T) := by
  unfold OwnedAt
  by_cases h : o = x
  · subst h; simp [eq_comm]
  · simp [h]

theorem ownedAt_remove {m : Mem} {x o : Var} {T : Val} :
    OwnedAt (m.remove x) o T ↔ o ≠ x ∧ OwnedAt m o T := by
  unfold OwnedAt
  by_cases h : o = x
  · subst h; simp
  · simp [h]

theorem ownedAt_with {m : Mem} {a : Nat → Bool} {n : Nat} {o : Var} {T : Val} :
    OwnedAt { m with alloc := a, nid := n } o T ↔ OwnedAt m o T := Iff.rfl

theorem ownedAt_withA {m : Mem} {a : Nat → Bool} {o : Var} {T : Val} :
    OwnedAt { m with alloc := a } o T ↔ OwnedAt m o T := Iff.rfl

/-- Taking a slot's tree out (a move, a drop) keeps the others' invariant,
    whatever happens to the addresses of the tree taken out. -/
theorem HeapOK.without {m : Mem} (hh : HeapOK m) {x : Var} {T : Val} (hx : OwnedAt m x T)
    (m' : Mem) (hown : ∀ o U, OwnedAt m' o U → o ≠ x ∧ OwnedAt m o U)
    (halloc : ∀ i, i ∉ T.ids → m'.alloc i = m.alloc i) (hnid : m.nid ≤ m'.nid) : HeapOK m' where
  nodup o U hU := hh.nodup o U (hown o U hU).2
  disj o1 o2 U1 U2 hne h1 h2 := hh.disj o1 o2 U1 U2 hne (hown o1 U1 h1).2 (hown o2 U2 h2).2
  alloc o U hU i hi := by
    obtain ⟨hox, hU'⟩ := hown o U hU
    have hni : i ∉ T.ids := fun h => hh.disj o x U T hox hU' hx i hi h
    obtain ⟨ha, hlt⟩ := hh.alloc o U hU' i hi
    exact ⟨by rw [halloc i hni]; exact ha, Nat.lt_of_lt_of_le hlt hnid⟩
  self o U hU := hh.self o U (hown o U hU).2

/-- Putting a tree into a slot that held none. -/
theorem HeapOK.put {m : Mem} (hh : HeapOK m) {x : Var} {T : Val} (m' : Mem)
    (hown : ∀ o U, OwnedAt m' o U → (o = x ∧ U = T) ∨ (o ≠ x ∧ OwnedAt m o U))
    (hnx : ∀ U, ¬ OwnedAt m x U)
    (hT : T.ids.Nodup) (hTs : SelfFree T) (hTa : ∀ i ∈ T.ids, m'.alloc i = true ∧ i < m'.nid)
    (hTd : ∀ o U, OwnedAt m o U → ∀ i ∈ T.ids, i ∉ U.ids)
    (halloc : ∀ o U, OwnedAt m o U → ∀ i ∈ U.ids, m'.alloc i = m.alloc i) (hnid : m.nid ≤ m'.nid) :
    HeapOK m' where
  nodup o U hU := by
    rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact hT
    · exact hh.nodup o U h
  disj o1 o2 U1 U2 hne h1 h2 := by
    rcases hown o1 U1 h1 with ⟨rfl, rfl⟩ | ⟨ho1, h1'⟩ <;> rcases hown o2 U2 h2 with ⟨rfl, rfl⟩ | ⟨ho2, h2'⟩
    · exact absurd rfl hne
    · exact hTd o2 U2 h2'
    · exact fun i hi hi' => hTd o1 U1 h1' i hi' hi
    · exact hh.disj o1 o2 U1 U2 hne h1' h2'
  alloc o U hU i hi := by
    rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact hTa i hi
    · obtain ⟨ha, hlt⟩ := hh.alloc o U h i hi
      exact ⟨by rw [halloc o U h i hi]; exact ha, Nat.lt_of_lt_of_le hlt hnid⟩
  self o U hU := by
    rcases hown o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
    · exact hTs
    · exact hh.self o U h

/-! ### Trees that do not view themselves -/

theorem SelfFree.sub {T U : Val} (h : SelfFree T) (hs : Sub U T) : SelfFree U :=
  fun d o l hv u c es hn => h d o l (hv.trans hs) u c es (hn.trans hs)

theorem selfFree_int (n : Nat) : SelfFree (.int n) := fun _ _ _ h => by cases h

theorem selfFree_view (d o l : Nat) : SelfFree (.view d o l) :=
  fun _ _ _ _ _ _ _ h => by cases h

theorem ViewIn.sub {τ T s v} (h : ViewIn τ T s v) : Sub v T := by
  induction h with
  | here => exact Sub.refl _
  | child he _ ih => exact Sub.child he ih
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih
  | pkg _ ih => exact Sub.pkg ih

end A2
