import A2.Frame

/-! A2 — evaluating a right-hand side keeps the invariant and yields a value
valid as its entry says. -/

namespace A2

theorem VecOf.unique {m : Mem} (hh : HeapOK m) {y : Var} {t t' : Ty} {c c' d d' : Nat}
    {es es' : List Val} (h1 : VecOf m y t c d es) (h2 : VecOf m y t' c' d' es') :
    Val.node t c d es = Val.node t' c' d' es' := by
  obtain ⟨_, _, h1⟩ := h1
  obtain ⟨_, _, h2⟩ := h2
  rcases h1 with h1 | ⟨h1, n1⟩ <;> rcases h2 with h2 | ⟨h2, n2⟩
  · rw [h1] at h2; cases h2; rfl
  · rw [h1] at h2; cases h2
  · rw [h1] at h2; cases h2
  · rw [h1] at h2; cases h2; exact nodeAt_unique hh n1 n2

theorem comp_ne_view {a b : Kind} (ha : a ≠ .view) (hb : b ≠ .view) : comp a b ≠ .view := by
  cases a <;> cases b <;> simp_all [comp]

theorem comp_ne_self {a b : Kind} (hb : b ≠ .self) : comp a b ≠ .self := by
  cases a <;> cases b <;> simp_all [comp]

/-- A borrowed `Vec` taken from `y` in way `k`. -/
theorem derive_hrefAt {m : Mem} {y : Var} {E : Entry} {N : Val}
    (hroot : E.mode.isRoot = true → RootNode m y N)
    {k : Kind}
    (hbor : E.mode = .bor → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind N n0)
    (hrk : rootKind E.ty k = k)
    {t : Ty} {c d : Nat} {es : List Val} (hl : Lands k (.node t c d es) N)
    (hw : WFv (.vec t) (.node t c d es)) {H : List Dep} (hv : ViewsOK m (.vec t) (.node t c d es) H) :
    ∃ dep ∈ derive y E k, HrefAt m dep c t H := by
  unfold derive
  cases h : E.mode.isRoot with
  | true =>
    simp only [↓reduceIte, List.mem_singleton, exists_eq_left]
    exact ⟨N, d, es, hroot h, by rw [hrk]; exact hl, hw, hv⟩
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map]
    have hb : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
    obtain ⟨dep, hd, n0, hr, hld⟩ := hbor hb
    exact ⟨_, ⟨dep, hd, rfl⟩, n0, d, es, hr, lands_comp' hld hl, hw, hv⟩

/-- A view taken from `y` in way `k`. -/
theorem derive_viewAt {m : Mem} {y : Var} {E : Entry} {N : Val}
    (hroot : E.mode.isRoot = true → RootNode m y N)
    (hbor : E.mode = .bor → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind N n0)
    {k : Kind} (hk : k ≠ .self) (hrk : rootKind E.ty k = k)
    {t : Ty} {c d : Nat} {es : List Val} (hl : Lands k (.node t c d es) N)
    {o l : Nat} (hlen : o + l ≤ es.length) (hw : WFv (.vec t) (.node t c d es)) :
    ∃ dep ∈ derive y E k, ViewAt m dep d o l t := by
  unfold derive
  cases h : E.mode.isRoot with
  | true =>
    simp only [↓reduceIte, List.mem_singleton, exists_eq_left]
    exact viewAt_iff.mpr ⟨N, c, es, hroot h, by rw [hrk]; exact hk, by rw [hrk]; exact hl, hlen, hw⟩
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, List.mem_map]
    have hb : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
    obtain ⟨dep, hd, n0, hr, hld⟩ := hbor hb
    exact ⟨_, ⟨dep, hd, rfl⟩, viewAt_iff.mpr ⟨n0, c, es, hr, comp_ne_self hk,
      lands_comp' hld hl, hlen, hw⟩⟩

theorem Lands.elem {t : Ty} {c d : Nat} {es : List Val} {e : Val} (he : e ∈ es) :
    Lands .inner e (.node t c d es) :=
  Or.inr (Or.inr ⟨rfl, e, Child.elem he, Sub.refl _⟩)

theorem WFv.elem {t : Ty} {T : Val} (hw : WFv (.vec t) T) {c d : Nat} {es : List Val}
    {u : Ty} (hT : T = .node u c d es) {e : Val} (he : e ∈ es) : WFv t e := by
  subst hT; cases hw with | node h => exact h e he

theorem ViewsOK.elem {m : Mem} {t u : Ty} {c d : Nat} {es : List Val} {H : List Dep}
    (hv : ViewsOK m (.vec t) (.node u c d es) H) {e : Val} (he : e ∈ es) : ViewsOK m t e H :=
  fun s v hin => hv s v (ViewIn.child he hin)

/-- Values that hold no views: nothing inside them can dangle. -/
theorem ViewsOK.none {m : Mem} {t : Ty} (ht : t.holdsView = false) (T : Val) (H : List Dep) :
    ViewsOK m t T H := by
  intro s v hin
  have := hin.holdsView
  rw [ht] at this; cases this

theorem rootNode_st {m m' : Mem} (h : m'.st = m.st) {r : Var} {n : Val} (hn : RootNode m r n) :
    RootNode m' r n := by
  unfold RootNode NodeAt DataAt at *
  rw [h]; exact hn

theorem MInv.of_st {m m' : Mem} {Γ : Ctx} (hi : MInv m Γ) (h : m'.st = m.st) (hh : HeapOK m')
    (hnv : m.nv ≤ m'.nv) : MInv m' Γ where
  dom v := by rw [h]; exact hi.dom v
  slot v E hv := by
    obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot v E hv
    refine ⟨sl, by rw [h]; exact hsl, hok, hslot.keep fun dep _ => ?_⟩
    have hk : RootKeep m m' dep.root := fun n hn => rootNode_st h hn
    exact ⟨hk.vkeep, hk.hkeep⟩
  heap := hh
  nvSt v hv := by rw [h] at hv; exact Nat.lt_of_lt_of_le (hi.nvSt v hv) hnv
  noInout := hi.noInout
  wf := hi.wf
  rootbLive := hi.rootbLive
  rootbLt := hi.rootbLt

/-- What a right-hand side hands to the binding that takes it. -/
structure RhsOut (m1 : Mem) (Γ1 : Ctx) (E : Entry) (v : Val) (o : Bool) : Prop where
  own    : o = E.mode.ownSlot
  mode   : E.mode = .own ∨ E.mode = .bor
  live   : E.live = true
  tyok   : E.ty.ok = true
  wf     : E.ty ≠ .int → ∀ r ∈ roots E.vdeps, ∃ Er, Γ1 r = some Er ∧ Er.mode.isRoot = true
  valOwn : E.mode = .own → E.ty.owning = true ∧ WFv E.ty v ∧ ViewsOK m1 E.ty v E.held ∧
             v.ids.Nodup ∧ (∀ i ∈ v.ids, m1.alloc i = true ∧ i < m1.nid) ∧
             (∀ x U, OwnedAt m1 x U → ∀ i ∈ v.ids, i ∉ U.ids) ∧ SelfFree v
  valBor : E.mode = .bor → ValOK m1 E.ty v E.path E.held

/-- The context and memory after a right-hand side, and how they relate to
    before. -/
structure RhsPost (m m1 : Mem) (Γ Γ1 : Ctx) (F : List Var) : Prop where
  inv   : MInv m1 Γ1
  nv    : m1.nv = m.nv
  nid   : m.nid ≤ m1.nid
  dom   : ∀ x, (m1.st x).isSome = (m.st x).isSome
  frz   : ∀ x ∈ F, m1.st x = m.st x
  rootb : ∀ p Ep, Γ p = some Ep → Ep.mode = .rootb → Γ1 p = some Ep
  cdom  : ∀ x, (Γ1 x).isSome = (Γ x).isSome
  cmode : ∀ x E1, Γ1 x = some E1 → ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty

theorem RhsPost.same {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) : RhsPost m m Γ Γ F :=
  ⟨hi, rfl, Nat.le_refl _, fun _ => rfl, fun _ _ => rfl, fun _ _ h _ => h, fun _ => rfl,
    fun x E1 h => ⟨E1, h, rfl, rfl⟩⟩

theorem intE_out {m : Mem} {Γ : Ctx} (n : Nat) : RhsOut m Γ intE (.int n) false where
  own := rfl
  mode := Or.inr rfl
  live := rfl
  tyok := rfl
  wf h := absurd rfl h
  valOwn h := by simp [intE] at h
  valBor _ := ⟨n, rfl⟩

theorem wf_held {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) : ∀ r ∈ roots E.held,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  refine hi.wf y E hy hl (Or.inl hnint) r ?_
  simp only [roots, Entry.vdeps, List.map_append, List.mem_append] at hr ⊢
  exact Or.inr hr

theorem wf_path {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) (hm : E.mode.ownSlot = false) : ∀ r ∈ roots E.path,
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  refine hi.wf y E hy hl (Or.inl hnint) r ?_
  simp only [roots, Entry.vdeps, hm, Bool.false_eq_true, ↓reduceIte, List.map_append,
    List.mem_append] at hr ⊢
  exact Or.inl hr

theorem wf_derive {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) (k : Kind) : ∀ r ∈ roots (derive y E k),
    ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  unfold derive at hr
  cases h : E.mode.isRoot with
  | true =>
    simp only [h, ↓reduceIte, roots, List.map_cons, List.map_nil, List.mem_singleton] at hr
    subst hr; exact ⟨E, hy, h⟩
  | false =>
    simp only [h, Bool.false_eq_true, ↓reduceIte, roots, List.map_map, List.mem_map,
      Function.comp] at hr
    obtain ⟨dep, hd, rfl⟩ := hr
    have hm : E.mode.ownSlot = false := by cases hm : E.mode <;> simp_all [Mode.isRoot, Mode.ownSlot]
    exact wf_path hi hy hl hnint hm dep.root (List.mem_map_of_mem hd)

theorem wf_append {Γ : Ctx} {a b : List Dep}
    (ha : ∀ r ∈ roots a, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true)
    (hb : ∀ r ∈ roots b, ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true) :
    ∀ r ∈ roots (a ++ b), ∃ Er, Γ r = some Er ∧ Er.mode.isRoot = true := by
  intro r hr
  simp only [roots, List.map_append, List.mem_append] at hr
  rcases hr with hr | hr
  · exact ha r hr
  · exact hb r hr

theorem bor_vdeps (E : Entry) (h : E.mode = .bor) : E.vdeps = E.path ++ E.held := by
  simp [Entry.vdeps, h, Mode.ownSlot]

theorem slot_val_eq {m : Mem} {y : Var} {o : Bool} {v w : Val}
    (h1 : m.st y = some ⟨o, some v⟩) (h2 : m.st y = some ⟨o, some w⟩) : v = w := by
  rw [h1] at h2; cases h2; rfl

theorem out_copyBor {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {v : Val}
    (hy : Γ y = some E) (hl : E.live = true) (hm : E.mode = .bor)
    (hv : m.st y = some ⟨false, some v⟩) : RhsOut m Γ E v false where
  own := by rw [hm]; rfl
  mode := Or.inr hm
  live := hl
  tyok := hi.tyok hy
  wf hn := hi.wf y E hy hl (Or.inl hn)
  valOwn h := by rw [hm] at h; cases h
  valBor _ := by
    obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    rw [slot_val_eq hv hw]; exact hok

/-- A borrow of a whole binding `y` (`var` of a borrowed parameter, or
    `borrow`): its handle, or its view if it is a slice. -/
theorem out_borrowWhole {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {v : Val}
    (hy : Γ y = some E) (hl : E.live = true) (hnown : E.mode.ownSlot = false ∨ ∃ t, E.ty = .vec t)
    (hv : m.st y = some ⟨false, some v⟩ ∨
      ∃ t c d es, m.st y = some ⟨true, some (.node t c d es)⟩ ∧ v = .href c)
    (hroot : E.mode = .rootb ∨ (E.mode = .own ∧ ∃ t, E.ty = .vec t)) (hnp : E.ty.isAgg = false) :
    RhsOut m Γ ⟨E.ty, .bor, true, derive y E .self, E.held⟩ v false where
  own := rfl
  mode := Or.inr rfl
  live := rfl
  tyok := hi.tyok (E := E) hy
  wf hn := by
    rw [bor_vdeps _ rfl]
    exact wf_append (wf_derive hi hy hl hn _) (wf_held (E := E) hi hy hl hn)
  valOwn h := by cases h
  valBor _ := by
    have hisroot : E.mode.isRoot = true := by
      rcases hroot with h | ⟨h, _⟩ <;> rw [h] <;> rfl
    show ValOK m E.ty v (derive y E .self) E.held
    cases hty : E.ty with
    | int =>
      rcases hroot with h | ⟨_, t, ht⟩
      · obtain ⟨w, hw, hok⟩ := hi.bor_val hy hl (by rw [h]; rfl)
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩
        · rw [slot_val_eq hv hw]; rw [hty] at hok; exact hok
        · rw [hv] at hw; cases hw
      · rw [ht] at hty; cases hty
    | vec t =>
      obtain ⟨c, d, es, hvec, hw, hvs, hroot', _⟩ := hi.vec_node hy hl hty
      have hvc : v = .href c := by
        obtain ⟨_, _, hvec⟩ := hvec
        rcases hv with hv | ⟨_, _, _, _, hv, rfl⟩ <;> rcases hvec with h | ⟨h, _⟩ <;>
          rw [hv] at h <;> cases h <;> rfl
      refine ⟨c, hvc, ?_⟩
      exact derive_hrefAt (hroot' ·) (fun h => by rw [h] at hisroot; cases hisroot)
        (by rw [hty]; rfl) (Or.inl ⟨rfl, rfl⟩) hw hvs
    | slice t =>
      obtain ⟨d, o, l, c, es, hs, _, _, hlen, hw, hroot', _⟩ := hi.slice_node hy hl hty
      have hvv : v = .view d o l := by
        rcases hv with hv | ⟨_, _, _, _, hv, _⟩ <;> rw [hv] at hs <;> cases hs; rfl
      refine ⟨d, o, l, hvv, ?_⟩
      have hder : derive y E .self = derive y E .view := by
        unfold derive; rw [hisroot, hty]; rfl
      rw [hder]
      exact derive_viewAt (hroot' ·) (fun h => by rw [h] at hisroot; cases hisroot)
        (by decide) (by rw [hty]; rfl) (Or.inr (Or.inl ⟨rfl, rfl⟩)) hlen hw
    | prod a b => rw [hty] at hnp; cases hnp
    | sum a b => rw [hty] at hnp; cases hnp

/-- A value stored in memory, lent out: every node inside it is reached
    through `P`, every view it stores is valid through `H`. -/
theorem lend_valOK {m : Mem} {H : List Dep} {τ : Ty} {e : Val} (hw : WFv τ e) :
    ∀ {P : List Dep},
    (∀ t c d es, Sub (.node t c d es) e →
      ∃ dep ∈ P, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind (.node t c d es) n0) →
    ViewsOK m τ e H → (∀ s, τ = .slice s → ViewsOK m τ e P) → ValOK m τ (lendOf e) P H := by
  induction hw with
  | int => intro P _ _ _; exact ⟨_, rfl⟩
  | @view t d o l =>
    intro P _ _ hs
    obtain ⟨d', o', l', hv, dep, hd, ha⟩ := hs t rfl t _ ViewIn.here
    cases hv
    exact ⟨d, o, l, rfl, dep, hd, ha⟩
  | @node t c d es hes =>
    intro P hn hv _
    obtain ⟨dep, hd, n0, hr, hl⟩ := hn t c d es (Sub.refl _)
    exact ⟨c, rfl, dep, hd, n0, d, es, hr, hl, WFv.node hes, hv⟩
  | @pair a b v w _ _ ihv ihw =>
    intro P hn hvs _
    have hn' : ∀ t c d es, Sub (.node t c d es) (.pair v w) →
        ∃ dep ∈ P ++ H, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind (.node t c d es) n0 := by
      intro t c d es hs
      obtain ⟨dep, hd, rest⟩ := hn t c d es hs
      exact ⟨dep, List.mem_append_left _ hd, rest⟩
    refine ⟨_, _, rfl, ihv (fun t c d es hs => hn' t c d es (Sub.fst hs)) (fun s x hin => hvs s x
      (ViewIn.fst hin)) (fun s _ => ?_), ihw (fun t c d es hs => hn' t c d es (Sub.snd hs))
      (fun s x hin => hvs s x (ViewIn.snd hin)) (fun s _ => ?_)⟩
    · exact ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.fst hin))
    · exact ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.snd hin))
  | @inl a b v _ ihv =>
    intro P hn hvs _
    refine Or.inl ⟨_, rfl, ihv (fun t c d es hs => ?_) (fun s x hin => hvs s x (ViewIn.inl hin))
      (fun s _ => ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.inl hin)))⟩
    obtain ⟨dep, hd, rest⟩ := hn t c d es (Sub.inl hs)
    exact ⟨dep, List.mem_append_left _ hd, rest⟩
  | @inr a b v _ ihv =>
    intro P hn hvs _
    refine Or.inr ⟨_, rfl, ihv (fun t c d es hs => ?_) (fun s x hin => hvs s x (ViewIn.inr hin))
      (fun s _ => ViewsOK.mono (List.subset_append_right _ _) (fun s x hin => hvs s x (ViewIn.inr hin)))⟩
    obtain ⟨dep, hd, rest⟩ := hn t c d es (Sub.inr hs)
    exact ⟨dep, List.mem_append_left _ hd, rest⟩

/-- What a borrowed struct holds is already lent: lending it again changes
    nothing. -/
theorem ValOK.lend {m : Mem} {τ : Ty} {v : Val} {P H : List Dep} (h : ValOK m τ v P H) : lendOf v = v := by
  induction τ generalizing v P with
  | int => obtain ⟨n, rfl⟩ := h; rfl
  | vec t => obtain ⟨c, rfl, _⟩ := h; rfl
  | slice t => obtain ⟨d, o, l, rfl, _⟩ := h; rfl
  | prod a b iha ihb =>
    obtain ⟨x, y, rfl, hx, hy⟩ := h
    simp [lendOf, iha hx, ihb hy]
  | sum a b iha ihb =>
    rcases h with ⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩
    · simp [lendOf, iha hx]
    · simp [lendOf, ihb hx]

theorem elemE_mode (y : Var) (E : Entry) (t : Ty) : (elemE y E t).mode = .bor := by
  cases t <;> rfl

theorem out_at {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .vec t)
    {t' : Ty} {c d n : Nat} {es : List Val} (hn : n < es.length) (hvec : VecOf m y t' c d es) :
    RhsOut m Γ (elemE y E t) (lendOf es[n]) false where
  own := by rw [elemE_mode]; rfl
  mode := Or.inr (elemE_mode ..)
  live := by cases t <;> rfl
  tyok := by
    have := hi.tyok hy; rw [hty] at this
    cases t with
    | int => rfl
    | vec s => exact this
    | slice s => exact this
    | prod a b => exact this
    | sum a b => exact this
  wf hn' := by
    rw [bor_vdeps _ (elemE_mode ..)]
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    cases t with
    | int => exact absurd rfl hn'
    | slice s => exact wf_append (wf_held (E := E) hi hy hl hnint) (wf_held (E := E) hi hy hl hnint)
    | vec s => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | prod a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | sum a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
  valOwn h := by rw [elemE_mode] at h; cases h
  valBor _ := by
    obtain ⟨c0, d0, es0, hvec0, hw, hvs, hroot, hbor⟩ := hi.vec_node hy hl hty
    have heq := VecOf.unique hi.heap hvec0 hvec
    cases heq
    have hmem : es[n] ∈ es := List.getElem_mem hn
    have hwe : WFv t es[n] := hw.elem rfl hmem
    generalize es[n] = e at hmem hwe ⊢
    cases t with
    | int =>
      cases hwe with | int => exact ⟨_, rfl⟩
    | slice s =>
      cases hwe with
      | view =>
        obtain ⟨d', o', l', hv', dep, hd, ha⟩ := hvs s _ (ViewIn.child hmem ViewIn.here)
        exact ⟨d', o', l', hv', dep, hd, ha⟩
    | vec s =>
      cases hwe with
      | node hes =>
        rename_i c1 d1 es1
        exact ⟨c1, rfl, derive_hrefAt (hroot ·) hbor (by rw [hty]; rfl)
          (Lands.elem hmem) (WFv.node hes) (hvs.elem hmem)⟩
    | prod a b =>
      refine lend_valOK hwe (fun t' c' d' es' hs => ?_) (hvs.elem hmem) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧
          Lands dep.kind (.node (.prod a b) c d es) n0 := fun h => hbor (by
        cases hm : E.mode <;> simp_all [Mode.isRoot])
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | sum a b =>
      refine lend_valOK hwe (fun t' c' d' es' hs => ?_) (hvs.elem hmem) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧
          Lands dep.kind (.node (.sum a b) c d es) n0 := fun h => hbor (by
        cases hm : E.mode <;> simp_all [Mode.isRoot])
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)

theorem out_view {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .vec t) (hhv : t.holdsView = false)
    {t' : Ty} {c d : Nat} {es : List Val} (hvec : VecOf m y t' c d es) :
    RhsOut m Γ ⟨.slice t, .bor, true, derive y E .view, E.held⟩ (.view d 0 es.length) false where
  own := rfl
  mode := Or.inr rfl
  live := rfl
  tyok := by
    have := hi.tyok hy; rw [hty] at this
    simpa [Ty.ok, hhv] using this
  wf hn' := by
    rw [bor_vdeps _ rfl]
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
  valOwn h := by cases h
  valBor _ := by
    obtain ⟨c0, d0, es0, hvec0, hw, _, hroot, hbor⟩ := hi.vec_node hy hl hty
    have heq := VecOf.unique hi.heap hvec0 hvec
    cases heq
    refine ⟨d, 0, es.length, rfl, derive_viewAt (hroot ·) ?_ (by decide) (by rw [hty]; rfl)
      (Or.inr (Or.inl ⟨rfl, rfl⟩)) (by simp) hw⟩
    intro hb
    obtain ⟨dep, hd, n0, hr, hla⟩ := hbor hb
    exact ⟨dep, hd, n0, hr, hla⟩

theorem out_sat {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} {t : Ty}
    (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .slice t)
    {t' : Ty} {c d o l n : Nat} {es : List Val} (hn : o + n < es.length)
    (hv : m.st y = some ⟨false, some (.view d o l)⟩) (hda : DataAt m d (.node t' c d es)) :
    RhsOut m Γ (elemE y E t) (lendOf es[o + n]) false where
  own := by rw [elemE_mode]; rfl
  mode := Or.inr (elemE_mode ..)
  live := by cases t <;> rfl
  tyok := by
    have := hi.tyok hy; rw [hty] at this
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at this
    cases t with
    | int => rfl
    | vec s => exact this.1
    | slice s => simp [Ty.holdsView] at this
    | prod a b => exact this.1
    | sum a b => exact this.1
  wf hn' := by
    rw [bor_vdeps _ (elemE_mode ..)]
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    cases t with
    | int => exact absurd rfl hn'
    | slice s => exact wf_append (wf_held (E := E) hi hy hl hnint) (wf_held (E := E) hi hy hl hnint)
    | vec s => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | prod a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
    | sum a b => exact wf_append (wf_derive hi hy hl hnint _) (wf_held (E := E) hi hy hl hnint)
  valOwn h := by rw [elemE_mode] at h; cases h
  valBor _ := by
    obtain ⟨d0, o0, l0, c0, es0, hs0, hda0, _, _, hw, hroot, hbor⟩ := hi.slice_node hy hl hty
    rw [hv] at hs0; cases hs0
    have heq := dataAt_unique hi.heap hda0 hda
    cases heq
    have hok := hi.tyok hy; rw [hty] at hok
    simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at hok
    have hmem : es[o + n] ∈ es := List.getElem_mem hn
    have hwe : WFv t es[o + n] := hw.elem rfl hmem
    generalize es[o + n] = e at hmem hwe ⊢
    cases t with
    | int =>
      cases hwe with | int => exact ⟨_, rfl⟩
    | slice s => simp [Ty.holdsView] at hok
    | vec s =>
      cases hwe with
      | node hes =>
        rename_i c1 d1 es1
        refine ⟨c1, rfl, derive_hrefAt (hroot ·) ?_ (by rw [hty]; rfl)
          (Lands.elem hmem) (WFv.node hes) (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _)⟩
        intro hb
        obtain ⟨dep, hd, n0, hr, _, hla⟩ := hbor hb
        exact ⟨dep, hd, n0, hr, hla⟩
    | prod a b =>
      refine lend_valOK hwe (fun t' c' d' es' hs => ?_)
        (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧
          Lands dep.kind (.node (.prod a b) c d es) n0 := fun h => by
        have hb : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
        obtain ⟨dep, hd, n0, hr, _, hla⟩ := hbor hb
        exact ⟨dep, hd, n0, hr, hla⟩
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)
    | sum a b =>
      refine lend_valOK hwe (fun t' c' d' es' hs => ?_)
        (ViewsOK.none (by simpa [Ty.holdsView] using hok.2) _ _) (fun s h => by cases h)
      have hbor' : E.mode.isRoot = false → ∃ dep ∈ E.path, ∃ n0, RootNode m dep.root n0 ∧
          Lands dep.kind (.node (.sum a b) c d es) n0 := fun h => by
        have hb : E.mode = .bor := by cases hm : E.mode <;> simp_all [Mode.isRoot]
        obtain ⟨dep, hd, n0, hr, _, hla⟩ := hbor hb
        exact ⟨dep, hd, n0, hr, hla⟩
      exact derive_lands (hroot ·) hbor' (Or.inr (Or.inr ⟨rfl, _, Child.elem hmem, hs⟩))
        (by rw [hty]; rfl)

/-- A field read out of the struct `y`: what the field holds, lent. -/
theorem out_comp {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) (hnint : E.ty ≠ .int) {o : Bool} {T x : Val} (hv : m.st y = some ⟨o, some T⟩)
    (hc : Child x T) {t : Ty} (htok : t.ok = true)
    (hown : WFv E.ty T → ViewsOK m E.ty T E.held → WFv t x ∧ ViewsOK m t x E.held)
    (hbor : ValOK m E.ty T E.path E.held → ValOK m t x (E.path ++ E.held) E.held) :
    RhsOut m Γ (projE y E t) (lendOf x) false := by
  have hint : t = .int ∨ projE y E t = ⟨t, .bor, true, projDeps y E ++ E.held, E.held⟩ := by
    cases t <;> simp [projE]
  -- what the field holds, valid as a borrow through `P`
  have key : ValOK m t (lendOf x) (projDeps y E ++ E.held) E.held := by
    rcases hi.mode_cases hy with hm | hm | hm
    · have hos : E.mode.ownSlot = true := by rw [hm]; rfl
      obtain ⟨T', hT', hwT, hvsT⟩ := hi.own_val hy hl hos
      rw [hT'] at hv; cases hv
      obtain ⟨hwx, hvx⟩ := hown hwT hvsT
      have hpd : projDeps y E = [⟨y, .inner⟩] := by simp [projDeps, hos]
      refine lend_valOK hwx (fun t' c d es hs => ⟨⟨y, .inner⟩, by simp [hpd], T, Or.inl hT',
        Or.inr (Or.inr ⟨rfl, x, hc, hs⟩)⟩) hvx (fun s _ => ?_)
      exact ViewsOK.mono (List.subset_append_right _ _) hvx
    all_goals
      have hos : E.mode.ownSlot = false := by rw [hm]; rfl
      obtain ⟨T', hT', hok⟩ := hi.bor_val hy hl hos
      rw [hT'] at hv; cases hv
      have hpd : projDeps y E = E.path := by simp [projDeps, hos]
      have hx := hbor hok
      rw [hpd, hx.lend]; exact hx
  rcases hint with rfl | heq
  · obtain ⟨n, hn⟩ := key
    simp only [projE]; rw [hn]; exact intE_out n
  · rw [heq]
    refine ⟨rfl, Or.inr rfl, rfl, htok, fun _ r hr => ?_, fun h => (by cases h), fun _ => key⟩
    rw [bor_vdeps _ rfl] at hr
    refine wf_append (wf_append ?_ (wf_held hi hy hl hnint)) (wf_held hi hy hl hnint) r hr
    unfold projDeps
    split
    · intro r hr; simp [roots] at hr; subst hr
      exact ⟨E, hy, by cases hm : E.mode <;> simp_all [Mode.ownSlot, Mode.isRoot]⟩
    · rename_i hos; exact wf_path hi hy hl hnint (by simpa using hos)

theorem out_fst {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (hty : E.ty = .prod a b) {o : Bool} {v w : Val}
    (hv : m.st y = some ⟨o, some (.pair v w)⟩) : RhsOut m Γ (projE y E a) (lendOf v) false := by
  have hok := hi.tyok hy; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  refine out_comp hi hy hl (by rw [hty]; simp) hv Child.fst hok.1 (fun hw hvs => ?_) (fun h => ?_)
  · rw [hty] at hw hvs; cases hw with
    | pair ha _ => exact ⟨ha, fun s x hin => hvs s x (ViewIn.fst hin)⟩
  · rw [hty] at h; obtain ⟨x, z, hxz, hx, _⟩ := h; cases hxz; exact hx

theorem out_snd {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (hty : E.ty = .prod a b) {o : Bool} {v w : Val}
    (hv : m.st y = some ⟨o, some (.pair v w)⟩) : RhsOut m Γ (projE y E b) (lendOf w) false := by
  have hok := hi.tyok hy; rw [hty] at hok
  simp only [Ty.ok, Bool.and_eq_true] at hok
  refine out_comp hi hy hl (by rw [hty]; simp) hv Child.snd hok.2 (fun hw hvs => ?_) (fun h => ?_)
  · rw [hty] at hw hvs; cases hw with
    | pair _ hb => exact ⟨hb, fun s x hin => hvs s x (ViewIn.snd hin)⟩
  · rw [hty] at h; obtain ⟨x, z, hxz, _, hz⟩ := h; cases hxz; exact hz

theorem rhs_new {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ) {t : Ty} (ht : t.ok = true) :
    let m1 : Mem := { m with alloc := upd (upd m.alloc m.nid true) (m.nid + 1) true, nid := m.nid + 2 }
    RhsPost m m1 Γ Γ F ∧ RhsOut m1 Γ ⟨.vec t, .own, true, [], []⟩ (.node t m.nid (m.nid + 1) []) true := by
  intro m1
  have hold : ∀ o U, OwnedAt m o U → ∀ i ∈ U.ids, m1.alloc i = m.alloc i := by
    intro o U hU i hi'
    have hlt := (hi.heap.alloc o U hU i hi').2
    show upd (upd m.alloc m.nid true) (m.nid + 1) true i = m.alloc i
    rw [upd_ne _ _ (by omega), upd_ne _ _ (by omega)]
  have hheap : HeapOK m1 :=
    { nodup := fun o U hU => hi.heap.nodup o U hU
      disj := fun o1 o2 U1 U2 hne h1 h2 => hi.heap.disj o1 o2 U1 U2 hne h1 h2
      alloc := fun o U hU i hi' => by
        obtain ⟨ha, hlt⟩ := hi.heap.alloc o U hU i hi'
        exact ⟨by rw [hold o U hU i hi']; exact ha, by show i < m.nid + 2; omega⟩
      self := fun o U hU => hi.heap.self o U hU }
  refine ⟨⟨hi.of_st rfl hheap (Nat.le_refl _), rfl, by show m.nid ≤ m.nid + 2; omega, fun _ => rfl, fun _ _ => rfl,
    fun _ _ h _ => h, fun _ => rfl, fun x E1 h => ⟨E1, h, rfl, rfl⟩⟩, ?_⟩
  refine ⟨rfl, Or.inl rfl, rfl, ht, fun _ r hr => by simp [roots, Entry.vdeps, Mode.ownSlot] at hr,
    fun _ => ⟨rfl, WFv.node (fun e he => by simp at he), fun s v hin => ?_, ?_, ?_, ?_, ?_⟩,
    fun h => by cases h⟩
  · cases hin with | child he _ => simp at he
  · simp
  · intro i hi'
    simp only [ids_node, idsL_nil, List.mem_cons, List.not_mem_nil, or_false] at hi'
    show upd (upd m.alloc m.nid true) (m.nid + 1) true i = true ∧ i < m.nid + 2
    rcases hi' with rfl | rfl
    · rw [upd_ne _ _ (by omega)]; simp
    · simp
  · intro x U hU i hi' hiU
    have hlt := (hi.heap.alloc x U hU i hiU).2
    simp only [ids_node, idsL_nil, List.mem_cons, List.not_mem_nil, or_false] at hi'
    rcases hi' with rfl | rfl <;> omega
  · intro d o l hs
    rcases hs.cases' with h | ⟨e, hc, _⟩
    · cases h
    · cases hc with | elem he => simp at he

theorem rhs_move {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {y : Var} {E : Entry} {v : Val} (hy : Γ y = some E) (hl : E.live = true) (hm : E.mode = .own)
    (hyF : y ∉ F) (hv : m.st y = some ⟨true, some v⟩) :
    RhsPost m (m.set y ⟨true, none⟩) Γ (setE (kill .replace false y Γ) y { E with live := false }) F ∧
    RhsOut (m.set y ⟨true, none⟩) (setE (kill .replace false y Γ) y { E with live := false })
      ⟨E.ty, .own, true, [], E.held⟩ v true := by
  have hos : E.mode.ownSlot = true := by rw [hm]; rfl
  obtain ⟨T, hT, hwT, hvsT⟩ := hi.own_val hy hl hos
  rw [hT] at hv; cases hv
  obtain ⟨sl, hsl, hok, hslot⟩ := hi.slot y E hy
  obtain ⟨_, hown, _⟩ := hslot
  obtain ⟨hvec, _, _⟩ := hown hos
  have hst : ∀ o, o ≠ y → (m.set y ⟨true, none⟩).st o = m.st o := fun o ho => by simp [upd_ne _ _ ho]
  have hheap : HeapOK (m.set y ⟨true, none⟩) := hi.heap.without hT (m.set y ⟨true, none⟩) (fun o U hU => by
      rcases ownedAt_set.mp hU with ⟨_, h⟩ | h
      · cases h
      · exact h) (fun _ _ => rfl) (Nat.le_refl _)
  have hinv : MInv (m.set y ⟨true, none⟩) (setE (kill .replace false y Γ) y { E with live := false }) := by
    refine hi.change hanch hy hyF (by rw [hm]; simp) hst hheap rfl
      (fun k hk => by cases k <;> simp [Eff.kills] at hk) ?_ (by simp)
    refine ⟨⟨true, none⟩, by simp, hok, ⟨by simp [hos], fun _ => ⟨hvec, fun T h => by simp at h,
      fun h => by simp at h⟩, fun h => by simp [hos] at h⟩, rfl, fun h => by simp at h⟩
  refine ⟨⟨hinv, rfl, Nat.le_refl _, fun x => ?_, fun x hx => hst x (fun h => hyF (h ▸ hx)), ?_, ?_, ?_⟩, ?_⟩
  · by_cases hxy : x = y
    · subst hxy; simp [hT]
    · rw [hst x hxy]
  · intro p Ep hp hpm
    have hpy : p ≠ y := fun h => by subst h; rw [hy] at hp; cases hp; rw [hm] at hpm; cases hpm
    simp only [setE, upd_ne _ _ hpy, kill, hp, Option.map_some]
    rw [killE_rootb hanch hyF _ _ hp hpm]
  · intro x
    by_cases hxy : x = y
    · subst hxy; simp [setE, hy]
    · simp only [setE, upd_ne _ _ hxy, kill]; cases Γ x <;> rfl
  · intro x E1 h
    by_cases hxy : x = y
    · subst hxy; simp only [setE, upd_same, Option.some.injEq] at h; subst h
      exact ⟨E, hy, rfl, rfl⟩
    · simp only [setE, upd_ne _ _ hxy, kill] at h
      cases hE : Γ x with
      | none => rw [hE] at h; cases h
      | some E0 => rw [hE] at h; cases h; exact ⟨E0, rfl, killE_mode .., killE_ty ..⟩
  · have hnint' : E.ty ≠ .int := fun h => by rw [h] at hvec; cases hvec
    refine ⟨rfl, Or.inl rfl, rfl, hi.tyok (E := E) hy, fun hn r hr => ?_, fun _ => ⟨hvec, hwT, ?_, ?_, ?_, ?_,
      hi.heap.self y v hT⟩, fun h => by cases h⟩
    · have hr' : r ∈ roots E.held := by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr
      obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hn r hr'
      by_cases hry : r = y
      · subst hry; exact ⟨{ E with live := false }, by simp [setE], by rw [hm]; rfl⟩
      · exact ⟨killE .replace false y Er, by simp [setE, upd_ne _ _ hry, kill, hEr],
          by rw [killE_mode]; exact hroot⟩
    · refine hvsT.keep_except hT (hi.heap.self y v hT) (fun s w h => h) (fun dep hd hne => ?_)
      obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hnint' dep.root (List.mem_map_of_mem hd)
      exact (rootKeep_frame hi hanch (fun o ho => hst o (fun h => hyF (h ▸ ho))) hEr hroot
        (hst _ hne)).vkeep
    · exact hi.heap.nodup y v hT
    · exact fun i hi' => hi.heap.alloc y v hT i hi'
    · intro x U hU i hi' hiU
      rcases ownedAt_set.mp hU with ⟨_, h⟩ | ⟨hxy, h⟩
      · cases h
      · exact hi.heap.disj y x v U (Ne.symm hxy) hT h i hi' hiU

theorem kill_eq_upd {Γ : Ctx} {y : Var} {E : Entry} (hy : Γ y = some E) (e : Eff) (hv : Bool) :
    kill e hv y Γ = upd (kill e hv y Γ) y (some (killE e hv y E)) := by
  funext v
  by_cases h : v = y
  · subst h; simp [kill, hy]
  · simp [upd_ne _ _ h]

theorem kill_dom {Γ : Ctx} (e : Eff) (hv : Bool) (y x : Var) :
    (kill e hv y Γ x).isSome = (Γ x).isSome := by
  simp only [kill]; cases Γ x <;> rfl

theorem kill_cmode {Γ : Ctx} {e : Eff} {hv : Bool} {y x : Var} {E1 : Entry}
    (h : kill e hv y Γ x = some E1) : ∃ E0, Γ x = some E0 ∧ E1.mode = E0.mode ∧ E1.ty = E0.ty := by
  simp only [kill] at h
  cases hE : Γ x with
  | none => rw [hE] at h; cases h
  | some E0 => rw [hE] at h; cases h; exact ⟨E0, rfl, killE_mode .., killE_ty ..⟩

theorem kill_root {Γ : Ctx} {e : Eff} {hv : Bool} {y r : Var} {Er : Entry} (h : Γ r = some Er)
    (hroot : Er.mode.isRoot = true) : ∃ E', kill e hv y Γ r = some E' ∧ E'.mode.isRoot = true :=
  ⟨killE e hv y Er, by simp [kill, h], by rw [killE_mode]; exact hroot⟩

/-- Dropping elements keeps a tree from viewing itself. -/
theorem SelfFree.shrink {t : Ty} {c d : Nat} {es es' : List Val} (hsf : SelfFree (.node t c d es'))
    (hsub : ∀ e ∈ es, e ∈ es') : SelfFree (.node t c d es) := by
  intro d0 o l hv u c0 es0 hn
  have lift : ∀ {w : Val}, Sub w (.node t c d es) → w = .node t c d es ∨ Sub w (.node t c d es') := by
    intro w hw
    rcases hw.cases' with h | ⟨e, hc, hs⟩
    · exact Or.inl h
    · cases hc with | elem he => exact Or.inr (Sub.child (hsub e he) hs)
  rcases lift hv with h | hv'
  · cases h
  rcases lift hn with h | hn'
  · cases h; exact hsf _ o l hv' t c es' (Sub.refl _)
  · exact hsf d0 o l hv' u c0 es0 hn'

theorem idsL_sub_append (es : List Val) (e : Val) : List.Sublist (idsL es) (idsL (es ++ [e])) := by
  rw [idsL_append]; exact List.sublist_append_left _ _

theorem rhs_pop {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    {y : Var} {E : Entry} {t : Ty} (hy : Γ y = some E) (hl : E.live = true) (hty : E.ty = .vec t)
    (hcan : canDo E.mode .drop) (hyF : y ∉ F)
    {t' : Ty} {c d : Nat} {es : List Val} {e : Val}
    (hT : m.st y = some ⟨true, some (.node t' c d (es ++ [e]))⟩) :
    RhsPost m (m.set y ⟨true, some (.node t' c d es)⟩) Γ (kill .drop t.holdsView y Γ) F ∧
    RhsOut (m.set y ⟨true, some (.node t' c d es)⟩) (kill .drop t.holdsView y Γ) (popE y E t) e
      e.owns := by
  have hm : E.mode = .own := by
    rcases hcan with h | ⟨b, h, _⟩
    · exact h
    · exact absurd h (hi.noInout y E b hy)
  have hos : E.mode.ownSlot = true := by rw [hm]; rfl
  obtain ⟨T, hT', hwT, hvsT⟩ := hi.own_val hy hl hos
  rw [hT] at hT'; cases hT'
  rw [hty] at hwT hvsT
  have htt : t' = t := by cases hwT; rfl
  subst htt
  have hwes : ∀ x ∈ es ++ [e], WFv t' x := fun x hx => hwT.elem rfl hx
  have hwS : WFv (.vec t') (.node t' c d es) := WFv.node (fun x hx => hwes x (by simp [hx]))
  have hemem : e ∈ es ++ [e] := by simp
  have hnT := hi.heap.nodup y _ hT
  have hsubl : List.Sublist (Val.node t' c d es).ids (Val.node t' c d (es ++ [e])).ids := by
    simp only [ids_node]; exact ((idsL_sub_append es e).cons₂ d).cons₂ c
  have hsube : List.Sublist e.ids (Val.node t' c d (es ++ [e])).ids := by
    simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil]
    exact ((List.sublist_append_right _ _).cons d).cons c
  -- the shrunk tree and the popped element do not overlap
  have hsep : ∀ i ∈ e.ids, i ∉ (Val.node t' c d es).ids := by
    intro i hie hiS
    simp only [ids_node, idsL_append, idsL_cons, idsL_nil, List.append_nil, List.nodup_cons,
      List.mem_cons, List.mem_append, List.nodup_append] at hnT hiS
    rcases hiS with rfl | rfl | hiS
    · exact hnT.1 (Or.inr (Or.inr hie))
    · exact hnT.2.1 (Or.inr hie)
    · exact hnT.2.2.2.2 i hiS i hie rfl
  let m1 := m.set y ⟨true, some (.node t' c d es)⟩
  have hst : ∀ o, o ≠ y → m1.st o = m.st o := fun o ho => by simp [m1, upd_ne _ _ ho]
  have hown1 : ∀ o U, OwnedAt m1 o U → (o = y ∧ U = .node t' c d es) ∨ (o ≠ y ∧ OwnedAt m o U) := by
    intro o U hU
    rcases ownedAt_set.mp hU with ⟨h1, h2⟩ | h
    · cases h2; exact Or.inl ⟨h1, rfl⟩
    · exact Or.inr h
  have hheap : HeapOK m1 :=
    { nodup := fun o U hU => by
        rcases hown1 o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact hnT.sublist hsubl
        · exact hi.heap.nodup o U h
      disj := fun o1 o2 U1 U2 hne h1 h2 => by
        rcases hown1 o1 U1 h1 with ⟨rfl, rfl⟩ | ⟨ho1, h1'⟩ <;>
          rcases hown1 o2 U2 h2 with ⟨rfl, rfl⟩ | ⟨ho2, h2'⟩
        · exact absurd rfl hne
        · exact fun i hi' => hi.heap.disj _ o2 _ U2 (Ne.symm ho2) hT h2' i (hsubl.subset hi')
        · exact fun i hi' hi'' => hi.heap.disj _ o1 _ U1 (Ne.symm ho1) hT h1' i (hsubl.subset hi'') hi'
        · exact hi.heap.disj o1 o2 U1 U2 hne h1' h2'
      alloc := fun o U hU i hi' => by
        rcases hown1 o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact hi.heap.alloc y _ hT i (hsubl.subset hi')
        · exact hi.heap.alloc o U h i hi'
      self := fun o U hU => by
        rcases hown1 o U hU with ⟨_, rfl⟩ | ⟨_, h⟩
        · exact (hi.heap.self y _ hT).shrink (fun x hx => List.mem_append_left _ hx)
        · exact hi.heap.self o U h }
  have hsfT := hi.heap.self y _ hT
  have hkeepF : ∀ dep ∈ E.held, dep.root ≠ y → VKeep m m1 dep := by
    intro dep hd hne
    have hnint : E.ty ≠ .int := by rw [hty]; simp
    obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hnint dep.root (List.mem_map_of_mem hd)
    exact (rootKeep_frame hi hanch (fun o ho => hst o (fun h => hyF (h ▸ ho))) hEr hroot
      (hst _ hne)).vkeep
  have hinv : MInv m1 (kill .drop t'.holdsView y Γ) := by
    rw [kill_eq_upd hy]
    refine hi.change hanch hy hyF (by rw [hm]; simp) hst hheap rfl ?_ ?_ (by simp)
    · intro k hk
      have hk' : k = .self ∧ t'.holdsView = false := by
        cases k <;> cases hh : t'.holdsView <;> simp_all [Eff.kills]
      obtain ⟨rfl, hhv⟩ := hk'
      refine ⟨fun d' o l s ha => absurd (viewAt_iff.mp ha).choose_spec.choose_spec.choose_spec.2.1
        (by simp), ?_⟩
      exact Evolve.self_hkeep ⟨hT, by simp [m1], hwS⟩ hhv
    · refine ⟨⟨true, some (.node t' c d es)⟩, by simp [m1], by rw [killE_ty, hty]; exact hi.tyok (E := E) hy ▸ (by rw [hty]),
        ⟨by rw [killE_mode, hm]; rfl, fun _ => ⟨by rw [killE_ty, hty]; rfl,
          fun U hU => by cases hU; rw [killE_ty, hty]; exact hwS,
          fun _ => ⟨_, rfl, by
            rw [killE_ty, killE_held, hty]
            exact hvsT.keep_except hT hsfT (fun s w h => by
              cases h with
              | child hm' hin => exact ViewIn.child (List.mem_append_left _ hm') hin) hkeepF⟩⟩,
          fun h => by rw [killE_mode, hm] at h; cases h⟩,
        by rw [killE_mode], fun hl' hn r hr => ?_⟩
      rw [killE_vdeps] at hr
      rw [killE_ty] at hn
      obtain ⟨Er, hEr, hroot⟩ := hi.wf y E hy hl (Or.inl hn) r hr
      by_cases hry : r = y
      · exact Or.inl ⟨hry, by rw [killE_mode, hm]; rfl⟩
      · exact Or.inr ⟨hry, kill_root hEr hroot⟩
  have hnint : E.ty ≠ .int := by rw [hty]; simp
  have hwfH : ∀ r ∈ roots E.held, ∃ Er, kill .drop t'.holdsView y Γ r = some Er ∧ Er.mode.isRoot = true :=
    fun r hr => by
      obtain ⟨Er, hEr, hroot⟩ := wf_held hi hy hl hnint r hr
      exact kill_root hEr hroot
  refine ⟨⟨hinv, rfl, Nat.le_refl _, fun x => ?_, fun x hx => hst x (fun h => hyF (h ▸ hx)), ?_,
    fun x => kill_dom .., fun x E1 h => kill_cmode h⟩, ?_⟩
  · by_cases hxy : x = y
    · subst hxy; simp [m1, hT]
    · rw [hst x hxy]
  · intro p Ep hp hpm
    simp only [kill, hp, Option.map_some]
    rw [killE_rootb hanch hyF _ _ hp hpm]
  · have hwe : WFv t' e := hwes e hemem
    cases t' with
    | int =>
      cases hwe with | int => exact intE_out _
    | slice s =>
      cases hwe with
      | view =>
        rename_i dv ov lv
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.slice s, .bor, true, E.held, E.held⟩ _ false
        have htok : (Ty.slice s).ok = true := by simpa [Ty.ok] using hok
        refine RhsOut.mk rfl (Or.inr rfl) rfl htok (fun _ => ?_) (fun h => nomatch h) (fun _ => ?_)
        · show ∀ r ∈ roots (E.held ++ E.held), _
          exact wf_append hwfH hwfH
        · obtain ⟨d', o', l', hv', dep, hd, ha⟩ := hvsT s _ (ViewIn.child hemem ViewIn.here)
          cases hv'
          refine ⟨_, _, _, rfl, dep, hd, hkeepF dep hd ?_ _ _ _ s ha⟩
          intro heq
          obtain ⟨r, k⟩ := dep
          simp only at heq; subst heq
          exact viewAt_not_self hT hsfT (ViewIn.child hemem ViewIn.here) ha
    | vec s =>
      cases hwe with
      | node hes =>
        rename_i c1 d1 es1
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.vec s, .own, true, [], E.held⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, WFv.node hes, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _))⟩, fun h => by cases h⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU
    | prod a b =>
      cases hwe with
      | pair hwa hwb =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.prod a b, .own, true, [], E.held⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, WFv.pair hwa hwb, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _))⟩, fun h => by cases h⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU
    | sum a b =>
      have hsumwf := hwe
      cases hwe with
      | inl _ | inr _ =>
        have hok := hi.tyok hy; rw [hty] at hok
        show RhsOut _ _ ⟨.sum a b, .own, true, [], E.held⟩ _ true
        refine ⟨rfl, Or.inl rfl, rfl, hok, fun _ r hr => ?_, fun _ => ⟨rfl, hsumwf, ?_, ?_,
          ?_, ?_, hsfT.sub (Sub.child hemem (Sub.refl _))⟩, fun h => by cases h⟩
        · exact hwfH r (by simpa [roots, Entry.vdeps, Mode.ownSlot] using hr)
        · exact hvsT.keep_except hT hsfT (fun s' w h => ViewIn.child hemem h) hkeepF
        · exact hnT.sublist hsube
        · exact fun i hi' => hi.heap.alloc y _ hT i (hsube.subset hi')
        · intro x U hU i hi' hiU
          rcases hown1 x U hU with ⟨_, rfl⟩ | ⟨hxy, h⟩
          · exact hsep i hi' hiU
          · exact hi.heap.disj y x _ U (Ne.symm hxy) hT h i (hsube.subset hi') hiU

end A2
