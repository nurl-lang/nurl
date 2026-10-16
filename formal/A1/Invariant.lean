import A1.Typing

/-
  A1 — what a well-typed configuration guarantees about memory.

  * Every owned tree is well-formed at its binding's type, its addresses are
    allocated, appear once in it and in no other owner's tree (one owner per
    allocation).
  * Every live borrow reaches, through one of its dependencies, a node of
    its type inside memory that dependency's root holds; every live view
    lies inside the buffer it names.  The views stored inside a value are
    valid through what it holds (`held`).
  * A borrowed parameter's dependencies are frozen at the point of
    execution, so nothing that runs can change what it reaches.
-/

namespace A1

/-- An owned tree of the given type: integers, views and owned element
    `Vec`s, never a bare borrow. -/
inductive WFv : Ty → Val → Prop
  | int {n : Nat} : WFv .int (.int n)
  | view {t : Ty} {d o l : Nat} : WFv (.slice t) (.view d o l)
  | node {t : Ty} {c d : Nat} {es : List Val} :
      (∀ e ∈ es, WFv t e) → WFv (.vec t) (.node t c d es)

/-- `v`, a view of element type `s`, is stored in tree `T` of type `τ`. -/
inductive ViewIn : Ty → Val → Ty → Val → Prop
  | here {s : Ty} {d o l : Nat} : ViewIn (.slice s) (.view d o l) s (.view d o l)
  | child {t t' : Ty} {c d : Nat} {es : List Val} {e : Val} {s : Ty} {v : Val} :
      e ∈ es → ViewIn t e s v → ViewIn (.vec t) (.node t' c d es) s v

/-- `n` lies strictly inside `t`. -/
def Below (n t : Val) : Prop :=
  ∃ ty c d es e, t = .node ty c d es ∧ e ∈ es ∧ Sub n e

/-- The node a root's slot reaches: its own tree, or what its borrow names. -/
def RootNode (m : Mem) (r : Var) (n : Val) : Prop :=
  m.st r = some ⟨true, some n⟩ ∨
  (∃ c, m.st r = some ⟨false, some (.href c)⟩ ∧ NodeAt m c n) ∨
  (∃ d o l, m.st r = some ⟨false, some (.view d o l)⟩ ∧ DataAt m d n)

/-- The view `(d, o, l)` of element type `t` is valid through `dep`. -/
def ViewAt (m : Mem) (dep : Dep) (d o l : Nat) (t : Ty) : Prop :=
  ∃ n0 c es, RootNode m dep.root n0 ∧
    (dep.kind = .view ∧ Val.node t c d es = n0 ∨ dep.kind = .inner ∧ Below (.node t c d es) n0) ∧
    o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es)

/-- Every view stored in `T` is valid through some dependency in `H`. -/
def ViewsOK (m : Mem) (τ : Ty) (T : Val) (H : List Dep) : Prop :=
  ∀ s v, ViewIn τ T s v → ∃ d o l, v = .view d o l ∧ ∃ dep ∈ H, ViewAt m dep d o l s

/-- The borrowed `Vec` `c` of element type `t` is valid through `dep`. -/
def HrefAt (m : Mem) (dep : Dep) (c : Nat) (t : Ty) (H : List Dep) : Prop :=
  ∃ n0 d es, RootNode m dep.root n0 ∧
    (dep.kind = .self ∧ Val.node t c d es = n0 ∨ dep.kind = .inner ∧ Below (.node t c d es) n0) ∧
    WFv (.vec t) (.node t c d es) ∧ ViewsOK m (.vec t) (.node t c d es) H

/-- A borrowed value of type `τ`, depending on `P` and holding `H`. -/
def ValOK (m : Mem) : Ty → Val → List Dep → List Dep → Prop
  | .int, v, _, _ => ∃ n, v = .int n
  | .vec t, v, P, H => ∃ c, v = .href c ∧ ∃ dep ∈ P, HrefAt m dep c t H
  | .slice t, v, P, _ => ∃ d o l, v = .view d o l ∧ ∃ dep ∈ P, ViewAt m dep d o l t

mutual
def Val.ids : Val → List Nat
  | .node _ c d es => c :: d :: idsL es
  | _ => []
def idsL : List Val → List Nat
  | [] => []
  | e :: es => e.ids ++ idsL es
end

def OwnedAt (m : Mem) (x : Var) (t : Val) : Prop := m.st x = some ⟨true, some t⟩

/-- One owner per allocation, and every owned address is live. -/
structure HeapOK (m : Mem) : Prop where
  nodup : ∀ x t, OwnedAt m x t → t.ids.Nodup
  disj  : ∀ x y t u, x ≠ y → OwnedAt m x t → OwnedAt m y u → ∀ i ∈ t.ids, i ∉ u.ids
  alloc : ∀ x t, OwnedAt m x t → ∀ i ∈ t.ids, m.alloc i = true ∧ i < m.nid

/-- A binding's slot agrees with its entry. -/
def SlotOK (m : Mem) (E : Entry) (sl : Slot) : Prop :=
  sl.own = E.mode.ownSlot ∧
  (E.mode.ownSlot = true →
    (∃ t, E.ty = .vec t) ∧ (∀ T, sl.val = some T → WFv E.ty T) ∧
    (E.live = true → ∃ T, sl.val = some T ∧ ViewsOK m E.ty T E.held)) ∧
  (E.mode.ownSlot = false →
    (E.live = true → ∃ v, sl.val = some v ∧ ValOK m E.ty v E.path E.held))

/-- The bindings of the run-time scopes a statement is inside of, innermost
    last: they are bound for as long as the statement runs. -/
def Stmt.spine : Stmt → List Var
  | .seq a _ => a.spine
  | .scope x s => x :: s.spine
  | .rbind p s => p :: s.spine
  | .frozen _ s => s.spine
  | _ => []

/-- The invariant of a configuration running `s` in context `Γ`, with `F`
    lent out. -/
structure Inv (m : Mem) (Γ : Ctx) (F : List Var) (s : Stmt) : Prop where
  dom       : ∀ v, (Γ v).isSome = (m.st v).isSome
  slot      : ∀ v E, Γ v = some E → ∃ sl, m.st v = some sl ∧ E.ty.ok = true ∧ SlotOK m E sl
  heap      : HeapOK m
  nvSt      : ∀ v, (m.st v).isSome → v < m.nv
  nvS       : ∀ v ∈ s.vars, v < m.nv
  nvF       : ∀ v ∈ F, v < m.nv
  noInout   : ∀ v E b, Γ v = some E → E.mode ≠ .inout b
  wf        : CtxWF Γ
  rootbLive : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true
  rootbLt   : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r < p
  anch      : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ r ∈ roots E.vdeps, r ∈ F

end A1
