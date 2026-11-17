import A2.Heap
import A2.Repl
import A2.Sweep

/-! A2 — the values bindings hold, and the borrows taken from them. -/

namespace A2

/-- A2-drop.3b: an owner's slot holds a tree of its type, live or not. -/
theorem MInv.own_wfv {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hm : E.mode.ownSlot = true) {o : Bool} {T : Val} (hsl : m.st y = some ⟨o, some T⟩) :
    WFv E.ty T := by
  obtain ⟨sl, hsl', _, hso, hown, _⟩ := hi.slot y E hy
  obtain ⟨_, hwf, _⟩ := hown hm
  rw [hsl] at hsl'; cases hsl'
  exact hwf T rfl

/-- ... so a `Vec`'s is a node, and a destructor value's is not. -/
theorem WFv.vec_isNode {t : Ty} {T : Val} (h : WFv (.vec t) T) : T.isNode = true := by
  cases h; rfl

theorem WFv.dtor_isNode {f : Nat} {t : Ty} {T : Val} (h : WFv (.dtor f t) T) : T.isNode = false := by
  obtain ⟨hst, hw⟩ := WFv.dtor_iff.mp h
  cases t <;> simp [Ty.isStruct] at hst <;> cases hw <;> rfl

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
  · exact (hh.payAlloc (hh.rd_ids hk (hs.ids i hi))).1

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
    rcases hr with ⟨T, h, ht⟩ | ⟨_, _, h, _⟩ | ⟨_, _, _, _, h, _⟩ | ⟨_, _, _, h, _⟩ | ⟨_, _, h, _⟩
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

namespace A2

/-! ### AGORA-901: where a borrow's node lies -/

/-- What a block's holders read is the payload of a block: an `Arc`'s own,
    or, for a read guard's view, its lock block's (`ViewsAt`). -/
theorem ViewsAt.rd_pay {m : Mem} (hv : ViewsAt m.blk) {k : Nat} {bl : Blk} (hk : m.blk k = some bl)
    {i : Nat} (h : i ∈ bl.rd.ids) : PayAddr m i := by
  obtain ⟨t, kd, p⟩ := bl
  cases kd with
  | arc => exact ⟨k, _, hk, h⟩
  | lock => simp [Blk.rd] at h
  | dead => simp [Blk.rd] at h
  | view =>
    obtain ⟨k0, t0, q, hbl, hk0⟩ := hv k _ hk rfl
    cases hbl
    refine ⟨k0, _, hk0, ?_⟩
    simp only [Blk.rd_view, Option.getD_some, Val.ids, List.mem_append] at h
    rcases h with h | h
    · simp at h
    · simpa [Blk.tree] using h

/-- A value inside a payload holders read has only payload addresses. -/
theorem InPay.payAddr {m : Mem} (hh : HeapOK m) {n : Val} (h : InPay m n) : ∀ i ∈ n.ids, PayAddr m i := by
  obtain ⟨k, bl, hk, hs⟩ := h
  exact fun i hi => hh.views.rd_pay hk (hs.ids i hi)

/-- A node a dependency lands on lies in an owned tree or in a payload. -/
theorem Landed.home {m : Mem} {dep : Dep} {t : Ty} {c d : Nat} {es : List Val}
    (h : Landed m dep (.node t c d es)) :
    (∃ x T, m.st x = some ⟨true, some T⟩ ∧ Sub (.node t c d es) T) ∨ InPay m (.node t c d es) := by
  rcases h with ⟨n0, hr, hla⟩ | ⟨_, _, hp⟩
  · have hs := hla.sub
    rcases hr with ⟨T, hT, htop⟩ | ⟨v, c', _, _, hna⟩ | ⟨v, d', o, l, _, _, hda⟩ |
      ⟨v, k, q, _, _, rfl⟩ | ⟨v, k, _, _, rfl⟩
    · exact Or.inl ⟨dep.root, T, hT, hs.trans htop.sub⟩
    · rcases hna with ⟨x, T, hT, hsT, _⟩ | ⟨k, bl, hk, hsb, _⟩
      · exact Or.inl ⟨x, T, hT, hs.trans hsT⟩
      · exact Or.inr ⟨k, bl, hk, hs.trans hsb⟩
    · rcases hda with ⟨x, T, hT, hsT, _⟩ | ⟨k, bl, hk, hsb, _⟩
      · exact Or.inl ⟨x, T, hT, hs.trans hsT⟩
      · exact Or.inr ⟨k, bl, hk, hs.trans hsb⟩
    · rcases hs.cases' with h | ⟨e, hc, _⟩
      · cases h
      · cases hc
    · rcases hs.cases' with h | ⟨e, hc, _⟩
      · cases h
      · cases hc
  · exact Or.inr hp

/-- A handle a borrowed value is lands through one of its dependencies. -/
theorem ValOK.href_at {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ c, v = .href c → ∃ dep ∈ P, ∃ t, HrefAt m dep c t H := by
  induction h with
  | href h =>
    intro c hc; cases hc
    obtain ⟨dep, hd, hh⟩ := h
    exact ⟨dep, hd, _, hh⟩
  | dtor _ ih => exact ih
  | _ => intro c hc; cases hc

/-- **A live borrow's node** lies in an owned tree, or its address is a
    payload's. -/
theorem MInv.href_home {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hos : E.mode.ownSlot = false) {c : Nat}
    (hs : m.st y = some ⟨false, some (.href c)⟩) :
    (∃ x T, m.st x = some ⟨true, some T⟩ ∧ c ∈ T.ids) ∨ PayAddr m c := by
  obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl hos
  rw [hs] at hv; cases hv
  obtain ⟨dep, _, t, d, es, hlan, _⟩ := hok.href_at c rfl
  rcases hlan.home with ⟨x, T, hT, hsT⟩ | hp
  · exact Or.inl ⟨x, T, hT, hsT.ids c (by simp [Val.ids])⟩
  · exact Or.inr (hp.payAddr hi.heap c (by simp [Val.ids]))

/-! ### AGORA-901: nodes no package holds -/

/-- No package of an owned tree holds `n` in its environment. -/
def PkgFreeAt (m : Mem) (n : Val) : Prop :=
  ∀ r T, m.st r = some ⟨true, some T⟩ → ∀ fs te ms ev cs, Sub (.pkg fs te ms ev cs) T → ¬ Sub n ev

/-- Nothing lies strictly inside itself. -/
theorem Below.irrefl {a : Val} (h : Below a a) : False := by
  obtain ⟨e, hc, hs⟩ := h
  exact Nat.lt_irrefl _ (Nat.lt_of_le_of_lt hs.sizeOf_le hc.sizeOf_lt)

/-- A part of a tree whose addresses are distinct has distinct addresses. -/
theorem Sub.nodup {a b : Val} (h : Sub a b) (hn : b.ids.Nodup) : a.ids.Nodup := by
  induction h with
  | refl => exact hn
  | child he _ ih => exact ih (Child.nodup (Child.elem he) hn)
  | fst _ ih => exact ih (Child.nodup Child.fst hn)
  | snd _ ih => exact ih (Child.nodup Child.snd hn)
  | inl _ ih => exact ih (Child.nodup Child.inl hn)
  | inr _ ih => exact ih (Child.nodup Child.inr hn)
  | pkg _ ih => exact ih (Child.nodup Child.pkg hn)

/-- In a tree whose addresses are distinct, two subtrees sharing an address
    lie one inside the other. -/
theorem sub_nested {t a b : Val} (hn : t.ids.Nodup) (ha : Sub a t) (hb : Sub b t) {i : Nat}
    (hia : i ∈ a.ids) (hib : i ∈ b.ids) : Sub a b ∨ Sub b a := by
  rcases ha.cases' with h | ⟨ea, hca, hsa⟩
  · subst h; exact Or.inr hb
  rcases hb.cases' with h | ⟨eb, hcb, hsb⟩
  · subst h; exact Or.inl ha
  have heq := Child.same hca hcb hn (hsa.ids i hia) (hsb.ids i hib)
  subst heq
  exact sub_nested (hca.nodup hn) hsa hsb hia hib
termination_by sizeOf t
decreasing_by exact hca.sizeOf_lt

/-- An address of a node no package holds, by value, is one no package
    holds by address, wherever the node lies. -/
theorem PkgFreeAt.toId {m : Mem} (hh : HeapOK m) {n : Val}
    (hhome : (∃ r0 T0, m.st r0 = some ⟨true, some T0⟩ ∧ Sub n T0) ∨ InPay m n)
    (h : PkgFreeAt m n) {i : Nat} (hi : i ∈ n.head) : PkgFreeId m i := by
  intro r T hT fs te ms ev cs hP t c d es hN
  have key : i ∈ (Val.node t c d es).head → False := fun hi' => by
    have hsT : Sub (.node t c d es) T := hN.trans ((Sub.pkg (Sub.refl _)).trans hP)
    rcases hhome with ⟨r0, T0, hT0, hs0⟩ | hp
    · obtain ⟨_, heq⟩ := owned_unique hh hT hT0 hsT hs0 hi' hi
      rw [heq] at hN
      exact h r T hT fs te ms ev cs hP hN
    · exact hh.notPay hT (hsT.ids i (Val.head_ids _ i hi')) (hp.payAddr hh i (Val.head_ids _ i hi))
  exact ⟨fun h1 => key (by simp [Val.head, h1]), fun h2 => key (by simp [Val.head, h2])⟩

/-- A node of an address no package holds no package holds. -/
theorem PkgFreeId.at {m : Mem} {i : Nat} (h : PkgFreeId m i) {n : Val} (hn : i ∈ n.head) :
    PkgFreeAt m n := by
  intro r T hT fs te ms ev cs hP hN
  cases n with
  | node t c d es =>
    obtain ⟨h1, h2⟩ := h r T hT fs te ms ev cs hP t c d es hN
    simp [Val.head] at hn
    rcases hn with rfl | rfl
    · exact h1 rfl
    · exact h2 rfl
  | _ => simp [Val.head] at hn

/-- What lies in no owned tree no package of one holds. -/
theorem PkgFreeAt.of_notOwned {m : Mem} {n : Val} {i : Nat} (hi : i ∈ n.ids)
    (h : ∀ r T, m.st r = some ⟨true, some T⟩ → i ∉ T.ids) : PkgFreeAt m n :=
  fun r T hT _ _ _ _ _ hP hN => h r T hT (hP.ids i (Child.ids Child.pkg i (hN.ids i hi)))

/-- An owned tree's top no package holds. -/
theorem PkgFreeAt.top {m : Mem} (hh : HeapOK m) {y : Var} {Ty0 : Val} (hy : m.st y = some ⟨true, some Ty0⟩)
    {i : Nat} (hi : i ∈ Ty0.ids) : PkgFreeAt m Ty0 := by
  intro r T hT fs te ms ev cs hP hN
  have hiT : i ∈ T.ids := hP.ids i (Child.ids Child.pkg i (hN.ids i hi))
  by_cases hry : r = y
  · subst hry; rw [hy] at hT; cases hT
    exact Below.irrefl ⟨ev, Child.pkg, hP.trans hN⟩
  · exact hh.disj r y T Ty0 hry hT hy i hiT hi

/-- **A part no package holds passes it on** to each of its parts but a
    package's environment: within the owned tree it lies in, a package
    holding the part holds it, or lies inside it, at the part itself. -/
theorem PkgFreeAt.child {m : Mem} (hh : HeapOK m) {r0 : Var} {T0 n0 n : Val}
    (hT0 : m.st r0 = some ⟨true, some T0⟩) (hs0 : Sub n0 T0) (hf : PkgFreeAt m n0)
    (hnp : ∀ fs te ms ev cs, n0 ≠ .pkg fs te ms ev cs) (hc : Child n n0) {i : Nat} (hi : i ∈ n.ids) :
    PkgFreeAt m n := by
  intro r T hT fs te ms ev cs hP hN
  have hiP : i ∈ (Val.pkg fs te ms ev cs).ids := Child.ids Child.pkg i (hN.ids i hi)
  have hi0 : i ∈ n0.ids := hc.ids i hi
  have hrr : r = r0 := Classical.byContradiction fun hne =>
    hh.disj r r0 T T0 hne hT hT0 i (hP.ids i hiP) (hs0.ids i hi0)
  subst hrr; rw [hT0] at hT; cases hT
  have hnd := hh.nodup _ _ hT0
  rcases sub_nested hnd hs0 hP hi0 hiP with h | h
  · rcases h.cases' with h | ⟨e, hce, hse⟩
    · exact hnp fs te ms ev cs h
    · cases hce
      exact hf _ _ hT0 fs te ms ev cs hP hse
  · rcases h.cases' with h | ⟨e, hce, hse⟩
    · exact hnp fs te ms ev cs h.symm
    · have heq := Child.same hce hc (hs0.nodup hnd) (hse.ids i hiP) hi
      subst heq
      exact Below.irrefl ⟨ev, Child.pkg, hse.trans hN⟩

theorem WFv.href_false {τ : Ty} {c : Nat} (h : WFv τ (.href c)) : False := by
  generalize hv : (Val.href c) = v at h
  induction h with
  | dtor _ _ ih => exact ih hv
  | _ => cases hv

/-- A handle lent out of an owned value is a node's. -/
theorem lendOf_href {τ : Ty} {e : Val} (hw : WFv τ e) {c : Nat} (h : lendOf e = .href c) :
    ∃ t d es, e = .node t c d es := by
  cases e with
  | node t c' d es => simp [lendOf] at h; subst h; exact ⟨t, d, es, rfl⟩
  | href => exact hw.href_false.elim
  | _ => simp [lendOf] at h

theorem comp_isName {a b : Kind} (ha : a.isName = false) (hb : b.isName = false) :
    (comp a b).isName = false := by
  cases a <;> cases b <;> simp_all [comp, Kind.isName]

theorem comp_share {a b : Kind} (hb : b.isName = false) (h : comp a b ≠ .share) : a ≠ .share := by
  rintro rfl; cases b <;> simp_all [comp, Kind.isName]

/-- What is borrowed from `y` in a way `k` (no share, nothing by name)
    through clean roots only: `y` is clean, if it is a root, or else every
    memory dependency of its path is clean and no share. -/
theorem derive_clean {Γ : Ctx} {y : Var} {E : Entry} {k : Kind} (hkn : k.isName = false)
    (h : ∀ d ∈ memDeps (derive y E k), d.kind ≠ .share ∧ Clean Γ d.root) :
    (E.mode.isRoot = true → Clean Γ y) ∧
    (E.mode.isRoot = false → ∀ d ∈ memDeps E.path, d.kind ≠ .share ∧ Clean Γ d.root) := by
  refine ⟨fun hr => ?_, fun hr d hd => ?_⟩
  · have hmem : (⟨y, rootKind E.ty k⟩ : Dep) ∈ memDeps (derive y E k) := by
      unfold derive memDeps; rw [ite_eq_left hr]
      rcases rootKind_cases E.ty k with h | ⟨_, h⟩ <;> rw [h]
      · simp only [List.filter_cons, List.filter_nil, hkn, Bool.not_false, if_true, List.mem_singleton]
      · simp [Kind.isName]
    exact (h _ hmem).2
  · obtain ⟨hd, hdn⟩ := List.mem_filter.mp hd
    have hmem : (⟨d.root, comp d.kind k⟩ : Dep) ∈ memDeps (derive y E k) := by
      unfold derive memDeps; rw [if_neg (by simp [hr])]
      refine List.mem_filter.mpr ⟨List.mem_map_of_mem hd, ?_⟩
      simp only [Bool.not_eq_true'] at hdn ⊢
      simpa using comp_isName (by simpa using hdn) hkn
    obtain ⟨h1, h2⟩ := h _ hmem
    exact ⟨comp_share hkn h1, h2⟩

/-- **The node a live binding names**, through clean roots only, no package
    holds, and it lies in an owned tree or in a payload. -/
theorem MInv.vecOf_free {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {t : Ty} {c d : Nat} {es : List Val} (hvec : VecOf m y t c d es)
    {k : Kind} (hkn : k.isName = false)
    (hcl : ∀ d ∈ memDeps (derive y E k), d.kind ≠ .share ∧ Clean Γ d.root) :
    PkgFreeAt m (.node t c d es) ∧
      ((∃ r0 T0, m.st r0 = some ⟨true, some T0⟩ ∧ Sub (.node t c d es) T0) ∨ InPay m (.node t c d es)) := by
  obtain ⟨_, _, hv⟩ := hvec
  rcases hv with hv | ⟨hv, hna⟩
  · exact ⟨PkgFreeAt.top hi.heap hv (i := c) (by simp [Val.ids]), Or.inl ⟨y, _, hv, Sub.refl _⟩⟩
  · obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot y E hy
    rw [hv] at hsl; cases hsl
    have hos : E.mode.ownSlot = false := hso.symm
    have hfree : PkgFreeId m c := by
      obtain ⟨hroot, hbor⟩ := derive_clean hkn hcl
      cases hm : E.mode with
      | bor => exact hi.pkgFree y E _ _ hy (Or.inl hl) hv c (PkgNames.href (Or.inl hm) (hbor (by rw [hm]; rfl)) c)
      | rootb =>
        exact hi.pkgFree y E _ _ hy (Or.inl hl) hv c
          (PkgNames.href (Or.inr hm) ((hroot (by rw [hm]; rfl)).rootb_inv hy hm) c)
      | _ => rw [hm] at hos; cases hos
    refine ⟨hfree.at (by simp [Val.head]), ?_⟩
    rcases hna with ⟨x, T, hT, hs, _⟩ | ⟨k', bl, hk, hs, _⟩
    · exact Or.inl ⟨x, T, hT, hs⟩
    · exact Or.inr ⟨k', bl, hk, hs⟩

/-- ... and so is each of a part's parts but a package's environment. -/
theorem PkgFreeAt.child' {m : Mem} (hh : HeapOK m) {n0 n : Val}
    (hhome : (∃ r0 T0, m.st r0 = some ⟨true, some T0⟩ ∧ Sub n0 T0) ∨ InPay m n0) (hf : PkgFreeAt m n0)
    (hnp : ∀ fs te ms ev cs, n0 ≠ .pkg fs te ms ev cs) (hc : Child n n0) {i : Nat} (hi : i ∈ n.ids) :
    PkgFreeAt m n := by
  rcases hhome with ⟨r0, T0, hT0, hs0⟩ | hp
  · exact PkgFreeAt.child hh hT0 hs0 hf hnp hc hi
  · exact PkgFreeAt.of_notOwned hi fun r T hT hiT =>
      hh.notPay hT hiT ((hp.sub (hc.sub (Sub.refl _))).payAddr hh i hi)

theorem home_child {m : Mem} {n0 n : Val} (hc : Child n n0)
    (hhome : (∃ r0 T0, m.st r0 = some ⟨true, some T0⟩ ∧ Sub n0 T0) ∨ InPay m n0) :
    (∃ r0 T0, m.st r0 = some ⟨true, some T0⟩ ∧ Sub n T0) ∨ InPay m n := by
  rcases hhome with ⟨r0, T0, hT0, hs0⟩ | hp
  · exact Or.inl ⟨r0, T0, hT0, (hc.sub (Sub.refl _)).trans hs0⟩
  · exact Or.inr (hp.sub (hc.sub (Sub.refl _)))

/-! ### AGORA-901: what is lent of a part no package holds -/

/-- Where a value lies: in an owned tree, or in a payload. -/
abbrev Home (m : Mem) (e : Val) : Prop :=
  (∃ r0 T0, m.st r0 = some ⟨true, some T0⟩ ∧ Sub e T0) ∨ InPay m e

theorem bare_lend_ids : ∀ (e : Val), (∀ c', ¬ Sub (.href c') e) → ∀ {c : Nat},
    Bare (.href c) (lendOf e) → c ∈ e.ids
  | .node t c0 d es, _, c, hb => by
    have := Bare.href_eq (by simpa [lendOf] using hb); subst this; simp [Val.ids]
  | .pair a b, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | fst h => simp [Val.ids, bare_lend_ids a (fun c' h' => hnh c' (Sub.fst h')) h]
    | snd h => simp [Val.ids, bare_lend_ids b (fun c' h' => hnh c' (Sub.snd h')) h]
  | .inl a, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inl h => simpa [Val.ids] using bare_lend_ids a (fun c' h' => hnh c' (Sub.inl h')) h
  | .inr a, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inr h => simpa [Val.ids] using bare_lend_ids a (fun c' h' => hnh c' (Sub.inr h')) h
  | .href c0, hnh, _, _ => absurd (Sub.refl _) (hnh c0)
  | .int _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .view _ _ _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .pkg _ _ _ _ _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .arc _ _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .lk _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .cell _, _, _, hb => by simp only [lendOf] at hb; cases hb

/-- **What is lent of a part no package holds** names, by its handles, only
    nodes no package holds, each a part of it: lending replaces each node at
    the top of the part, through fields and payloads only (never a package's
    environment, which `lendOf` lends whole), by its handle. -/
theorem lend_href_free {m : Mem} (hh : HeapOK m) : ∀ (e : Val), Home m e → PkgFreeAt m e →
    (∀ c', ¬ Sub (.href c') e) → ∀ {c : Nat}, Bare (.href c) (lendOf e) →
      PkgFreeId m c ∧ ∃ t d es, Sub (.node t c d es) e
  | .node t c0 d es, hhome, hf, _, c, hb => by
    have := Bare.href_eq (by simpa [lendOf] using hb); subst this
    exact ⟨hf.toId hh hhome (by simp [Val.head]), t, d, es, Sub.refl _⟩
  | .pair a b, hhome, hf, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | fst h =>
      have hna : ∀ c', ¬ Sub (.href c') a := fun c' h' => hnh c' (Sub.fst h')
      obtain ⟨hfr, t, d, es, hs⟩ := lend_href_free hh a (home_child Child.fst hhome)
        (hf.child' hh hhome (fun _ _ _ _ _ h => by cases h) Child.fst (bare_lend_ids a hna h)) hna h
      exact ⟨hfr, t, d, es, Sub.fst hs⟩
    | snd h =>
      have hnb : ∀ c', ¬ Sub (.href c') b := fun c' h' => hnh c' (Sub.snd h')
      obtain ⟨hfr, t, d, es, hs⟩ := lend_href_free hh b (home_child Child.snd hhome)
        (hf.child' hh hhome (fun _ _ _ _ _ h => by cases h) Child.snd (bare_lend_ids b hnb h)) hnb h
      exact ⟨hfr, t, d, es, Sub.snd hs⟩
  | .inl a, hhome, hf, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inl h =>
      have hna : ∀ c', ¬ Sub (.href c') a := fun c' h' => hnh c' (Sub.inl h')
      obtain ⟨hfr, t, d, es, hs⟩ := lend_href_free hh a (home_child Child.inl hhome)
        (hf.child' hh hhome (fun _ _ _ _ _ h => by cases h) Child.inl (bare_lend_ids a hna h)) hna h
      exact ⟨hfr, t, d, es, Sub.inl hs⟩
  | .inr a, hhome, hf, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inr h =>
      have hna : ∀ c', ¬ Sub (.href c') a := fun c' h' => hnh c' (Sub.inr h')
      obtain ⟨hfr, t, d, es, hs⟩ := lend_href_free hh a (home_child Child.inr hhome)
        (hf.child' hh hhome (fun _ _ _ _ _ h => by cases h) Child.inr (bare_lend_ids a hna h)) hna h
      exact ⟨hfr, t, d, es, Sub.inr hs⟩
  | .href c0, _, _, hnh, _, _ => absurd (Sub.refl _) (hnh c0)
  | .int _, _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .view _ _ _, _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .pkg _ _ _ _ _, _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .arc _ _, _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .lk _, _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .cell _, _, _, _, _, hb => by simp only [lendOf] at hb; cases hb

/-- A view lent of a value is one it holds, through fields and payloads. -/
theorem bare_lend_view : ∀ (e : Val) {d o l : Nat}, Bare (.view d o l) (lendOf e) → Sub (.view d o l) e
  | .node _ _ _ _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .pair a b, _, _, _, hb => by
    simp only [lendOf] at hb
    cases hb with
    | fst h => exact Sub.fst (bare_lend_view a h)
    | snd h => exact Sub.snd (bare_lend_view b h)
  | .inl a, _, _, _, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inl h => exact Sub.inl (bare_lend_view a h)
  | .inr a, _, _, _, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inr h => exact Sub.inr (bare_lend_view a h)
  | .view _ _ _, _, _, _, hb => by
    simp only [lendOf] at hb; cases hb; exact Sub.refl _
  | .href _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .int _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .pkg _ _ _ _ _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .arc _ _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .lk _, _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .cell _, _, _, _, hb => by simp only [lendOf] at hb; cases hb

theorem bare_lend_node : ∀ (e : Val), (∀ c', ¬ Sub (.href c') e) → ∀ {c : Nat},
    Bare (.href c) (lendOf e) → ∃ t d es, Sub (.node t c d es) e
  | .node t c0 d es, _, c, hb => by
    have := Bare.href_eq (by simpa [lendOf] using hb); subst this; exact ⟨t, d, es, Sub.refl _⟩
  | .pair a b, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | fst h =>
      obtain ⟨t, d, es, hs⟩ := bare_lend_node a (fun c' h' => hnh c' (Sub.fst h')) h
      exact ⟨t, d, es, Sub.fst hs⟩
    | snd h =>
      obtain ⟨t, d, es, hs⟩ := bare_lend_node b (fun c' h' => hnh c' (Sub.snd h')) h
      exact ⟨t, d, es, Sub.snd hs⟩
  | .inl a, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inl h =>
      obtain ⟨t, d, es, hs⟩ := bare_lend_node a (fun c' h' => hnh c' (Sub.inl h')) h
      exact ⟨t, d, es, Sub.inl hs⟩
  | .inr a, hnh, c, hb => by
    simp only [lendOf] at hb
    cases hb with
    | inr h =>
      obtain ⟨t, d, es, hs⟩ := bare_lend_node a (fun c' h' => hnh c' (Sub.inr h')) h
      exact ⟨t, d, es, Sub.inr hs⟩
  | .href c0, hnh, _, _ => absurd (Sub.refl _) (hnh c0)
  | .int _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .view _ _ _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .pkg _ _ _ _ _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .arc _ _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .lk _, _, _, hb => by simp only [lendOf] at hb; cases hb
  | .cell _, _, _, hb => by simp only [lendOf] at hb; cases hb

theorem lendOf_view {e : Val} {d o l : Nat} (h : lendOf e = .view d o l) : e = .view d o l := by
  cases e <;> simp_all [lendOf]

/-- **The projection lemma** (AGORA-901): what a borrow lent out of a part
    `e` of an owned tree or a payload names, `e`'s own place and views say:
    its handles' nodes are parts of `e` no package holds, given that none
    holds `e` (`lend_href_free`); the views it holds or that those nodes store
    are `e`'s. -/
theorem lend_pkgNames {m : Mem} {Γ : Ctx} (hh : HeapOK m) {e : Val} (hhome : Home m e)
    (hnh : ∀ c', ¬ Sub (.href c') e) {E' : Entry} (hm : E'.mode = .bor)
    (hf : CleanDeps Γ E'.path → (∃ c, Bare (.href c) (lendOf e)) → PkgFreeAt m e)
    (hvw : CleanDeps Γ E'.held → ∀ i o l, Sub (.view i o l) e → PkgFreeId m i)
    (hvtop : CleanDeps Γ E'.path → ∀ i o l, e = .view i o l → PkgFreeId m i)
    {i : Nat} (hn : PkgNames m Γ E' (lendOf e) i) : PkgFreeId m i := by
  rcases hn with ⟨_, hc, ⟨c, hb, hic⟩ | ⟨o, l, hv⟩⟩ | ⟨_, hc, o, l, hb⟩ |
      ⟨_, hc, c, r, T, t, d, es, hb, hT, hs, o, l, hv⟩ | ⟨hos, _⟩
  · subst hic; exact (lend_href_free hh e hhome (hf hc ⟨_, hb⟩) hnh hb).1
  · exact hvtop hc i o l (lendOf_view hv)
  · exact hvw hc.right i o l (bare_lend_view e hb)
  · obtain ⟨t', d', es', hse⟩ := bare_lend_node e hnh hb
    rcases hhome with ⟨r0, T0, hT0, hs0⟩ | hp
    · obtain ⟨_, heq⟩ := owned_unique hh hT hT0 hs (hse.trans hs0) (i := c) (by simp [Val.head])
        (by simp [Val.head])
      rw [heq] at hv
      exact hvw hc i o l (hv.trans hse)
    · exact (hh.notPay hT (hs.ids c (by simp [Val.ids])) ((hp.sub hse).payAddr hh c (by simp [Val.ids]))).elim
  · rw [hm] at hos; cases hos

/-- A value of a type that holds no view holds none. -/
theorem WFv.noView {τ : Ty} {v : Val} (hw : WFv τ v) (hhv : τ.holdsView = false) {d o l : Nat} :
    ¬ Sub (.view d o l) v := by
  induction hw with
  | int => intro h; cases h
  | view => simp [Ty.holdsView] at hhv
  | arc => intro h; cases h
  | lk => intro h; cases h
  | cell => intro h; cases h
  | rguard => intro h; cases h
  | pkg _ hq ih => intro h; cases h with | pkg h => exact ih (hq.1 hhv).1 h
  | node _ ih =>
    intro h
    cases h with
    | child he hs => exact ih _ he (by simpa [Ty.holdsView] using hhv) hs
  | pair _ _ iha ihb =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    intro h
    cases h with
    | fst h => exact iha hhv.1 h
    | snd h => exact ihb hhv.2 h
  | inl _ ih =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    intro h; cases h with | inl h => exact ih hhv.1 h
  | inr _ ih =>
    simp only [Ty.holdsView, Bool.or_eq_false_iff] at hhv
    intro h; cases h with | inr h => exact ih hhv.2 h
  | dtor _ _ ih => exact ih (by simpa [Ty.holdsView] using hhv)

/-- An owned value holds no handle. -/
theorem WFv.noHref {τ : Ty} {v : Val} (hw : WFv τ v) {c : Nat} : ¬ Sub (.href c) v := by
  induction hw with
  | int => intro h; cases h
  | view => intro h; cases h
  | arc => intro h; cases h
  | lk => intro h; cases h
  | cell => intro h; cases h
  | rguard => intro h; cases h
  | pkg _ _ ih => intro h; cases h with | pkg h => exact ih h
  | node _ ih =>
    intro h
    cases h with
    | child he hs => exact ih _ he hs
  | pair _ _ iha ihb =>
    intro h
    cases h with
    | fst h => exact iha h
    | snd h => exact ihb h
  | inl _ ih => intro h; cases h with | inl h => exact ih h
  | inr _ ih => intro h; cases h with | inr h => exact ih h
  | dtor _ _ ih => exact ih

/-- No payload holders read holds a view (`MInv.blocks`: no block's type
    holds one). -/
theorem MInv.noViewPay {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {d o l : Nat} : ¬ InPay m (.view d o l) := by
  rintro ⟨k', bl, hk, hs⟩
  obtain ⟨_, hhv, hpay, _⟩ := hi.blocks k' bl hk
  have hrd : bl.rd = .int 0 ∨ ∃ p, bl.pay = some p ∧ bl.rd = p := by
    obtain ⟨ty, kd, pay⟩ := bl
    cases kd <;> cases pay <;> simp [Blk.rd, Blk.tree]
  rcases hrd with h | ⟨p, hp, h⟩
  · rw [h] at hs; cases hs
  · rw [h] at hs
    exact (hpay p hp).1.noView hhv hs

/-- **The views of the node a live binding names** have addresses no
    package holds, when what it holds reaches memory through clean roots only
    and no share: an owner's tree's views, or a borrow's pointee's (in an
    owned tree: no payload holds a view). -/
theorem MInv.vecOf_views {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {t : Ty} {c d : Nat} {es : List Val} (hvec : VecOf m y t c d es)
    (hc : CleanDeps Γ E.held) : ∀ i o l, Sub (.view i o l) (.node t c d es) → PkgFreeId m i := by
  intro i o l hv
  obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot y E hy
  obtain ⟨_, _, hvv⟩ := hvec
  rcases hvv with hst | ⟨hst, hna⟩
  · rw [hst] at hsl; cases hsl
    exact hi.pkgFree y E true _ hy (Or.inl hl) hst i (Or.inr (Or.inr (Or.inr ⟨hso.symm, hc, o, l, hv⟩)))
  · rw [hst] at hsl; cases hsl
    have hm : E.mode = .bor ∨ E.mode = .rootb := by
      have h := hso.symm
      cases hm : E.mode <;> simp_all [Mode.ownSlot]
    rcases hna with ⟨r, T, hT, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
    · exact hi.pkgFree y E false _ hy (Or.inl hl) hst i
        (Or.inr (Or.inr (Or.inl ⟨hm, hc, c, r, T, t, d, es, .refl _, hT, hs, o, l, hv⟩)))
    · exact (hi.noViewPay ⟨k, bl, hk, hv.trans hs⟩).elim

theorem VecOf.home {m : Mem} {y : Var} {t : Ty} {c d : Nat} {es : List Val} (h : VecOf m y t c d es) :
    Home m (.node t c d es) := by
  obtain ⟨_, _, hv⟩ := h
  rcases hv with hv | ⟨_, hna⟩
  · exact Or.inl ⟨y, _, hv, Sub.refl _⟩
  · rcases hna with ⟨x, T, hT, hs, _⟩ | ⟨k, bl, hk, hs, _⟩
    · exact Or.inl ⟨x, T, hT, hs⟩
    · exact Or.inr ⟨k, bl, hk, hs⟩

/-- What is borrowed from a borrow or a borrowed parameter through clean
    roots only and no share depends, through its path, on clean roots only. -/
theorem derive_clean_path {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E)
    (hm : E.mode = .bor ∨ E.mode = .rootb) {k : Kind} (hkn : k.isName = false)
    (h : CleanDeps Γ (derive y E k)) : CleanDeps Γ E.path := by
  obtain ⟨hr, hb⟩ := derive_clean hkn h
  rcases hm with hm | hm
  · exact hb (by rw [hm]; rfl)
  · exact (hr (by rw [hm]; rfl)).rootb_inv hy hm

/-- A borrowed slot is a borrow's or a borrowed parameter's. -/
theorem MInv.bor_mode {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    {v : Val} (hv : m.st y = some ⟨false, some v⟩) : E.mode = .bor ∨ E.mode = .rootb := by
  obtain ⟨sl, hsl, _, hso, _⟩ := hi.slot y E hy
  rw [hv] at hsl; cases hsl
  have h := hso.symm
  cases hm : E.mode <;> simp_all [Mode.ownSlot]

/-- An owned value is no view: only a slice's is, and a slice owns nothing. -/
theorem WFv.owning_noView {τ : Ty} {v : Val} (hw : WFv τ v) (ho : τ.owning = true) {d o l : Nat} :
    v ≠ .view d o l := by
  induction hw with
  | view => simp [Ty.owning] at ho
  | dtor hs _ ih => exact ih (Ty.owning_of_isStruct hs)
  | int | node | pair | inl | inr | pkg | arc | lk | cell | rguard => intro h; cases h

theorem WFv.view_holdsView {τ : Ty} {d o l : Nat} (h : WFv τ (.view d o l)) : τ.holdsView = true := by
  generalize hv : (Val.view d o l) = v at h
  induction h with
  | view => rfl
  | dtor _ _ ih => simpa [Ty.holdsView] using ih hv
  | _ => cases hv

/-- Every view a well-formed value holds is one `ViewIn` reaches. -/
theorem WFv.viewIn {τ : Ty} {T : Val} (hw : WFv τ T) {d o l : Nat} (hs : Sub (.view d o l) T) :
    ∃ s, ViewIn τ T s (.view d o l) := by
  induction hw with
  | int => cases hs
  | view => cases hs; exact ⟨_, .here⟩
  | arc => cases hs
  | lk => cases hs
  | cell => cases hs
  | rguard => cases hs
  | node _ ih =>
    cases hs with
    | child he hs' => obtain ⟨s, h⟩ := ih _ he hs'; exact ⟨s, .child he h⟩
  | pair _ _ iha ihb =>
    cases hs with
    | fst h => obtain ⟨s, h'⟩ := iha h; exact ⟨s, .fst h'⟩
    | snd h => obtain ⟨s, h'⟩ := ihb h; exact ⟨s, .snd h'⟩
  | inl _ ih => cases hs with | inl h => obtain ⟨s, h'⟩ := ih h; exact ⟨s, .inl h'⟩
  | inr _ ih => cases hs with | inr h => obtain ⟨s, h'⟩ := ih h; exact ⟨s, .inr h'⟩
  | @pkg fs te ms q v cs hw' hq ih =>
    cases hs with
    | pkg h =>
      cases q with
      | any => obtain ⟨s, h'⟩ := ih h; exact ⟨s, .pkg h'⟩
      | _ => exact absurd h (hw'.noView (hq.1 rfl).1)
  | dtor _ _ ih => obtain ⟨s, h⟩ := ih hs; exact ⟨s, .dtor h⟩

theorem ViewAt.home {m : Mem} (hh : HeapOK m) {dep : Dep} {d o l : Nat} {t : Ty} (h : ViewAt m dep d o l t) :
    (∃ r T, m.st r = some ⟨true, some T⟩ ∧ d ∈ T.ids) ∨ PayAddr m d := by
  obtain ⟨c, es, _, hlan, _⟩ := h
  rcases hlan.home with ⟨x, T, hT, hsT⟩ | hp
  · exact Or.inl ⟨x, T, hT, hsT.ids d (by simp [Val.ids])⟩
  · exact Or.inr (hp.payAddr hh d (by simp [Val.ids]))

theorem ValOK.bare_href {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ c, Bare (.href c) v → ∃ dep t H', HrefAt m dep c t H' := by
  induction h with
  | href h =>
    intro c hb
    obtain rfl := hb.href_eq
    obtain ⟨dep, _, hh⟩ := h
    exact ⟨dep, _, _, hh⟩
  | pair _ _ iha ihb =>
    intro c hb
    cases hb with
    | fst h => exact iha c h
    | snd h => exact ihb c h
  | inl _ ih => intro c hb; cases hb with | inl h => exact ih c h
  | inr _ ih => intro c hb; cases hb with | inr h => exact ih c h
  | dtor _ ih => exact ih
  | _ => intro c hb; cases hb

theorem ValOK.bare_view {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ d o l, Bare (.view d o l) v → ∃ dep t, ViewAt m dep d o l t := by
  induction h with
  | view h =>
    intro d o l hb
    have := hb.of_leaf (fun _ _ h => by cases h) (fun _ h => by cases h) (fun _ h => by cases h)
    cases this
    obtain ⟨dep, _, hv⟩ := h
    exact ⟨dep, _, hv⟩
  | pair _ _ iha ihb =>
    intro d o l hb
    cases hb with
    | fst h => exact iha d o l h
    | snd h => exact ihb d o l h
  | inl _ ih => intro d o l hb; cases hb with | inl h => exact ih d o l h
  | inr _ ih => intro d o l hb; cases hb with | inr h => exact ih d o l h
  | dtor _ ih => exact ih
  | _ => intro d o l hb; cases hb

/-- **What a live binding names lies in memory**: in an owned tree, or in a
    payload (each name is valid: `ValOK`, `HrefAt`, `ViewsOK`). -/
theorem MInv.named_home {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {Ey : Entry} (hy : Γ y = some Ey)
    (hl : Alive Ey) {o : Bool} {v : Val} (hs : m.st y = some ⟨o, some v⟩) {i : Nat}
    (hn : PkgNames m Γ Ey v i) : (∃ r T, m.st r = some ⟨true, some T⟩ ∧ i ∈ T.ids) ∨ PayAddr m i := by
  have hbor : (Ey.mode = .bor ∨ Ey.mode = .rootb) → ValOK m Ey.ty v Ey.path Ey.held := fun hm => by
    have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
    obtain ⟨w, hw, hok⟩ := hi.bor_val hy (hl.live_of_bor hm) hos
    rw [hs] at hw; cases hw; exact hok
  have hhref : ∀ c, Bare (.href c) v → (Ey.mode = .bor ∨ Ey.mode = .rootb) →
      (∃ r T, m.st r = some ⟨true, some T⟩ ∧ c ∈ T.ids) ∨ PayAddr m c := fun c hb hm => by
    obtain ⟨dep, t, H', d, es, hlan, _⟩ := (hbor hm).bare_href c hb
    rcases hlan.home with ⟨x, T, hT, hsT⟩ | hp
    · exact Or.inl ⟨x, T, hT, hsT.ids c (by simp [Val.ids])⟩
    · exact Or.inr (hp.payAddr hi.heap c (by simp [Val.ids]))
  rcases hn with ⟨hm, _, ⟨c, hb, rfl⟩ | ⟨o', l, rfl⟩⟩ | ⟨hm, _, o', l, hb⟩ |
      ⟨hm, _, c, r, T, t, d, es, hb, hT, hsn, o', l, hv⟩ | ⟨hos, _, o', l, hv⟩
  · exact hhref _ hb hm
  · obtain ⟨dep, t, hva⟩ := (hbor hm).bare_view i o' l (.refl _)
    exact hva.home hi.heap
  · obtain ⟨dep, t, hva⟩ := (hbor hm).bare_view i o' l hb
    exact hva.home hi.heap
  · obtain ⟨dep, t', H', d', es', hlan, hwn, hvs, _⟩ := (hbor hm).bare_href c hb
    have heq : Val.node t' c d' es' = .node t c d es := by
      rcases hlan.home with ⟨x, T', hT', hsT'⟩ | hp
      · exact (owned_unique hi.heap hT' hT hsT' hsn (i := c) (by simp [Val.head]) (by simp [Val.head])).2
      · exact (hi.heap.notPay hT (hsn.ids c (by simp [Val.ids])) (hp.payAddr hi.heap c (by simp [Val.ids]))).elim
    rw [← heq] at hv
    obtain ⟨s, hin⟩ := hwn.viewIn hv
    obtain ⟨d0, o0, l0, hvv, dep', _, hva⟩ := hvs s _ hin
    cases hvv
    exact hva.home hi.heap
  · -- an owner's views: live, or made by `letd` (`MInv.armed`)
    obtain ⟨sl, hsl, _, hso, hown, _⟩ := hi.slot y Ey hy
    rw [hs] at hsl; cases hsl
    have hwT : WFv Ey.ty v := (hown hos).2.1 v rfl
    have hvsT : ViewsOK m Ey.ty v Ey.held := by
      rcases hl with hl | ⟨hdb, _⟩
      · obtain ⟨T', hT', _, hvs⟩ := hi.own_val hy hl hos
        rw [hs] at hT'; cases hT'; exact hvs
      · exact (hi.armed y Ey _ hy hs hdb hos v rfl).2
    obtain ⟨s, hin⟩ := hwT.viewIn hv
    obtain ⟨d0, o0, l0, hvv, dep', _, hva⟩ := hvsT s _ hin
    cases hvv
    exact hva.home hi.heap

theorem mem_PHH {P H : List Dep} {dep : Dep} (hd : dep ∈ (P ++ H) ++ H) : dep ∈ P ++ H := by
  rcases List.mem_append.mp hd with h | h
  · exact h
  · exact List.mem_append_right _ h

theorem ValOK.bare_href' {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ c, Bare (.href c) v → ∃ dep ∈ P ++ H, ∃ t H', HrefAt m dep c t H' := by
  induction h with
  | href h =>
    intro c hb
    obtain rfl := hb.href_eq
    obtain ⟨dep, hd, hh⟩ := h
    exact ⟨dep, List.mem_append_left _ hd, _, _, hh⟩
  | pair _ _ iha ihb =>
    intro c hb
    cases hb with
    | fst h => obtain ⟨dep, hd, r⟩ := iha c h; exact ⟨dep, mem_PHH hd, r⟩
    | snd h => obtain ⟨dep, hd, r⟩ := ihb c h; exact ⟨dep, mem_PHH hd, r⟩
  | inl _ ih =>
    intro c hb
    cases hb with
    | inl h => obtain ⟨dep, hd, r⟩ := ih c h; exact ⟨dep, mem_PHH hd, r⟩
  | inr _ ih =>
    intro c hb
    cases hb with
    | inr h => obtain ⟨dep, hd, r⟩ := ih c h; exact ⟨dep, mem_PHH hd, r⟩
  | dtor _ ih => exact ih
  | int => intro c hb; cases hb
  | view => intro c hb; cases hb
  | pkg => intro c hb; cases hb
  | arc => intro c hb; cases hb
  | rguard => intro c hb; cases hb
  | lk => intro c hb; cases hb
  | cell => intro c hb; cases hb

/-- AGORA-901: a handle a value holds directly lands through a dependency of
    it, and the node it names stores views valid through what it holds. -/
theorem ValOK.bare_href_held {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ c, Bare (.href c) v → ∃ dep ∈ P ++ H, ∃ t, HrefAt m dep c t H := by
  induction h with
  | href h =>
    intro c hb
    obtain rfl := hb.href_eq
    obtain ⟨dep, hd, hh⟩ := h
    exact ⟨dep, List.mem_append_left _ hd, _, hh⟩
  | pair _ _ iha ihb =>
    intro c hb
    cases hb with
    | fst h => obtain ⟨dep, hd, r⟩ := iha c h; exact ⟨dep, mem_PHH hd, r⟩
    | snd h => obtain ⟨dep, hd, r⟩ := ihb c h; exact ⟨dep, mem_PHH hd, r⟩
  | inl _ ih =>
    intro c hb
    cases hb with
    | inl h => obtain ⟨dep, hd, r⟩ := ih c h; exact ⟨dep, mem_PHH hd, r⟩
  | inr _ ih =>
    intro c hb
    cases hb with
    | inr h => obtain ⟨dep, hd, r⟩ := ih c h; exact ⟨dep, mem_PHH hd, r⟩
  | dtor _ ih => exact ih
  | _ => intro c hb; cases hb

/-- AGORA-901: a view a value holds directly is valid through a dependency
    of it. -/
theorem ValOK.bare_view_in {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) :
    ∀ d o l, Bare (.view d o l) v → ∃ dep ∈ P ++ H, ∃ t, ViewAt m dep d o l t := by
  induction h with
  | view h =>
    intro d o l hb
    have := hb.of_leaf (fun _ _ h => by cases h) (fun _ h => by cases h) (fun _ h => by cases h)
    cases this
    obtain ⟨dep, hd, hv⟩ := h
    exact ⟨dep, List.mem_append_left _ hd, _, hv⟩
  | pair _ _ iha ihb =>
    intro d o l hb
    cases hb with
    | fst h => obtain ⟨dep, hd, r⟩ := iha d o l h; exact ⟨dep, mem_PHH hd, r⟩
    | snd h => obtain ⟨dep, hd, r⟩ := ihb d o l h; exact ⟨dep, mem_PHH hd, r⟩
  | inl _ ih =>
    intro d o l hb
    cases hb with
    | inl h => obtain ⟨dep, hd, r⟩ := ih d o l h; exact ⟨dep, mem_PHH hd, r⟩
  | inr _ ih =>
    intro d o l hb
    cases hb with
    | inr h => obtain ⟨dep, hd, r⟩ := ih d o l h; exact ⟨dep, mem_PHH hd, r⟩
  | dtor _ ih => exact ih
  | _ => intro d o l hb; cases hb

/-- AGORA-901: a view stored in the node of an owned tree that a value's
    handle names is valid through something the value holds in memory. -/
theorem ValOK.named_view_held {m : Mem} (hh : HeapOK m) {τ : Ty} {v : Val} {P H : List Dep}
    (h : ValOK m τ v P H) {c : Nat} (hb : Bare (.href c) v) {r : Var} {T : Val} {t : Ty} {d : Nat}
    {es : List Val} (hT : m.st r = some ⟨true, some T⟩) (hs : Sub (.node t c d es) T) {i o l : Nat}
    (hv : Sub (.view i o l) (.node t c d es)) : ∃ dep ∈ H, dep.kind.isName = false := by
  obtain ⟨dep0, _, t0, d', es', hl, hw, hvs, _⟩ := h.bare_href_held c hb
  have heq : Val.node t c d es = .node t0 c d' es' := by
    rcases hl.home with ⟨x, T', hT', hs'⟩ | hp
    · exact (owned_unique hh hT hT' hs hs' (i := c) (by simp [Val.head]) (by simp [Val.head])).2
    · exact absurd (hp.payAddr hh c (by simp [Val.ids])) (hh.notPay hT (hs.ids c (by simp [Val.ids])))
  rw [heq] at hv
  obtain ⟨s, hvi⟩ := hw.viewIn hv
  obtain ⟨_, _, _, _, dep, hd, _, _, _, hla, _⟩ := hvs s _ hvi
  exact ⟨dep, hd, hla.notName⟩

theorem sub_antisymm {a b : Val} (h1 : Sub a b) (h2 : Sub b a) : a = b := by
  rcases h1.cases' with h | ⟨e, hc, hs⟩
  · exact h
  · exact (Below.irrefl ⟨e, hc, h2.trans hs⟩).elim

/-- **Who names an owner's root node**: a live borrow whose handle names the
    node at the top of an owner's tree, not frozen, depends on that owner as
    its handle or its view (`self`, `view`): a borrowed parameter's node lies
    in a frozen tree or a payload (`rootb_anchor`). -/
theorem MInv.root_namer {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) {t : Ty} {c0 d0 : Nat} {es0 : List Val}
    (hT : m.st x = some ⟨true, some (.node t c0 d0 es0)⟩)
    {y : Var} {Ey : Entry} (hy : Γ y = some Ey) (hl : Ey.live = true) {v : Val}
    (hs : m.st y = some ⟨false, some v⟩) (hb : Bare (.href c0) v) :
    ∃ dep ∈ Ey.vdeps, dep.root = x ∧ (dep.kind = .self ∨ dep.kind = .view) := by
  have hm := hi.bor_mode hy hs
  have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
  obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl hos
  rw [hs] at hw; cases hw
  have hint : Ey.ty ≠ .int := fun ht => by
    rw [ht] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok; cases hb
  obtain ⟨dep, hd, t1, H', d1, es1, hlan, _⟩ := hok.bare_href' c0 hb
  have hdv : dep ∈ Ey.vdeps := by simp [Entry.vdeps, hos]; exact List.mem_append.mp hd
  have hc0T : c0 ∈ (Val.node t c0 d0 es0).ids := by simp [Val.ids]
  -- a node in a frozen tree or a payload is not the owner's
  have hfz : ∀ n0, Sub (.node t1 c0 d1 es1) n0 →
      ((∃ o T, o ∈ F ∧ OwnedAt m o T ∧ Sub n0 T) ∨ ∃ k bl, m.blk k = some bl ∧ Sub n0 bl.rd) → False := by
    rintro n0 hsn (⟨o, T, hoF, hoT, hsT⟩ | ⟨k, bl, hk, hsb⟩)
    · have hox : o = x := Classical.byContradiction fun hne =>
        hi.heap.disj o x T _ hne hoT hT c0 ((hsn.trans hsT).ids c0 (by simp [Val.ids])) hc0T
      exact hxF (hox ▸ hoF)
    · exact hi.heap.notPay hT hc0T
        (InPay.payAddr hi.heap ⟨k, bl, hk, hsn.trans hsb⟩ c0 (by simp [Val.ids]))
  refine ⟨dep, hdv, ?_⟩
  rcases hlan with ⟨n0, hr, hla⟩ | ⟨_, _, hp⟩
  · have hsn := hla.sub
    -- a borrowed root's node is a borrowed parameter's
    have hrb : (∃ w, m.st dep.root = some ⟨false, some w⟩) → ∃ Er, Γ dep.root = some Er ∧ Er.mode = .rootb := by
      rintro ⟨w, hw⟩
      obtain ⟨Er, hEr, hro⟩ := hi.wf y Ey hy hl (Or.inl hint) dep.root (List.mem_map_of_mem hdv)
      obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot dep.root Er hEr
      rw [hw] at hsl; cases hsl
      refine ⟨Er, hEr, ?_⟩
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hro; simp [Mode.isRoot] at hro
    rcases hr with ⟨T1, hT1, htop⟩ | ⟨w', c', hc', ht', hna⟩ | ⟨w', d', o', l', hc', ht', hda⟩ |
      ⟨w', k, q, _, _, rfl⟩ | ⟨w', k, _, _, rfl⟩
    · -- an owner's tree: the owner's, at its top
      have hs1 : Sub (.node t1 c0 d1 es1) T1 := hsn.trans htop.sub
      have hrx : dep.root = x := Classical.byContradiction fun hne =>
        hi.heap.disj _ x T1 _ hne hT1 hT c0 (hs1.ids c0 (by simp [Val.ids])) hc0T
      refine ⟨hrx, ?_⟩
      rw [hrx, hT] at hT1; cases hT1
      have heq := sub_unique (hi.heap.nodup x _ hT) hs1 (Sub.refl _) (i := c0) (by simp [Val.head])
        (by simp [Val.head])
      have hn0 : n0 = .node t c0 d0 es0 := by
        rw [heq] at hsn
        exact (sub_antisymm hsn htop.sub).symm
      rcases hla with ⟨hk, _⟩ | ⟨hk, _⟩ | ⟨_, hbl⟩
      · exact Or.inl hk
      · exact Or.inr hk
      · rw [hn0, heq] at hbl; exact (Below.irrefl hbl).elim
    · obtain ⟨Er, hEr, hrbm⟩ := hrb ⟨w', hc'⟩
      exact (hfz n0 hsn (rootb_anchor hi hanch dep.root Er n0 hEr hrbm
        (Or.inr (Or.inl ⟨w', c', hc', ht', hna⟩)) (by
          obtain ⟨ty, d, es, hneq⟩ := hna.eq; rw [hneq]; intro _ _ h; cases h))).elim
    · obtain ⟨Er, hEr, hrbm⟩ := hrb ⟨w', hc'⟩
      exact (hfz n0 hsn (rootb_anchor hi hanch dep.root Er n0 hEr hrbm
        (Or.inr (Or.inr (Or.inl ⟨w', d', o', l', hc', ht', hda⟩))) (by
          obtain ⟨ty, c, es, hneq⟩ := hda.eq; rw [hneq]; intro _ _ h; cases h))).elim
    · rcases hsn.cases' with h | ⟨e, hc, _⟩
      · cases h
      · cases hc
    · rcases hsn.cases' with h | ⟨e, hc, _⟩
      · cases h
      · cases hc
  · exact (hi.heap.notPay hT hc0T (hp.payAddr hi.heap c0 (by simp [Val.ids]))).elim

/-- **Who names a node of an owner's tree**: a live borrow whose handle names
    a node of an owner's tree, not frozen, depends on that owner in memory, as
    its handle, its view or a part of it: a borrowed parameter's node lies in
    a frozen tree or a payload (`rootb_anchor`), a share's in a payload. -/
theorem MInv.namer {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) (hanch : RootbAnch Γ F)
    {x : Var} (hxF : x ∉ F) {T : Val} (hT : m.st x = some ⟨true, some T⟩) {c : Nat} (hcT : c ∈ T.ids)
    {y : Var} {Ey : Entry} (hy : Γ y = some Ey) (hl : Ey.live = true) {v : Val}
    (hs : m.st y = some ⟨false, some v⟩) (hb : Bare (.href c) v) :
    ∃ dep ∈ Ey.vdeps, dep.root = x ∧ (dep.kind = .self ∨ dep.kind = .view ∨ dep.kind = .inner) := by
  have hm := hi.bor_mode hy hs
  have hos : Ey.mode.ownSlot = false := by rcases hm with h | h <;> rw [h] <;> rfl
  obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl hos
  rw [hs] at hw; cases hw
  have hint : Ey.ty ≠ .int := fun ht => by
    rw [ht] at hok; obtain ⟨k, rfl⟩ := valOK_int.mp hok; cases hb
  obtain ⟨dep, hd, t1, H', d1, es1, hlan, _⟩ := hok.bare_href' c hb
  have hdv : dep ∈ Ey.vdeps := by simp [Entry.vdeps, hos]; exact List.mem_append.mp hd
  have hfz : ∀ n0, Sub (.node t1 c d1 es1) n0 →
      ((∃ o T, o ∈ F ∧ OwnedAt m o T ∧ Sub n0 T) ∨ ∃ k bl, m.blk k = some bl ∧ Sub n0 bl.rd) → False := by
    rintro n0 hsn (⟨o, T', hoF, hoT, hsT⟩ | ⟨k, bl, hk, hsb⟩)
    · have hox : o = x := Classical.byContradiction fun hne =>
        hi.heap.disj o x T' _ hne hoT hT c ((hsn.trans hsT).ids c (by simp [Val.ids])) hcT
      exact hxF (hox ▸ hoF)
    · exact hi.heap.notPay hT hcT (InPay.payAddr hi.heap ⟨k, bl, hk, hsn.trans hsb⟩ c (by simp [Val.ids]))
  refine ⟨dep, hdv, ?_⟩
  rcases hlan with ⟨n0, hr, hla⟩ | ⟨_, _, hp⟩
  · have hsn := hla.sub
    have hrb : (∃ w, m.st dep.root = some ⟨false, some w⟩) → ∃ Er, Γ dep.root = some Er ∧ Er.mode = .rootb := by
      rintro ⟨w, hw⟩
      obtain ⟨Er, hEr, hro⟩ := hi.wf y Ey hy hl (Or.inl hint) dep.root (List.mem_map_of_mem hdv)
      obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot dep.root Er hEr
      rw [hw] at hsl; cases hsl
      refine ⟨Er, hEr, ?_⟩
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hro; simp [Mode.isRoot] at hro
    have hk : dep.kind = .self ∨ dep.kind = .view ∨ dep.kind = .inner := by
      rcases hla with ⟨h, _⟩ | ⟨h, _⟩ | ⟨h, _⟩
      · exact Or.inl h
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
    rcases hr with ⟨T1, hT1, htop⟩ | ⟨w', c', hc', ht', hna⟩ | ⟨w', d', o', l', hc', ht', hda⟩ |
      ⟨w', k, q, _, _, rfl⟩ | ⟨w', k, _, _, rfl⟩
    · have hs1 : Sub (.node t1 c d1 es1) T1 := hsn.trans htop.sub
      have hrx : dep.root = x := Classical.byContradiction fun hne =>
        hi.heap.disj _ x T1 _ hne hT1 hT c (hs1.ids c (by simp [Val.ids])) hcT
      exact ⟨hrx, hk⟩
    · obtain ⟨Er, hEr, hrbm⟩ := hrb ⟨w', hc'⟩
      exact (hfz n0 hsn (rootb_anchor hi hanch dep.root Er n0 hEr hrbm
        (Or.inr (Or.inl ⟨w', c', hc', ht', hna⟩)) (by
          obtain ⟨ty, d, es, hneq⟩ := hna.eq; rw [hneq]; intro _ _ h; cases h))).elim
    · obtain ⟨Er, hEr, hrbm⟩ := hrb ⟨w', hc'⟩
      exact (hfz n0 hsn (rootb_anchor hi hanch dep.root Er n0 hEr hrbm
        (Or.inr (Or.inr (Or.inl ⟨w', d', o', l', hc', ht', hda⟩))) (by
          obtain ⟨ty, c, es, hneq⟩ := hda.eq; rw [hneq]; intro _ _ h; cases h))).elim
    · rcases hsn.cases' with h | ⟨e, hc, _⟩
      · cases h
      · cases hc
    · rcases hsn.cases' with h | ⟨e, hc, _⟩
      · cases h
      · cases hc
  · exact (hi.heap.notPay hT hcT (hp.payAddr hi.heap c (by simp [Val.ids]))).elim

end A2
