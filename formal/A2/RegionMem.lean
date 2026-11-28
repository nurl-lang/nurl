module

public import A2.ThruPre

@[expose] public section

/-! A2 — AGORA-937 stage 3b, first part: what a parameter's region reaches
in memory (`A2/THRU_STAGE3_DESIGN.md`).

At a through-changing call that passes views of the caller's memory, each
regioned parameter's region is lifted as a ghost binding. Its ghost value is
a set of buffer addresses `D`: those of the views its argument stores. It is
not a copy of the values there, because the body changes those nodes in
place. A region reaches the node *currently* at one of its addresses
(`RegionNode`). That is `RootNode`'s view case generalised: a borrowed slot
with `view d o l` at its top reaches `DataAt m d n`. So what lands through a
dependency on a region lands exactly as through any other (`Lands`), and a
view a region dependency validates is valid as `ViewAt` says.

This file proves the facts the call's entry needs:

* the views an argument stores, valid as the caller's invariant says
  (`ViewsOK`), are valid through its region (`ViewsOK.region_viewAt`);
* the node at each address is unique (`RegionNode.unique`);
* derived borrows compose kinds through a region as through a root
  (`RegionLanded.comp`);
* what lands through a region lands through the argument's own roots at
  the composed kind (`RegionLanded.landed`, with `ViewsOK.region_landed` for
  its hypothesis at the call's entry). So the memory invariant can be stated
  of the context with each region dependency `⟨π p, k⟩` replaced by
  `⟨r, comp a k⟩` for what the argument holds, `⟨r, a⟩`: the caller's roots,
  which it already speaks of;
* the kinds-composed substitution `subDc` and `LandedR.subDc`/`_list`: with
  each region read as its addresses, what lands through a dependency lands
  through its substitution;
* deriving a borrow commutes with the substitution (`subDc_derive`, from
  `comp_assoc`);
* a change strictly inside a region's node keeps the node's address and
  length, so a view of its buffer stays in bounds (`Repl.keeps_enclosing`,
  `DataAt.keeps_enclosing`, `RegionViewAt.keeps_len`), and the view itself
  survives such a change, well-formed (`RegionViewAt.keep_inner`).

Nothing here is used by a typing rule yet, and no theorem statement
changes. -/

namespace A2

/-- The buffer addresses of the views a value of type `τ` stores. -/
def ViewAddr (τ : Ty) (T : Val) (d : Nat) : Prop := ∃ s o l, ViewIn τ T s (.view d o l)

/-- A region of buffer addresses `D` reaches the node whose element buffer
    is one of them, wherever it is in memory: in an owned tree or a live
    payload (`DataAt`). -/
def RegionNode (m : Mem) (D : Nat → Prop) (n : Val) : Prop := ∃ d, D d ∧ DataAt m d n

/-- What lands through a dependency of kind `k` on a region: where the
    node it reaches puts it (`Lands`), as for a root (`Landed`). -/
def RegionLanded (m : Mem) (D : Nat → Prop) (k : Kind) (n : Val) : Prop :=
  ∃ n0, RegionNode m D n0 ∧ Lands k n n0

/-- A view of element type `t` valid through a dependency of kind `k` on a
    region, as `ViewAt` is through a dependency on a root. -/
def RegionViewAt (m : Mem) (D : Nat → Prop) (k : Kind) (d o l : Nat) (t : Ty) : Prop :=
  ∃ c es, k ≠ .self ∧ RegionLanded m D k (.node t c d es) ∧
    o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es)

/-- A valid view's buffer is a node in memory. -/
theorem ViewAt.dataAt {m : Mem} {dep : Dep} {d o l : Nat} {t : Ty} (h : ViewAt m dep d o l t) :
    ∃ c es, DataAt m d (.node t c d es) ∧ o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es) := by
  obtain ⟨c, es, -, hl, hle, hw⟩ := h
  exact ⟨c, es, hl.inMem.dataAt rfl, hle, hw⟩

/-- **The views an argument stores are valid through its region.** A value
    whose views are valid as the invariant says (`ViewsOK`, through what its
    binding holds) has each of them valid through a view dependency on the
    region of its own buffer addresses. That is the region clause at the
    call's entry. -/
theorem ViewsOK.region_viewAt {m : Mem} {τ : Ty} {T : Val} {H : List Dep} (h : ViewsOK m τ T H)
    {s : Ty} {d o l : Nat} (hv : ViewIn τ T s (.view d o l)) :
    RegionViewAt m (ViewAddr τ T) .view d o l s := by
  obtain ⟨d', o', l', heq, ⟨dep, -, hva⟩ | hsv⟩ := h s _ hv
  · cases heq
    obtain ⟨c, es, hd, hle, hw⟩ := hva.dataAt
    exact ⟨c, es, by decide, ⟨_, ⟨d, ⟨s, o, l, hv⟩, hd⟩, Or.inr (Or.inl ⟨rfl, rfl⟩)⟩, hle, hw⟩
  · -- AGORA-980: a static literal's text is a node in memory too, its block's
    cases heq
    obtain ⟨rfl, k, bl, c, es, hk, _, hs, hle, hw⟩ := hsv
    exact ⟨c, es, by decide, ⟨_, ⟨d, ⟨.int, o, l, hv⟩, .inr ⟨k, bl, hk, hs, .int, c, es, rfl⟩⟩,
      Or.inr (Or.inl ⟨rfl, rfl⟩)⟩, hle, hw⟩

/-- ... and each address of the region reaches a node. -/
theorem ViewsOK.region_node {m : Mem} {τ : Ty} {T : Val} {H : List Dep} (h : ViewsOK m τ T H)
    {d : Nat} (hd : ViewAddr τ T d) : ∃ n, RegionNode m (ViewAddr τ T) n ∧ ∃ ty c es, n = .node ty c d es := by
  obtain ⟨s, o, l, hv⟩ := hd
  obtain ⟨c, es, -, ⟨n0, ⟨d0, hD, hn⟩, hl⟩, -, -⟩ := h.region_viewAt hv
  rcases hl with ⟨h1, -⟩ | ⟨-, rfl⟩ | ⟨h1, -⟩ | ⟨_, h1, -⟩
  · cases h1
  · exact ⟨_, ⟨d0, hD, hn⟩, s, c, es, rfl⟩
  · cases h1
  · cases h1

/-- The node at an address is unique (the heap invariant), so a region
    reaches one node per address. -/
theorem RegionNode.unique {m : Mem} (hh : HeapOK m) {d : Nat} {n1 n2 : Val}
    (h1 : DataAt m d n1) (h2 : DataAt m d n2) : n1 = n2 :=
  dataAt_unique hh h1 h2

/-- A borrow derived through a region dependency lands at the composed kind,
    as one derived through a root does (`lands_comp'`). -/
theorem RegionLanded.comp {m : Mem} {D : Nat → Prop} {kp k : Kind} {n0 N : Val}
    (hp : RegionLanded m D kp n0) (hk : Lands k N n0) : RegionLanded m D (comp kp k) N := by
  obtain ⟨n1, hr, hl⟩ := hp
  exact ⟨n1, hr, lands_comp' hl hk⟩

/-- A region over fewer addresses reaches no more. -/
theorem RegionLanded.mono {m : Mem} {D D' : Nat → Prop} (hD : ∀ d, D d → D' d) {k : Kind} {n : Val}
    (h : RegionLanded m D k n) : RegionLanded m D' k n := by
  obtain ⟨n0, ⟨d, hd, hn⟩, hl⟩ := h
  exact ⟨n0, ⟨d, hD d hd, hn⟩, hl⟩

/-- Composing with a dependency that is not a name never gives a name. -/
theorem comp_share_left {k : Kind} (hk : k.isName = false) : comp .share k = .share := by
  cases k <;> simp_all [comp, Kind.isName]

/-- **A view through a region lands through the argument's own roots**,
    at the composed kind: if every node at one of the region's addresses
    lands through some dependency in `S` (the views the argument holds are
    valid through it), then what lands through a non-name dependency of
    kind `k` on the region lands through `⟨r, comp a k⟩` for some `⟨r, a⟩ ∈ S`.
    So a context in which each region dependency is replaced by what the
    argument holds, kinds composed, states the same validity in terms of the
    caller's roots, which the memory invariant already speaks of. -/
theorem RegionLanded.landed {m : Mem} {D : Nat → Prop} {S : List Dep}
    (hS : ∀ d n0, D d → DataAt m d n0 → ∃ dep ∈ S, Landed m dep n0)
    {k : Kind} (hk : k.isName = false) {n : Val} (h : RegionLanded m D k n) :
    ∃ dep ∈ S, Landed m ⟨dep.root, A2.comp dep.kind k⟩ n := by
  obtain ⟨n0, ⟨d, hd, hn⟩, hl⟩ := h
  obtain ⟨dep, hdep, hL⟩ := hS d n0 hd hn
  refine ⟨dep, hdep, ?_⟩
  rcases hL with ⟨n1, hr, hl1⟩ | ⟨hks, hrm, hip⟩
  · exact Or.inl ⟨n1, hr, lands_comp' hl1 hl⟩
  · refine Or.inr ⟨?_, hrm, hip.sub hl.sub⟩
    show A2.comp dep.kind k = .share
    rw [hks]; exact comp_share_left hk

/-- ... and the hypothesis holds of an argument's region at the call's entry:
    every node at an address of a view the argument stores, valid as the
    invariant says, lands through what the argument holds (the heap makes
    the node at an address unique), or (AGORA-980) is a static literal's
    text, which needs no dependency. -/
theorem ViewsOK.region_landed {m : Mem} (hh : HeapOK m) {τ : Ty} {T : Val} {H : List Dep}
    (h : ViewsOK m τ T H) : ∀ d n0, ViewAddr τ T d → DataAt m d n0 →
      (∃ dep ∈ H, Landed m dep n0) ∨ ∃ o l s, SViewAt m d o l s := by
  intro d n0 hd hn0
  obtain ⟨s, o, l, hv⟩ := hd
  obtain ⟨d', o', l', heq, ⟨dep, hdep, hva⟩ | hsv⟩ := h s _ hv
  · cases heq
    obtain ⟨c, es, -, hL, -, -⟩ := hva
    have := RegionNode.unique hh hn0 (hL.inMem.dataAt rfl)
    subst this
    exact .inl ⟨dep, hdep, hL⟩
  · cases heq; exact .inr ⟨o, l, s, hsv⟩

/-! ### The kinds-composed substitution

Where a call places the body, the invariant is stated of the context in
which each dependency on a region is replaced by what the region stands for
(`σ`), each composed with the dependency's kind. Today's lift (`subD`) copies
the argument's kinds verbatim and relies on `RSetup.A` covering every kind
on the arguments' roots; stage 3 drops that for roots reached through a
region, so the kinds must compose. -/

/-- The kinds-composed substitution of a dependency. One on a region
    (`isPi`) becomes what the region stands for, each dependency composed
    with this one's kind. A name on a region is dropped, since no region is
    changed by name. Any other dependency is kept. -/
def subDc (isPi : Var → Bool) (σ : Var → List Dep) (d : Dep) : List Dep :=
  if isPi d.root then
    (if d.kind.isName then [] else (σ d.root).map fun e => ⟨e.root, A2.comp e.kind d.kind⟩)
  else [d]

/-- Where a dependency lands with each region read as its addresses
    (`reg`): through the region (`RegionLanded`), or as any dependency does. -/
def LandedR (m : Mem) (isPi : Var → Bool) (reg : Var → Nat → Prop) (dep : Dep) (n : Val) : Prop :=
  if isPi dep.root then RegionLanded m (reg dep.root) dep.kind n else Landed m dep n

/-- **What lands through a dependency, regions read as their addresses,
    lands through its kinds-composed substitution**, where each region's
    nodes land through what it stands for (`RegionLanded.landed`). -/
theorem LandedR.subDc {m : Mem} {isPi : Var → Bool} {reg : Var → Nat → Prop} {σ : Var → List Dep}
    (hreg : ∀ v, isPi v = true → ∀ d n0, reg v d → DataAt m d n0 → ∃ e ∈ σ v, Landed m e n0)
    {dep : Dep} {n : Val} (h : LandedR m isPi reg dep n) :
    ∃ e ∈ A2.subDc isPi σ dep, Landed m e n := by
  unfold LandedR at h
  unfold A2.subDc
  by_cases hp : isPi dep.root = true
  · simp only [hp, ↓reduceIte] at h ⊢
    have hnm : dep.kind.isName = false := by
      obtain ⟨n0, -, hl⟩ := h; exact lands_notName hl
    rw [hnm]
    obtain ⟨e, he, hL⟩ := RegionLanded.landed (hreg dep.root hp) hnm h
    exact ⟨⟨e.root, A2.comp e.kind dep.kind⟩, List.mem_map.mpr ⟨e, he, rfl⟩, hL⟩
  · simp only [Bool.not_eq_true] at hp
    simp only [hp, Bool.false_eq_true, ↓reduceIte] at h ⊢
    exact ⟨dep, List.mem_singleton_self _, h⟩

/-- ... and so for a list of dependencies, as `ValOK` and `ViewsOK` ask:
    some dependency of the list validates the value, and then some
    dependency of its substitution does. -/
theorem LandedR.subDc_list {m : Mem} {isPi : Var → Bool} {reg : Var → Nat → Prop} {σ : Var → List Dep}
    (hreg : ∀ v, isPi v = true → ∀ d n0, reg v d → DataAt m d n0 → ∃ e ∈ σ v, Landed m e n0)
    {P : List Dep} {n : Val} (h : ∃ dep ∈ P, LandedR m isPi reg dep n) :
    ∃ e ∈ P.flatMap (A2.subDc isPi σ), Landed m e n := by
  obtain ⟨dep, hd, hL⟩ := h
  obtain ⟨e, he, hLe⟩ := hL.subDc hreg
  exact ⟨e, List.mem_flatMap.mpr ⟨dep, hd, he⟩, hLe⟩

/-- No region: the substitution changes nothing. -/
theorem subDc_noPi {isPi : Var → Bool} {σ : Var → List Dep} {d : Dep} (h : isPi d.root = false) :
    A2.subDc isPi σ d = [d] := by
  simp [A2.subDc, h]

/-- ... nor what is read as landing. -/
theorem LandedR.of_noPi {m : Mem} {isPi : Var → Bool} {reg : Var → Nat → Prop} {dep : Dep} {n : Val}
    (h : isPi dep.root = false) : LandedR m isPi reg dep n ↔ Landed m dep n := by
  simp [LandedR, h]

/-! ### The substitution commutes with deriving a borrow

A borrow derived from a borrowed entry composes each of its dependencies'
kinds with the borrow's (`derive`). Composing is associative, so deriving
and then substituting is substituting and then deriving. The substituted
context's derived borrows are then those of the substituted entries,
however the body derives them. -/

/-- Composing a dependency's kind with one that is not a name gives a name
    only when the dependency's was one. -/
theorem comp_isName_r {a k : Kind} (hk : k.isName = false) : (A2.comp a k).isName = a.isName := by
  cases a <;> cases k <;> simp_all [A2.comp, Kind.isName]

/-- Composing every dependency with a kind `k` that is not a name commutes
    with the substitution. -/
theorem subDc_comp {isPi : Var → Bool} {σ : Var → List Dep} {k : Kind} (hk : k.isName = false) (d : Dep) :
    A2.subDc isPi σ ⟨d.root, A2.comp d.kind k⟩ =
      (A2.subDc isPi σ d).map fun e => ⟨e.root, A2.comp e.kind k⟩ := by
  unfold A2.subDc
  by_cases hp : isPi d.root = true
  · simp only [hp, ↓reduceIte]
    rw [comp_isName_r hk]
    cases hn : d.kind.isName
    · simp only [Bool.false_eq_true, ↓reduceIte, List.map_map]
      apply List.map_congr_left
      intro e _
      simp [comp_assoc]
    · simp
  · simp only [Bool.not_eq_true] at hp
    simp [hp]

theorem subDc_comp_list {isPi : Var → Bool} {σ : Var → List Dep} {k : Kind} (hk : k.isName = false)
    (ds : List Dep) :
    (ds.map fun d => (⟨d.root, A2.comp d.kind k⟩ : Dep)).flatMap (A2.subDc isPi σ) =
      (ds.flatMap (A2.subDc isPi σ)).map fun e => ⟨e.root, A2.comp e.kind k⟩ := by
  induction ds with
  | nil => rfl
  | cons d ds ih => simp only [List.map_cons, List.flatMap_cons, List.map_append, subDc_comp hk, ih]

/-- **Deriving a borrow commutes with the substitution**: from a borrowed
    entry, by a kind that is not a name, the substituted dependencies of the
    borrow are the borrow of the substituted entry. (From a root, the
    borrow's one dependency is on the root, which is no region.) -/
theorem subDc_derive {isPi : Var → Bool} {σ : Var → List Dep} {y : Var} {E : Entry} {k : Kind}
    (hk : k.isName = false) (hroot : E.mode.isRoot = true → isPi y = false) :
    (derive y E k).flatMap (A2.subDc isPi σ) = derive y { E with path := E.path.flatMap (A2.subDc isPi σ) } k := by
  unfold derive
  by_cases hr : E.mode.isRoot = true
  · simp only [hr, ↓reduceIte, List.flatMap_cons, List.flatMap_nil, List.append_nil]
    exact subDc_noPi (hroot hr)
  · simp only [Bool.not_eq_true] at hr
    simp only [hr, Bool.false_eq_true, ↓reduceIte]
    exact subDc_comp_list hk E.path

/-! ### A change inside a region's node keeps the node

A change through a borrow rewrites one node of its owner's tree (`Repl`).
Where that node lies strictly inside a node of a region (an element's
inside, AGORA-933's grow of `w[0]`), the region's node keeps its address and
its number of elements. So a view of its buffer, `view d o l` with
`o + l ≤ es.length`, still fits: the caller's argument stays valid while the
body changes the memory its views point into. -/

/-- **A rewrite strictly inside a node keeps the node's address and length.**
    The node `t c d es` lies in the old tree and the hole strictly inside
    it; then the new tree holds `t c d es'`, `es'` as long as `es`. -/
theorem Repl.keeps_enclosing {n n' T T' : Val} (hr : Repl n n' T T') {t : Ty} {c d : Nat} {es : List Val}
    (hs : Sub (.node t c d es) T) (hb : Below n (.node t c d es)) :
    ∃ es', Sub (.node t c d es') T' ∧ es'.length = es.length := by
  induction hr with
  | here =>
    exact (Below.not_self (Below.of_sub_below hs hb)).elim
  | @elem t1 c1 d1 pre post e e' hr' ih =>
    cases hs with
    | refl =>
      exact ⟨pre ++ e' :: post, Sub.refl _, by simp⟩
    | child hx hsx =>
      rcases List.mem_append.mp hx with hx | hx
      · exact ⟨es, Sub.child (List.mem_append_left _ hx) hsx, rfl⟩
      · rcases List.mem_cons.mp hx with rfl | hx
        · obtain ⟨es', hs', hl⟩ := ih hsx
          exact ⟨es', Sub.child (List.mem_append_right _ (List.mem_cons_self ..)) hs', hl⟩
        · exact ⟨es, Sub.child (List.mem_append_right _ (List.mem_cons_of_mem _ hx)) hsx, rfl⟩
  | fst hr' ih =>
    cases hs with
    | fst hs' => obtain ⟨es', h, hl⟩ := ih hs'; exact ⟨es', Sub.fst h, hl⟩
    | snd hs' => exact ⟨es, Sub.snd hs', rfl⟩
  | snd hr' ih =>
    cases hs with
    | fst hs' => exact ⟨es, Sub.fst hs', rfl⟩
    | snd hs' => obtain ⟨es', h, hl⟩ := ih hs'; exact ⟨es', Sub.snd h, hl⟩
  | inl hr' ih =>
    cases hs with
    | inl hs' => obtain ⟨es', h, hl⟩ := ih hs'; exact ⟨es', Sub.inl h, hl⟩
  | inr hr' ih =>
    cases hs with
    | inr hs' => obtain ⟨es', h, hl⟩ := ih hs'; exact ⟨es', Sub.inr h, hl⟩
  | pkg hr' ih =>
    cases hs with
    | pkg hs' => obtain ⟨es', h, hl⟩ := ih hs'; exact ⟨es', Sub.pkg h, hl⟩

/-- ... so in memory: the owner's slot given the rewritten tree, the node at
    the region's address `d` is still there, as long as before (in the
    owner's new tree, whatever the old slot held). -/
theorem DataAt.keeps_enclosing {m : Mem} {o : Var} {T T' n n' : Val} (hr : Repl n n' T T') {t : Ty} {c d : Nat} {es : List Val}
    (hs : Sub (.node t c d es) T) (hb : Below n (.node t c d es)) :
    ∃ es', DataAt (m.set o ⟨true, some T'⟩) d (.node t c d es') ∧ es'.length = es.length := by
  obtain ⟨es', hs', hl⟩ := hr.keeps_enclosing hs hb
  refine ⟨es', Or.inl ⟨o, T', ?_, hs', t, c, es', rfl⟩, hl⟩
  simp [Mem.set, upd]

/-- **A view of a region's buffer stays in bounds** through a change strictly
    inside the node: the length it was checked against is the new node's. -/
theorem RegionViewAt.keeps_len {m : Mem} {o : Var} {T T' n n' : Val} (hr : Repl n n' T T') {t : Ty} {c d o' l : Nat} {es : List Val}
    (hs : Sub (.node t c d es) T) (hb : Below n (.node t c d es)) (hle : o' + l ≤ es.length) :
    ∃ es', DataAt (m.set o ⟨true, some T'⟩) d (.node t c d es') ∧ o' + l ≤ es'.length := by
  obtain ⟨es', hd, hl⟩ := DataAt.keeps_enclosing (m := m) (o := o) hr hs hb
  exact ⟨es', hd, hl ▸ hle⟩

/-- ... and the enclosing node is either unchanged or the hole rewritten in
    it, so it keeps whatever the rewrite keeps (`DSH_repl_wf`). -/
theorem Repl.keeps_enclosing' {n n' T T' : Val} (hr : Repl n n' T T') {t : Ty} {c d : Nat} {es : List Val}
    (hs : Sub (.node t c d es) T) (hb : Below n (.node t c d es)) :
    ∃ es', Sub (.node t c d es') T' ∧ es'.length = es.length ∧
      (es' = es ∨ Repl n n' (.node t c d es) (.node t c d es')) := by
  induction hr with
  | here =>
    exact (Below.not_self (Below.of_sub_below hs hb)).elim
  | @elem t1 c1 d1 pre post e e' hr' ih =>
    cases hs with
    | refl =>
      exact ⟨pre ++ e' :: post, Sub.refl _, by simp, Or.inr (Repl.elem hr')⟩
    | child hx hsx =>
      rcases List.mem_append.mp hx with hx | hx
      · exact ⟨es, Sub.child (List.mem_append_left _ hx) hsx, rfl, Or.inl rfl⟩
      · rcases List.mem_cons.mp hx with rfl | hx
        · obtain ⟨es', hs', hl, he⟩ := ih hsx
          exact ⟨es', Sub.child (List.mem_append_right _ (List.mem_cons_self ..)) hs', hl, he⟩
        · exact ⟨es, Sub.child (List.mem_append_right _ (List.mem_cons_of_mem _ hx)) hsx, rfl, Or.inl rfl⟩
  | fst hr' ih =>
    cases hs with
    | fst hs' => obtain ⟨es', h, hl, he⟩ := ih hs'; exact ⟨es', Sub.fst h, hl, he⟩
    | snd hs' => exact ⟨es, Sub.snd hs', rfl, Or.inl rfl⟩
  | snd hr' ih =>
    cases hs with
    | fst hs' => exact ⟨es, Sub.fst hs', rfl, Or.inl rfl⟩
    | snd hs' => obtain ⟨es', h, hl, he⟩ := ih hs'; exact ⟨es', Sub.snd h, hl, he⟩
  | inl hr' ih =>
    cases hs with
    | inl hs' => obtain ⟨es', h, hl, he⟩ := ih hs'; exact ⟨es', Sub.inl h, hl, he⟩
  | inr hr' ih =>
    cases hs with
    | inr hs' => obtain ⟨es', h, hl, he⟩ := ih hs'; exact ⟨es', Sub.inr h, hl, he⟩
  | pkg hr' ih =>
    cases hs with
    | pkg hs' => obtain ⟨es', h, hl, he⟩ := ih hs'; exact ⟨es', Sub.pkg h, hl, he⟩

/-- **An argument's view of a region's buffer survives a change strictly
    inside the region's node.** The change rewrites owner `o`'s tree, and the
    replacement is well-formed wherever the hole was. If the region's node
    lies in `o`'s tree, the hole must be strictly inside it. Otherwise the
    node lies in another slot or a payload, which the change leaves alone.
    Either way, the view is still valid through its region in the new memory,
    with the same bounds and a well-formed node. -/
theorem RegionViewAt.keep_inner {m : Mem} {o : Var} {T T' n n' : Val} (hT : m.st o = some ⟨true, some T⟩)
    (hr : Repl n n' T T') (hn : ∀ σ, WFv σ n → WFv σ n')
    {D : Nat → Prop} {d o' l : Nat} {t : Ty} (hv : RegionViewAt m D .view d o' l t)
    (hb : ∀ c es, Sub (.node t c d es) T → Below n (.node t c d es)) :
    RegionViewAt (m.set o ⟨true, some T'⟩) D .view d o' l t := by
  obtain ⟨c, es, hk, ⟨n0, ⟨d0, hD, hn0⟩, hl⟩, hle, hw⟩ := hv
  rcases hl with ⟨h1, -⟩ | ⟨-, rfl⟩ | ⟨h1, -⟩ | ⟨_, h1, -⟩
  · cases h1
  · -- the region's node is the view's node, at the address `d0`
    have hd0 : d0 = d := by
      obtain ⟨_, _, _, h⟩ := hn0.eq; cases h; rfl
    subst hd0
    rcases hn0 with ⟨x, Tx, hx, hsx, -⟩ | ⟨k, bl, hk', hsk, -⟩
    · by_cases hxo : x = o
      · subst hxo
        rw [hT] at hx; cases hx
        obtain ⟨es', hs', hl', he⟩ := hr.keeps_enclosing' hsx (hb c es hsx)
        have hw' : WFv (.vec t) (.node t c d0 es') := by
          rcases he with rfl | hr0
          · exact hw
          · exact DSH_repl_wf hn hr0 hw
        refine ⟨c, es', hk, ⟨_, ⟨d0, hD, Or.inl ⟨x, T', by simp [Mem.set, upd], hs', t, c, es', rfl⟩⟩,
          Or.inr (Or.inl ⟨rfl, rfl⟩)⟩, hl' ▸ hle, hw'⟩
      · refine ⟨c, es, hk, ⟨_, ⟨d0, hD, Or.inl ⟨x, Tx, ?_, hsx, t, c, es, rfl⟩⟩,
          Or.inr (Or.inl ⟨rfl, rfl⟩)⟩, hle, hw⟩
        simp [Mem.set, upd, hxo, hx]
    · exact ⟨c, es, hk, ⟨_, ⟨d0, hD, Or.inr ⟨k, bl, hk', hsk, t, c, es, rfl⟩⟩,
        Or.inr (Or.inl ⟨rfl, rfl⟩)⟩, hle, hw⟩
  · cases h1
  · cases h1

end A2
