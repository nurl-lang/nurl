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
  (`RegionLanded.comp`).

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

end A2
