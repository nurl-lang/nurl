import A2.ThruPre

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
  through its substitution.

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
  obtain ⟨d', o', l', heq, dep, -, hva⟩ := h s _ hv
  cases heq
  obtain ⟨c, es, hd, hle, hw⟩ := hva.dataAt
  exact ⟨c, es, by decide, ⟨_, ⟨d, ⟨s, o, l, hv⟩, hd⟩, Or.inr (Or.inl ⟨rfl, rfl⟩)⟩, hle, hw⟩

/-- ... and each address of the region reaches a node. -/
theorem ViewsOK.region_node {m : Mem} {τ : Ty} {T : Val} {H : List Dep} (h : ViewsOK m τ T H)
    {d : Nat} (hd : ViewAddr τ T d) : ∃ n, RegionNode m (ViewAddr τ T) n ∧ ∃ ty c es, n = .node ty c d es := by
  obtain ⟨s, o, l, hv⟩ := hd
  obtain ⟨c, es, -, ⟨n0, ⟨d0, hD, hn⟩, hl⟩, -, -⟩ := h.region_viewAt hv
  rcases hl with ⟨h1, -⟩ | ⟨-, rfl⟩ | ⟨h1, -⟩
  · cases h1
  · exact ⟨_, ⟨d0, hD, hn⟩, s, c, es, rfl⟩
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
    the node at an address unique). -/
theorem ViewsOK.region_landed {m : Mem} (hh : HeapOK m) {τ : Ty} {T : Val} {H : List Dep}
    (h : ViewsOK m τ T H) : ∀ d n0, ViewAddr τ T d → DataAt m d n0 → ∃ dep ∈ H, Landed m dep n0 := by
  intro d n0 hd hn0
  obtain ⟨s, o, l, hv⟩ := hd
  obtain ⟨d', o', l', heq, dep, hdep, hva⟩ := h s _ hv
  cases heq
  obtain ⟨c, es, -, hL, -, -⟩ := hva
  have := RegionNode.unique hh hn0 (hL.inMem.dataAt rfl)
  subst this
  exact ⟨dep, hdep, hL⟩

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

end A2
