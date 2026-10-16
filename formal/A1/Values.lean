import A1.Heap

/-! A1 — the values bindings hold, and the borrows taken from them. -/

namespace A1

theorem MInv.own_val {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hm : E.mode.ownSlot = true) :
    ∃ T, m.st y = some ⟨true, some T⟩ ∧ WFv E.ty T ∧ ViewsOK m E.ty T E.held := by
  obtain ⟨sl, hsl, _, hso, hown, _⟩ := hi.slot y E hy
  obtain ⟨_, hwf, hlv⟩ := hown hm
  obtain ⟨T, hT, hv⟩ := hlv hl
  obtain ⟨o, val⟩ := sl
  simp only at hso hT
  subst hT
  rw [hm] at hso; subst hso
  exact ⟨T, hsl, hwf T rfl, hv⟩

theorem MInv.bor_val {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hm : E.mode.ownSlot = false) :
    ∃ v, m.st y = some ⟨false, some v⟩ ∧ ValOK m E.ty v E.path E.held := by
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot y E hy
  obtain ⟨v, hv, hok⟩ := hbor hm hl
  obtain ⟨o, val⟩ := sl
  simp only at hso hv
  subst hv
  rw [hm] at hso; subst hso
  exact ⟨v, hsl, hok⟩

theorem MInv.tyok {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E) :
    E.ty.ok = true := by
  obtain ⟨_, _, h, _⟩ := hi.slot y E hy; exact h

theorem MInv.mode_cases {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry}
    (hy : Γ y = some E) : E.mode = .own ∨ E.mode = .rootb ∨ E.mode = .bor := by
  cases h : E.mode with
  | own => exact Or.inl rfl
  | inout b => exact absurd h (hi.noInout y E b hy)
  | rootb => exact Or.inr (Or.inl rfl)
  | bor => exact Or.inr (Or.inr rfl)

/-- Where a value reached through a dependency of a given kind lies. -/
def Lands (k : Kind) (n n0 : Val) : Prop :=
  k = .self ∧ n = n0 ∨ k = .view ∧ n = n0 ∨ k = .inner ∧ Below n n0

theorem hrefAt_iff {m : Mem} {dep : Dep} {c : Nat} {t : Ty} {H : List Dep} :
    HrefAt m dep c t H ↔ ∃ n0 d es, RootNode m dep.root n0 ∧ dep.kind ≠ .view ∧
      Lands dep.kind (.node t c d es) n0 ∧
      WFv (.vec t) (.node t c d es) ∧ ViewsOK m (.vec t) (.node t c d es) H := by
  constructor
  · rintro ⟨n0, d, es, hr, hk, hw, hv⟩
    refine ⟨n0, d, es, hr, ?_, ?_, hw, hv⟩
    · rcases hk with ⟨h, _⟩ | ⟨h, _⟩ <;> rw [h] <;> decide
    · rcases hk with ⟨h1, h2⟩ | ⟨h1, h2⟩
      · exact Or.inl ⟨h1, h2⟩
      · exact Or.inr (Or.inr ⟨h1, h2⟩)
  · rintro ⟨n0, d, es, hr, hk, hl, hw, hv⟩
    refine ⟨n0, d, es, hr, ?_, hw, hv⟩
    rcases hl with ⟨h1, h2⟩ | ⟨h1, _⟩ | ⟨h1, h2⟩
    · exact Or.inl ⟨h1, h2⟩
    · exact absurd h1 hk
    · exact Or.inr ⟨h1, h2⟩

theorem viewAt_iff {m : Mem} {dep : Dep} {d o l : Nat} {t : Ty} :
    ViewAt m dep d o l t ↔ ∃ n0 c es, RootNode m dep.root n0 ∧ dep.kind ≠ .self ∧
      Lands dep.kind (.node t c d es) n0 ∧ o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es) := by
  constructor
  · rintro ⟨n0, c, es, hr, hk, hl, hw⟩
    refine ⟨n0, c, es, hr, ?_, ?_, hl, hw⟩
    · rcases hk with ⟨h, _⟩ | ⟨h, _⟩ <;> rw [h] <;> decide
    · rcases hk with ⟨h1, h2⟩ | ⟨h1, h2⟩
      · exact Or.inr (Or.inl ⟨h1, h2⟩)
      · exact Or.inr (Or.inr ⟨h1, h2⟩)
  · rintro ⟨n0, c, es, hr, hk, hl', hl, hw⟩
    refine ⟨n0, c, es, hr, ?_, hl, hw⟩
    rcases hl' with ⟨h1, _⟩ | ⟨h1, h2⟩ | ⟨h1, h2⟩
    · exact absurd h1 hk
    · exact Or.inl ⟨h1, h2⟩
    · exact Or.inr ⟨h1, h2⟩

theorem Lands.sub {k : Kind} {n n0 : Val} (h : Lands k n n0) : Sub n n0 := by
  rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, hb⟩
  · exact Sub.refl _
  · exact Sub.refl _
  · exact hb.sub

/-- Every node a root reaches is inside some owned tree. -/
theorem RootNode.owned {m : Mem} {r : Var} {n : Val} (h : RootNode m r n) :
    ∃ o T, OwnedAt m o T ∧ Sub n T := by
  rcases h with h | ⟨c, _, o, T, hT, hs, _⟩ | ⟨d, _, _, _, o, T, hT, hs, _⟩
  · exact ⟨r, n, h, Sub.refl _⟩
  · exact ⟨o, T, hT, hs⟩
  · exact ⟨o, T, hT, hs⟩

/-- The `Vec` node a live binding of type `vec t` names, with the
    dependency of its own that reaches it (for a root: the binding itself). -/
theorem MInv.vec_node {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .vec t) :
    ∃ c d es, VecOf m y t c d es ∧ WFv (.vec t) (.node t c d es) ∧
      ViewsOK m (.vec t) (.node t c d es) E.held ∧
      (E.mode.isRoot = true → RootNode m y (.node t c d es)) ∧
      (E.mode = .bor → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧ dep.kind ≠ .view ∧
        Lands dep.kind (.node t c d es) n0) := by
  rcases hi.mode_cases hy with hm | hm | hm
  · have hos : E.mode.ownSlot = true := by rw [hm]; rfl
    obtain ⟨T, hT, hw, hv⟩ := hi.own_val hy hl hos
    rw [ht] at hw hv
    cases hw with
    | node hes =>
      rename_i c d es
      have ha := hi.heap.alloc y _ hT
      refine ⟨c, d, es, ⟨(ha c (by simp)).1, (ha d (by simp)).1, Or.inl hT⟩, WFv.node hes, hv,
        fun _ => Or.inl hT, fun h => by rw [hm] at h; cases h⟩
  all_goals
    have hos : E.mode.ownSlot = false := by rw [hm]; rfl
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl hos
    rw [ht] at hok
    obtain ⟨c, rfl, dep, hd, hh⟩ := hok
    obtain ⟨n0, d, es, hr, hk, hla, hw, hvs⟩ := hrefAt_iff.mp hh
    obtain ⟨o, T, hoT, hsT⟩ := hr.owned
    have hsub : Sub (.node t c d es) n0 := hla.sub
    have hna : NodeAt m c (.node t c d es) := ⟨o, T, hoT, hsub.trans hsT, t, d, es, rfl⟩
    have ha := hi.heap.alloc o T hoT
    refine ⟨c, d, es, ⟨(ha c ((hsub.trans hsT).ids c (by simp))).1,
      (ha d ((hsub.trans hsT).ids d (by simp))).1, Or.inr ⟨hv, hna⟩⟩, hw, hvs,
      fun _ => Or.inr (Or.inl ⟨c, hv, hna⟩), fun _ => ⟨dep, hd, n0, hr, hk, hla⟩⟩

/-- The buffer a live slice binding views. -/
theorem MInv.slice_node {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .slice t) :
    ∃ d o l c es, m.st y = some ⟨false, some (.view d o l)⟩ ∧ DataAt m d (.node t c d es) ∧
      m.alloc d = true ∧ o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es) ∧
      (E.mode.isRoot = true → RootNode m y (.node t c d es)) ∧
      (E.mode = .bor → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧ dep.kind ≠ .self ∧
        Lands dep.kind (.node t c d es) n0) := by
  rcases hi.mode_cases hy with hm | hm | hm
  · have hos : E.mode.ownSlot = true := by rw [hm]; rfl
    obtain ⟨sl, _, _, _, hown, _⟩ := hi.slot y E hy
    obtain ⟨⟨t', ht'⟩, _⟩ := hown hos
    rw [ht] at ht'; cases ht'
  all_goals
    have hos : E.mode.ownSlot = false := by rw [hm]; rfl
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl hos
    rw [ht] at hok
    obtain ⟨d, o, l, rfl, dep, hd, hh⟩ := hok
    obtain ⟨n0, c, es, hr, hk, hla, hlen, hw⟩ := viewAt_iff.mp hh
    obtain ⟨o', T, hoT, hsT⟩ := hr.owned
    have hsub : Sub (.node t c d es) n0 := hla.sub
    have hda : DataAt m d (.node t c d es) := ⟨o', T, hoT, hsub.trans hsT, t, c, es, rfl⟩
    have ha := hi.heap.alloc o' T hoT
    exact ⟨d, o, l, c, es, hv, hda, (ha d ((hsub.trans hsT).ids d (by simp))).1, hlen, hw,
      fun _ => Or.inr (Or.inr ⟨d, o, l, hv, hda⟩), fun _ => ⟨dep, hd, n0, hr, hk, hla⟩⟩

theorem lands_comp' {n0 n1 N : Val} {kp k : Kind} (hp : Lands kp n0 n1) (hk : Lands k N n0) :
    Lands (comp kp k) N n1 := lands_comp hp hk

/-- A borrow taken from `y` in way `k` reaches memory through `derive y E k`. -/
theorem derive_lands {m : Mem} {y : Var} {E : Entry} {N N' : Val} {k : Kind}
    (hroot : E.mode.isRoot = true → RootNode m y N)
    (hbor : E.mode.isRoot = false → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind N n0)
    (hk : Lands k N' N) (hrk : rootKind E.ty k = k) :
    ∃ dep ∈ derive y E k, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind N' n0 := by
  unfold derive
  cases h : E.mode.isRoot with
  | true =>
    simp only [↓reduceIte, List.mem_singleton]
    exact ⟨_, rfl, N, hroot h, by rw [hrk]; exact hk⟩
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map]
    obtain ⟨dep, hd, n0, hr, hl⟩ := hbor h
    exact ⟨_, ⟨dep, hd, rfl⟩, n0, hr, lands_comp' hl hk⟩

end A1
