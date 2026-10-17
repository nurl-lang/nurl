import A2.Ctx

/-! A2 — what a change of memory leaves valid.

A borrow is valid through one of its dependencies.  If the memory that
dependency's root reaches is unchanged (`RootKeep`) — or changed only in a way
that does not end borrows of that kind (`push`/`pop` on the root) — the borrow
stays valid. -/

namespace A2

def RootKeep (m m' : Mem) (r : Var) : Prop := ∀ n, RootNode m r n → RootNode m' r n

def VKeep (m m' : Mem) (dep : Dep) : Prop :=
  ∀ d o l s, ViewAt m dep d o l s → ViewAt m' dep d o l s

def HKeep (m m' : Mem) (dep : Dep) : Prop :=
  ∀ c t H, (∀ h ∈ H, VKeep m m' h) → HrefAt m dep c t H → HrefAt m' dep c t H

theorem RootKeep.vkeep {m m' : Mem} {dep : Dep} (h : RootKeep m m' dep.root) : VKeep m m' dep := by
  intro d o l s ⟨n0, c, es, hr, hk, hl, hw⟩
  exact ⟨n0, c, es, h n0 hr, hk, hl, hw⟩

theorem ViewsOK.keep {m m' : Mem} {τ : Ty} {T : Val} {H : List Dep} (hk : ∀ h ∈ H, VKeep m m' h)
    (hv : ViewsOK m τ T H) : ViewsOK m' τ T H := by
  intro s v hin
  obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := hv s v hin
  exact ⟨d, o, l, rfl, dep, hd, hk dep hd d o l s ha⟩

theorem RootKeep.hkeep {m m' : Mem} {dep : Dep} (h : RootKeep m m' dep.root) : HKeep m m' dep := by
  intro c t H hH ⟨n0, d, es, hr, hk, hw, hv⟩
  exact ⟨n0, d, es, h n0 hr, hk, hw, hv.keep hH⟩

theorem ValOK.keep {m m' : Mem} {τ : Ty} {v : Val} {P H : List Dep}
    (hp : ∀ dep ∈ P, VKeep m m' dep ∧ HKeep m m' dep) (hh : ∀ dep ∈ H, VKeep m m' dep ∧ HKeep m m' dep)
    (h : ValOK m τ v P H) : ValOK m' τ v P H := by
  induction τ generalizing v P with
  | int => exact h
  | vec t =>
    obtain ⟨c, rfl, dep, hd, ha⟩ := h
    exact ⟨c, rfl, dep, hd, (hp dep hd).2 c t H (fun h hh' => (hh h hh').1) ha⟩
  | slice t =>
    obtain ⟨d, o, l, rfl, dep, hd, ha⟩ := h
    exact ⟨d, o, l, rfl, dep, hd, (hp dep hd).1 d o l t ha⟩
  | prod a b iha ihb =>
    obtain ⟨x, y, rfl, hx, hy⟩ := h
    have hph : ∀ dep ∈ P ++ H, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hh dep hd
    exact ⟨x, y, rfl, iha hph hx, ihb hph hy⟩
  | sum a b iha ihb =>
    have hph : ∀ dep ∈ P ++ H, VKeep m m' dep ∧ HKeep m m' dep := fun dep hd => by
      rcases List.mem_append.mp hd with hd | hd
      · exact hp dep hd
      · exact hh dep hd
    rcases h with ⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩
    · exact Or.inl ⟨x, rfl, iha hph hx⟩
    · exact Or.inr ⟨x, rfl, ihb hph hx⟩

/-! ### Borrowed parameters reach only frozen owners -/

theorem ViewIn.holdsView {τ T s v} (h : ViewIn τ T s v) : τ.holdsView = true := by
  induction h with
  | here => rfl
  | child _ _ ih => simpa [Ty.holdsView] using ih
  | fst _ ih => simp [Ty.holdsView, ih]
  | snd _ ih => simp [Ty.holdsView, ih]
  | inl _ ih => simp [Ty.holdsView, ih]
  | inr _ ih => simp [Ty.holdsView, ih]

theorem no_views {t : Ty} (ht : t.holdsView = false) (m : Mem) (T : Val) (H : List Dep) :
    ViewsOK m (.vec t) T H := by
  intro s v hin
  have := hin.holdsView
  simp [Ty.holdsView, ht] at this

theorem nodeAt_of_owned {m : Mem} {o : Var} {T n : Val} (ho : OwnedAt m o T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : NodeAt m c n :=
  ⟨o, T, ho, hs, t, d, es, hn⟩

theorem dataAt_of_owned {m : Mem} {o : Var} {T n : Val} (ho : OwnedAt m o T) (hs : Sub n T)
    {t : Ty} {c d : Nat} {es : List Val} (hn : n = .node t c d es) : DataAt m d n :=
  ⟨o, T, ho, hs, t, c, es, hn⟩

theorem Lands.sub {k : Kind} {n n0 : Val} (h : Lands k n n0) : Sub n n0 := by
  rcases h with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, hb⟩
  · exact Sub.refl _
  · exact Sub.refl _
  · exact hb.sub

theorem Top.sub {n v : Val} (h : Top n v) : Sub n v := by
  induction h with
  | refl => exact Sub.refl _
  | fst _ ih => exact Sub.fst ih
  | snd _ ih => exact Sub.snd ih
  | inl _ ih => exact Sub.inl ih
  | inr _ ih => exact Sub.inr ih

theorem Top.trans {a b c : Val} (h1 : Top a b) (h2 : Top b c) : Top a c := by
  induction h2 with
  | refl => exact h1
  | fst _ ih => exact Top.fst ih
  | snd _ ih => exact Top.snd ih
  | inl _ ih => exact Top.inl ih
  | inr _ ih => exact Top.inr ih

theorem Top.node {n : Val} {t : Ty} {c d : Nat} {es : List Val} (h : Top n (.node t c d es)) :
    n = .node t c d es := by
  cases h; rfl

/-- Every node a root reaches is inside some owned tree. -/
theorem RootNode.owned {m : Mem} {r : Var} {n : Val} (h : RootNode m r n) :
    ∃ o T, OwnedAt m o T ∧ Sub n T := by
  rcases h with ⟨T, h, ht⟩ | ⟨_, c, _, _, o, T, hT, hs, _⟩ | ⟨_, d, _, _, _, _, o, T, hT, hs, _⟩
  · exact ⟨r, T, h, ht.sub⟩
  · exact ⟨o, T, hT, hs⟩
  · exact ⟨o, T, hT, hs⟩

theorem append_assoc_sub {P H : List Dep} : (P ++ H) ++ H ⊆ P ++ H := by
  intro d hd
  rcases List.mem_append.mp hd with hd | hd
  · exact hd
  · exact List.mem_append_right _ hd

/-- A `Vec` handle inside a borrowed value reaches its node through one of
    the value's dependencies. -/
theorem valOK_href {m : Mem} (hh : HeapOK m) {c : Nat} {n : Val} (hn : NodeAt m c n) :
    ∀ {τ : Ty} {w : Val} {P H : List Dep}, ValOK m τ w P H → Top (.href c) w →
      ∃ dep ∈ P ++ H, ∃ n0, RootNode m dep.root n0 ∧ Lands dep.kind n n0 := by
  intro τ
  induction τ with
  | int => intro w P H hok ht; obtain ⟨_, rfl⟩ := hok; cases ht
  | slice t => intro w P H hok ht; obtain ⟨_, _, _, rfl, _⟩ := hok; cases ht
  | vec t =>
    intro w P H hok ht
    obtain ⟨c', rfl, dep, hd, n1, d, es, hr1, hl, _, _⟩ := hok
    cases ht
    obtain ⟨o, T, hoT, hsT⟩ := hr1.owned
    have := nodeAt_unique hh hn ⟨o, T, hoT, hl.sub.trans hsT, t, d, es, rfl⟩
    subst this
    exact ⟨dep, List.mem_append_left _ hd, n1, hr1, hl⟩
  | prod a b iha ihb =>
    intro w P H hok ht
    obtain ⟨x, y, rfl, hx, hy⟩ := hok
    cases ht with
    | fst ht =>
      obtain ⟨dep, hd, rest⟩ := iha hx ht
      exact ⟨dep, append_assoc_sub hd, rest⟩
    | snd ht =>
      obtain ⟨dep, hd, rest⟩ := ihb hy ht
      exact ⟨dep, append_assoc_sub hd, rest⟩
  | sum a b iha ihb =>
    intro w P H hok ht
    rcases hok with ⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩
    · cases ht with
      | inl ht =>
        obtain ⟨dep, hd, rest⟩ := iha hx ht
        exact ⟨dep, append_assoc_sub hd, rest⟩
    · cases ht with
      | inr ht =>
        obtain ⟨dep, hd, rest⟩ := ihb hx ht
        exact ⟨dep, append_assoc_sub hd, rest⟩

/-- A view inside a borrowed value reaches its buffer through one of the
    value's dependencies, of a kind that ends views. -/
theorem valOK_view {m : Mem} (hh : HeapOK m) {d o l : Nat} {n : Val} (hn : DataAt m d n) :
    ∀ {τ : Ty} {w : Val} {P H : List Dep}, ValOK m τ w P H → Top (.view d o l) w →
      ∃ dep ∈ P ++ H, ∃ n0, RootNode m dep.root n0 ∧ dep.kind ≠ .self ∧ Lands dep.kind n n0 := by
  intro τ
  induction τ with
  | int => intro w P H hok ht; obtain ⟨_, rfl⟩ := hok; cases ht
  | vec t => intro w P H hok ht; obtain ⟨_, rfl, _⟩ := hok; cases ht
  | slice t =>
    intro w P H hok ht
    obtain ⟨d', o', l', rfl, dep, hd, n1, c, es, hr1, hk, _, _⟩ := hok
    cases ht
    have hl' : Lands dep.kind (.node t c d es) n1 := by
      rcases hk with ⟨h1, h2⟩ | ⟨h1, h2⟩
      · exact Or.inr (Or.inl ⟨h1, h2⟩)
      · exact Or.inr (Or.inr ⟨h1, h2⟩)
    have hks : dep.kind ≠ .self := by rcases hk with ⟨h1, _⟩ | ⟨h1, _⟩ <;> rw [h1] <;> decide
    obtain ⟨o2, T, hoT, hsT⟩ := hr1.owned
    have := dataAt_unique hh hn ⟨o2, T, hoT, hl'.sub.trans hsT, t, c, es, rfl⟩
    subst this
    exact ⟨dep, List.mem_append_left _ hd, n1, hr1, hks, hl'⟩
  | prod a b iha ihb =>
    intro w P H hok ht
    obtain ⟨x, y, rfl, hx, hy⟩ := hok
    cases ht with
    | fst ht =>
      obtain ⟨dep, hd, rest⟩ := iha hx ht
      exact ⟨dep, append_assoc_sub hd, rest⟩
    | snd ht =>
      obtain ⟨dep, hd, rest⟩ := ihb hy ht
      exact ⟨dep, append_assoc_sub hd, rest⟩
  | sum a b iha ihb =>
    intro w P H hok ht
    rcases hok with ⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩
    · cases ht with
      | inl ht =>
        obtain ⟨dep, hd, rest⟩ := iha hx ht
        exact ⟨dep, append_assoc_sub hd, rest⟩
    · cases ht with
      | inr ht =>
        obtain ⟨dep, hd, rest⟩ := ihb hx ht
        exact ⟨dep, append_assoc_sub hd, rest⟩

/-- A value held at the top of a borrowed slot `y` is valid through `y`
    itself: every handle in it is one `y` holds. -/
theorem valOK_via {m : Mem} {y : Var} {T : Val} (hy : m.st y = some ⟨false, some T⟩) :
    ∀ {τ : Ty} {w : Val} {P H Q : List Dep}, ValOK m τ w P H → Top w T → ⟨y, .view⟩ ∈ Q →
      ValOK m τ w Q H := by
  intro τ
  induction τ with
  | int => intro w P H Q hok _ _; exact hok
  | vec t =>
    intro w P H Q hok ht hq
    obtain ⟨c, rfl, dep, hd, n1, d, es, hr1, hl, hw, hv⟩ := hok
    obtain ⟨o, T', hoT, hsT⟩ := hr1.owned
    exact ⟨c, rfl, _, hq, _, d, es,
      Or.inr (Or.inl ⟨T, c, hy, ht, o, T', hoT, hl.sub.trans hsT, t, d, es, rfl⟩),
      Or.inr (Or.inl ⟨rfl, rfl⟩), hw, hv⟩
  | slice t =>
    intro w P H Q hok ht hq
    obtain ⟨d, o, l, rfl, dep, hd, n1, c, es, hr1, hk, hlen, hw⟩ := hok
    have hsub : Sub (.node t c d es) n1 := by
      rcases hk with ⟨_, h⟩ | ⟨_, h⟩
      · rw [h]; exact Sub.refl _
      · exact h.sub
    obtain ⟨o2, T', hoT, hsT⟩ := hr1.owned
    exact ⟨d, o, l, rfl, _, hq, _, c, es,
      Or.inr (Or.inr ⟨T, d, o, l, hy, ht, o2, T', hoT, hsub.trans hsT, t, c, es, rfl⟩),
      Or.inl ⟨rfl, rfl⟩, hlen, hw⟩
  | prod a b iha ihb =>
    intro w P H Q hok ht hq
    obtain ⟨x, z, rfl, hx, hz⟩ := hok
    exact ⟨x, z, rfl, iha hx (Top.trans (Top.fst (Top.refl _)) ht) (List.mem_append_left _ hq),
      ihb hz (Top.trans (Top.snd (Top.refl _)) ht) (List.mem_append_left _ hq)⟩
  | sum a b iha ihb =>
    intro w P H Q hok ht hq
    rcases hok with ⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩
    · exact Or.inl ⟨x, rfl, iha hx (Top.trans (Top.inl (Top.refl _)) ht) (List.mem_append_left _ hq)⟩
    · exact Or.inr ⟨x, rfl, ihb hx (Top.trans (Top.inr (Top.refl _)) ht) (List.mem_append_left _ hq)⟩

/-- What a borrowed slot reaches, it reaches through the dependencies of the
    value it holds. -/
theorem bor_lands {m : Mem} (hh : HeapOK m) {p : Var} {τ : Ty} {w : Val} {P H : List Dep}
    (hp : m.st p = some ⟨false, some w⟩) (hok : ValOK m τ w P H) {n0 : Val}
    (hr : RootNode m p n0) : ∃ d' ∈ P ++ H, ∃ n1, RootNode m d'.root n1 ∧ Lands d'.kind n0 n1 := by
  rcases hr with ⟨T, h, _⟩ | ⟨v, c, hc, ht, hn⟩ | ⟨v, d, o, l, hc, ht, hn⟩
  · rw [hp] at h; cases h
  · rw [hp] at hc; cases hc
    exact valOK_href hh hn hok ht
  · rw [hp] at hc; cases hc
    obtain ⟨dep, hd, n1, hr1, _, hl⟩ := valOK_view hh hn hok ht
    exact ⟨dep, hd, n1, hr1, hl⟩

/-- Every borrowed parameter reaches memory inside a frozen owner's tree. -/
theorem rootb_anchor {m : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F) :
    ∀ p E n, Γ p = some E → E.mode = .rootb → RootNode m p n →
      ∃ o T, o ∈ F ∧ OwnedAt m o T ∧ Sub n T := by
  intro p
  induction p using Nat.strongRecOn with
  | _ p ih =>
  intro E n hp hm hrn
  have hlive := hi.rootbLive p E hp hm
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot p E hp
  have hos : E.mode.ownSlot = false := by rw [hm]; rfl
  obtain ⟨v, hv, hok⟩ := hbor hos hlive
  have hsl' : sl = ⟨false, some v⟩ := by
    obtain ⟨own, val⟩ := sl
    simp only at hv hso; subst hv; rw [hso, hos]
  rw [hsl'] at hsl
  obtain ⟨dep, hd, n0, hr, hl⟩ := bor_lands hi.heap hsl hok hrn
  have hdv : dep.root ∈ roots E.vdeps := by
    simp only [roots, Entry.vdeps, hos, Bool.false_eq_true, ↓reduceIte, List.mem_map]
    exact ⟨dep, hd, rfl⟩
  have hF := hanch p E hp hm dep.root hdv
  have hnint : E.ty ≠ .int := by
    intro h; rw [h] at hok; obtain ⟨k, rfl⟩ := hok
    rcases hrn with ⟨_, h1, _⟩ | ⟨_, c, h1, ht, _⟩ | ⟨_, d, o, l, h1, ht, _⟩ <;> rw [hsl] at h1 <;>
      cases h1 <;> cases ht
  obtain ⟨Er, hEr, hroot⟩ := hi.wf p E hp hlive (Or.inl hnint) dep.root hdv
  rcases hr with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hn⟩ | ⟨w, d, o, l, hc, ht, hn⟩
  · exact ⟨dep.root, T, hF, hown, hl.sub.trans ht.sub⟩
  all_goals
    have hlt := hi.rootbLt p E hp hm dep.root hdv
    obtain ⟨slr, hslr, _, hsor, _, _⟩ := hi.slot dep.root Er hEr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hslr; cases hslr
      cases hme : Er.mode with
      | own => rw [hme] at hsor; simp [Mode.ownSlot] at hsor
      | inout b => exact absurd hme (hi.noInout _ Er b hEr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨o', T', hF', ho', hs'⟩ := ih dep.root hlt Er n0 hEr hrb (Or.inr (Or.inl ⟨w, c, hc, ht, hn⟩))
    exact ⟨o', T', hF', ho', hl.sub.trans hs'⟩
  · obtain ⟨o', T', hF', ho', hs'⟩ := ih dep.root hlt Er n0 hEr hrb (Or.inr (Or.inr ⟨w, d, o, l, hc, ht, hn⟩))
    exact ⟨o', T', hF', ho', hl.sub.trans hs'⟩

/-- A root whose slot is unchanged, at a point where every slot that changes
    is outside the frozen owners, reaches the same memory. -/
theorem rootKeep_frame {m m' : Mem} {Γ : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∈ F)
    (hF : ∀ o ∈ F, m'.st o = m.st o) {r : Var} {Er : Entry} (hr : Γ r = some Er)
    (hroot : Er.mode.isRoot = true) (hsame : m'.st r = m.st r) : RootKeep m m' r := by
  intro n hn
  rcases hn with ⟨T, hown, ht⟩ | ⟨w, c, hc, ht, hnode⟩ | ⟨w, d, o, l, hc, ht, hdata⟩
  · exact Or.inl ⟨T, by rw [hsame]; exact hown, ht⟩
  all_goals
    obtain ⟨sl, hsl, _, hso, _, _⟩ := hi.slot r Er hr
    have hrb : Er.mode = .rootb := by
      rw [hc] at hsl; cases hsl
      cases hme : Er.mode with
      | own => rw [hme] at hso; simp [Mode.ownSlot] at hso
      | inout b => exact absurd hme (hi.noInout _ Er b hr)
      | rootb => rfl
      | bor => rw [hme] at hroot; simp [Mode.isRoot] at hroot
  · obtain ⟨o', T, hoF, hoT, hsT⟩ :=
      rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inl ⟨w, c, hc, ht, hnode⟩))
    obtain ⟨_, _, _, _, ty, d, es, hneq⟩ := hnode
    refine Or.inr (Or.inl ⟨w, c, by rw [hsame]; exact hc, ht, ?_⟩)
    exact nodeAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq
  · obtain ⟨o', T, hoF, hoT, hsT⟩ :=
      rootb_anchor hi hanch r Er n hr hrb (Or.inr (Or.inr ⟨w, d, o, l, hc, ht, hdata⟩))
    obtain ⟨_, _, _, _, ty, c, es, hneq⟩ := hdata
    refine Or.inr (Or.inr ⟨w, d, o, l, by rw [hsame]; exact hc, ht, ?_⟩)
    exact dataAt_of_owned (by unfold OwnedAt; rw [hF o' hoF]; exact hoT) hsT hneq

/-! ### A root that grows or shrinks in place -/

/-- `x`'s tree went from `node t c d es` to `node t c d' es'`. -/
structure Evolve (m m' : Mem) (x : Var) (t : Ty) (c d d' : Nat) (es es' : List Val) : Prop where
  before : m.st x = some ⟨true, some (.node t c d es)⟩
  after  : m'.st x = some ⟨true, some (.node t c d' es')⟩
  wf     : WFv (.vec t) (.node t c d' es')

theorem rootNode_own {m : Mem} {x : Var} {T n : Val} (h : m.st x = some ⟨true, some T⟩)
    (hn : RootNode m x n) : Top n T := by
  rcases hn with ⟨_, h', ht⟩ | ⟨_, c, h', _⟩ | ⟨_, d, o, l, h', _⟩ <;> rw [h] at h' <;> cases h'
  exact ht

theorem rootNode_node {m : Mem} {x : Var} {t : Ty} {c d : Nat} {es : List Val} {n : Val}
    (h : m.st x = some ⟨true, some (.node t c d es)⟩) (hn : RootNode m x n) : n = .node t c d es :=
  (rootNode_own h hn).node

/-- Growing (`vec_push`): what is below the root stays below it. -/
theorem Evolve.grow_vkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (hpre : ∀ e ∈ es, e ∈ es') {k : Kind} (hk : k ≠ .view) :
    VKeep m m' ⟨x, k⟩ := by
  intro dd o l s ⟨n0, c', es2, hr, hkk, hl, hw⟩
  have := rootNode_node hev.before hr
  subst this
  rcases hkk with ⟨hv, _⟩ | ⟨hki, hb⟩
  · exact absurd hv hk
  · obtain ⟨e, hc, hs⟩ := hb
    cases hc with
    | elem he =>
      exact ⟨_, c', es2, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inr ⟨hki, e, Child.elem (hpre e he), hs⟩, hl, hw⟩

theorem Evolve.grow_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (hpre : ∀ e ∈ es, e ∈ es') {k : Kind}
    (hk : k = .self → t.holdsView = false) (hkv : k ≠ .view) : HKeep m m' ⟨x, k⟩ := by
  intro c2 t2 H hH ⟨n0, d2, es2, hr, hkk, hw, hv⟩
  have := rootNode_node hev.before hr
  subst this
  rcases hkk with ⟨hs, heq⟩ | ⟨hvw, _⟩ | ⟨hin, hb⟩
  · cases heq
    exact ⟨_, d', es', Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inl ⟨hs, rfl⟩, hev.wf, no_views (hk hs) _ _ _⟩
  · exact absurd hvw hkv
  · obtain ⟨e, hc, hs⟩ := hb
    cases hc with
    | elem he =>
      exact ⟨_, d2, es2, Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inr (Or.inr ⟨hin, e, Child.elem (hpre e he), hs⟩),
        hw, hv.keep hH⟩

/-- Shrinking (`vec_pop`): only a borrow of the whole handle survives, and
    only of a container that holds no views. -/
theorem Evolve.self_hkeep {m m' : Mem} {x : Var} {t : Ty} {c d d' : Nat} {es es' : List Val}
    (hev : Evolve m m' x t c d d' es es') (ht : t.holdsView = false) : HKeep m m' ⟨x, .self⟩ := by
  intro c2 t2 H hH ⟨n0, d2, es2, hr, hkk, hw, hv⟩
  have := rootNode_node hev.before hr
  subst this
  rcases hkk with ⟨_, heq⟩ | ⟨hin, _⟩ | ⟨hin, _⟩
  · cases heq
    exact ⟨_, d', es', Or.inl ⟨_, hev.after, Top.refl _⟩, Or.inl ⟨rfl, rfl⟩, hev.wf, no_views ht _ _ _⟩
  · cases hin
  · cases hin

/-! ### Rerooting at the end of a borrowed parameter's scope -/

theorem comp_self_left (k : Kind) : comp .self k = k := by cases k <;> rfl

/-- What lands in `p`'s node with kind `k` lands in the node `p` borrows
    from, with the composed kind. -/
theorem lands_comp {n0 n1 N : Val} {kp k : Kind}
    (hp : kp = .self ∧ n0 = n1 ∨ kp = .view ∧ n0 = n1 ∨ kp = .inner ∧ Below n0 n1)
    (hk : k = .self ∧ N = n0 ∨ k = .view ∧ N = n0 ∨ k = .inner ∧ Below N n0) :
    comp kp k = .self ∧ N = n1 ∨ comp kp k = .view ∧ N = n1 ∨ comp kp k = .inner ∧ Below N n1 := by
  rcases hp with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, hb⟩ <;>
    rcases hk with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, hb'⟩
  all_goals first
    | exact Or.inl ⟨rfl, rfl⟩
    | exact Or.inr (Or.inl ⟨rfl, rfl⟩)
    | exact Or.inr (Or.inr ⟨rfl, hb'⟩)
    | exact Or.inr (Or.inr ⟨rfl, hb⟩)
    | exact Or.inr (Or.inr ⟨rfl, Below.of_sub_below hb'.sub hb⟩)

end A2
