import A2.Heap
import A2.Repl

/-! A2 — the values bindings hold, and the borrows taken from them. -/

namespace A2

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

/-- A3.1: an address of a value lying in an owned tree or a live payload is live. -/
theorem HeapOK.inMem_alloc {m : Mem} (hh : HeapOK m) {n : Val} (h : InMem m n) :
    ∀ i ∈ n.ids, m.alloc i = true := by
  intro i hi
  rcases h with ⟨o, T, hT, hs⟩ | ⟨k, bl, hk, hs⟩
  · exact (hh.alloc o T hT i (hs.ids i hi)).1
  · exact (hh.payAlloc ⟨k, bl, hk, hs.ids i hi⟩).1

/-- The `Vec` node a live binding of type `vec t` names, with the
    dependency of its own that reaches it (for a root: the binding itself). -/
theorem MInv.vec_node {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .vec t) :
    ∃ c d es, VecOf m y t c d es ∧ WFv (.vec t) (.node t c d es) ∧
      ViewsOK m (.vec t) (.node t c d es) E.held ∧
      (E.mode.isRoot = true → RootNode m y (.node t c d es)) ∧
      (E.mode = .bor → ∃ dep ∈ E.path, Landed m dep (.node t c d es)) ∧
      NamesIn (.node t c d es) E.held ∧ SharesOK m (.vec t) (.node t c d es) := by
  rcases hi.mode_cases hy with hm | hm | hm
  · have hos : E.mode.ownSlot = true := by rw [hm]; rfl
    obtain ⟨T, hT, hw, hv⟩ := hi.own_val hy hl hos
    rw [ht] at hw hv
    cases hw with
    | node hes =>
      rename_i c d es
      have ha := hi.heap.alloc y _ hT
      refine ⟨c, d, es, ⟨(ha c (by simp)).1, (ha d (by simp)).1, Or.inl hT⟩, WFv.node hes, hv,
        fun _ => Or.inl ⟨_, hT, Top.refl _⟩, (fun h => by rw [hm] at h; cases h),
        hi.held y E _ _ hy hl hT rfl,
        by have := hi.shares y E _ _ hy hT rfl rfl; rw [ht] at this; exact this⟩
  all_goals
    have hos : E.mode.ownSlot = false := by rw [hm]; rfl
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl hos
    rw [ht] at hok
    obtain ⟨c, rfl, dep, hd, hh⟩ := valOK_vec.mp hok
    obtain ⟨d, es, hla, hw, hvs, hns, hsh⟩ := hh
    have hin := hla.inMem
    have hna : NodeAt m c (.node t c d es) := hin.nodeAt rfl
    refine ⟨c, d, es, ⟨hi.heap.inMem_alloc hin c (by simp), hi.heap.inMem_alloc hin d (by simp),
      Or.inr ⟨hv, hna⟩⟩, hw, hvs,
      fun _ => Or.inr (Or.inl ⟨_, c, hv, Top.refl _, hna⟩), fun _ => ⟨dep, hd, hla⟩, hns, hsh⟩

/-- The buffer a live slice binding views. -/
theorem MInv.slice_node {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (ht : E.ty = .slice t) :
    ∃ d o l c es, m.st y = some ⟨false, some (.view d o l)⟩ ∧ DataAt m d (.node t c d es) ∧
      m.alloc d = true ∧ o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es) ∧
      (E.mode.isRoot = true → RootNode m y (.node t c d es)) ∧
      (E.mode = .bor → ∃ dep ∈ E.path, dep.kind ≠ .self ∧ Landed m dep (.node t c d es)) := by
  rcases hi.mode_cases hy with hm | hm | hm
  · have hos : E.mode.ownSlot = true := by rw [hm]; rfl
    obtain ⟨sl, _, _, _, hown, _⟩ := hi.slot y E hy
    obtain ⟨hty, _⟩ := hown hos
    rw [ht] at hty; simp [Ty.owning] at hty
  all_goals
    have hos : E.mode.ownSlot = false := by rw [hm]; rfl
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl hos
    rw [ht] at hok
    obtain ⟨d, o, l, rfl, dep, hd, hh⟩ := valOK_slice.mp hok
    obtain ⟨c, es, hk, hla, hlen, hw⟩ := hh
    have hin := hla.inMem
    have hda : DataAt m d (.node t c d es) := hin.dataAt rfl
    exact ⟨d, o, l, c, es, hv, hda, hi.heap.inMem_alloc hin d (by simp), hlen, hw,
      fun _ => Or.inr (Or.inr (Or.inl ⟨_, d, o, l, hv, Top.refl _, hda⟩)), fun _ => ⟨dep, hd, hk, hla⟩⟩

theorem lands_comp' {n0 n1 N : Val} {kp k : Kind} (hp : Lands kp n0 n1) (hk : Lands k N n0) :
    Lands (comp kp k) N n1 := lands_comp hp hk

theorem InPay.sub {m : Mem} {n n' : Val} (h : InPay m n) (hs : Sub n' n) : InPay m n' := by
  obtain ⟨k, bl, hk, h⟩ := h
  exact ⟨k, bl, hk, hs.trans h⟩

/-- What is reached inside a payload stays inside it. -/
theorem comp_share_lands {k : Kind} {N n0 : Val} (hk : Lands k N n0) : comp .share k = .share := by
  rcases hk with ⟨rfl, _⟩ | ⟨rfl, _⟩ | ⟨rfl, _⟩ <;> rfl

/-- What lands in what a dependency lands, in way `k`, lands through it with
    the composed kind. -/
theorem Landed.comp {m : Mem} {dep : Dep} {N N' : Val} {k : Kind} (h : Landed m dep N)
    (hk : Lands k N' N) : Landed m ⟨dep.root, comp dep.kind k⟩ N' := by
  rcases h with ⟨n0, hr, hl⟩ | ⟨hs, hro, hp⟩
  · exact Or.inl ⟨n0, hr, lands_comp' hl hk⟩
  · refine Or.inr ⟨?_, hro, hp.sub hk.sub⟩
    show A2.comp dep.kind k = .share
    rw [hs]; exact comp_share_lands hk

theorem ArcLanded.comp {m : Mem} {dep : Dep} {N N' : Val} {k : Kind} (h : ArcLanded m dep N)
    (hk : Lands k N' N) : ArcLanded m ⟨dep.root, comp dep.kind k⟩ N' := by
  rcases h with ⟨n0, hr, hl⟩ | ⟨hs, hro⟩
  · exact Or.inl ⟨n0, hr, lands_comp' hl hk⟩
  · refine Or.inr ⟨?_, hro⟩
    show A2.comp dep.kind k = .share
    rw [hs]; exact comp_share_lands hk

/-- A borrow taken from `y` in way `k` reaches memory through `derive y E k`. -/
theorem derive_lands {m : Mem} {y : Var} {E : Entry} {N N' : Val} {k : Kind}
    (hroot : E.mode.isRoot = true → RootNode m y N)
    (hbor : E.mode.isRoot = false → ∃ dep ∈ E.path, Landed m dep N)
    (hk : Lands k N' N) (hrk : rootKind E.ty k = k) :
    ∃ dep ∈ derive y E k, Landed m dep N' := by
  unfold derive
  cases h : E.mode.isRoot with
  | true =>
    simp only [↓reduceIte, List.mem_singleton]
    exact ⟨_, rfl, Or.inl ⟨N, hroot h, by rw [hrk]; exact hk⟩⟩
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map]
    obtain ⟨dep, hd, hla⟩ := hbor h
    exact ⟨_, ⟨dep, hd, rfl⟩, hla.comp hk⟩

/-! ### Agora #295: the node a change through a borrow finds -/

/-- A live borrow of a `Vec` whose memory roots own their slots, none
    through a share, names a node of the tree of one of them, reached as
    that dependency says; it is the only node a step may find for it
    (`NodeOf`). (A3.1: a node in a payload is reached only through a share,
    `Landed`; so with no `.share` on the path, the node is in an owned tree.) -/
theorem MInv.thru_owner {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {Ex : Entry} {t : Ty}
    (hx : Γ x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t)
    (hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ d.root = some Er ∧ Er.mode.ownSlot = true)
    (hnsh : ∀ d ∈ memDeps Ex.path, d.kind ≠ .share) :
    ∃ dep ∈ memDeps Ex.path, ∃ T n0 c d es,
      m.st x = some ⟨false, some (.href c)⟩ ∧ m.st dep.root = some ⟨true, some T⟩ ∧
      Top n0 T ∧ Lands dep.kind (.node t c d es) n0 ∧ HrefAt m dep c t Ex.held ∧
      WFv (.vec t) (.node t c d es) ∧ NodeOf m x dep.root T t c d es ∧
      (∀ o T' t' c' d' es', NodeOf m x o T' t' c' d' es' →
        o = dep.root ∧ T' = T ∧ t' = t ∧ c' = c ∧ d' = d ∧ es' = es) ∧
      SharesOK m (.vec t) (.node t c d es) := by
  have hos : Ex.mode.ownSlot = false := by rw [hmx]; rfl
  obtain ⟨v, hv, hok⟩ := hi.bor_val hx hl hos
  rw [hty] at hok
  obtain ⟨c, rfl, dep, hdp, hh⟩ := valOK_vec.mp hok
  obtain ⟨d, es, hlan, hw, hvs, hns, hsh⟩ := hh
  have hdm : dep ∈ memDeps Ex.path := List.mem_filter.mpr ⟨hdp, by simp [hlan.notName]⟩
  obtain ⟨n0, hr, hla⟩ := hlan.root (hnsh dep hdm)
  obtain ⟨Er, hEr, hEro⟩ := hro dep hdm
  obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot dep.root Er hEr
  have hsl1 : sl.own = true := by rw [hso, hEro]
  -- an owning root reaches its own tree
  obtain ⟨T, hT, htop⟩ : ∃ T, m.st dep.root = some ⟨true, some T⟩ ∧ Top n0 T := by
    rcases hr with ⟨T, h, ht⟩ | ⟨_, _, h, _⟩ | ⟨_, _, _, _, h, _⟩ | ⟨_, _, _, h, _⟩
    · exact ⟨T, h, ht⟩
    all_goals rw [hsl] at h; cases h; simp at hsl1
  have hsub : Sub (.node t c d es) T := hla.sub.trans htop.sub
  have ha := hi.heap.alloc dep.root T hT
  have hno : NodeOf m x dep.root T t c d es :=
    ⟨(ha c (hsub.ids c (by simp))).1, (ha d (hsub.ids d (by simp))).1, hT, Or.inr ⟨hv, hsub⟩⟩
  refine ⟨dep, hdm, T, n0, c, d, es, hv, hT, htop, hla, ⟨d, es, hlan, hw, hvs, hns, hsh⟩, hw, hno,
    fun o T' t' c' d' es' hno' => ?_, hsh⟩
  obtain ⟨_, _, hT', hcase⟩ := hno'
  rcases hcase with ⟨rfl, _⟩ | ⟨hv', hsub'⟩
  · rw [hv] at hT'; cases hT'
  · rw [hv] at hv'; cases hv'
    obtain ⟨rfl, heq⟩ := owned_unique hi.heap hT' hT hsub' hsub (i := c) (by simp [Val.head])
      (by simp [Val.head])
    cases heq
    rw [hT] at hT'; cases hT'
    exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

end A2
