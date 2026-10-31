import A2.Typing

/-
  A2 — what a well-typed configuration guarantees about memory.

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

namespace A2

/-- An owned tree of the given type: integers, views and owned element
    `Vec`s, never a bare borrow. -/
inductive WFv : Ty → Val → Prop
  | int {n : Nat} : WFv .int (.int n)
  | view {t : Ty} {d o l : Nat} : WFv (.slice t) (.view d o l)
  | node {t : Ty} {c d : Nat} {es : List Val} :
      (∀ e ∈ es, WFv t e) → WFv (.vec t) (.node t c d es)
  | pair {a b : Ty} {v w : Val} : WFv a v → WFv b w → WFv (.prod a b) (.pair v w)
  | inl {a b : Ty} {v : Val} : WFv a v → WFv (.sum a b) (.inl v)
  | inr {a b : Ty} {v : Val} : WFv b v → WFv (.sum a b) (.inr v)
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {v : Val} {cs : List (Var × PMode × Ty)} :
      WFv te v → WFv (.fn ms) (.pkg fs te ms v cs)
  /-- A3.1: a share; its block, in memory, holds the payload it carries (in
      the first cut, one that holds no view). -/
  | arc {t : Ty} {k : Nat} {p : Val} : WFv t p → t.holdsView = false → WFv (.arc t) (.arc k p)

/-- `v`, a view of element type `s`, is stored in tree `T` of type `τ`. -/
inductive ViewIn : Ty → Val → Ty → Val → Prop
  | here {s : Ty} {d o l : Nat} : ViewIn (.slice s) (.view d o l) s (.view d o l)
  | child {t t' : Ty} {c d : Nat} {es : List Val} {e : Val} {s : Ty} {v : Val} :
      e ∈ es → ViewIn t e s v → ViewIn (.vec t) (.node t' c d es) s v
  | fst {a b : Ty} {x y : Val} {s : Ty} {v : Val} : ViewIn a x s v → ViewIn (.prod a b) (.pair x y) s v
  | snd {a b : Ty} {x y : Val} {s : Ty} {v : Val} : ViewIn b y s v → ViewIn (.prod a b) (.pair x y) s v
  | inl {a b : Ty} {x : Val} {s : Ty} {v : Val} : ViewIn a x s v → ViewIn (.sum a b) (.inl x) s v
  | inr {a b : Ty} {x : Val} {s : Ty} {v : Val} : ViewIn b x s v → ViewIn (.sum a b) (.inr x) s v
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {x : Val} {cs : List (Var × PMode × Ty)} {s : Ty}
      {v : Val} : ViewIn te x s v → ViewIn (.fn ms) (.pkg fs te ms x cs) s v

/-- A3.1: tree `T` of type `τ` holds a share of block `k`, whose payload is
    the `u` it carries, `p`. (Not inside a payload: the block's own shares
    are the block's.) -/
inductive ArcIn : Ty → Val → Ty → Nat → Val → Prop
  | here {u : Ty} {k : Nat} {p : Val} : ArcIn (.arc u) (.arc k p) u k p
  | child {t t' : Ty} {c d : Nat} {es : List Val} {e : Val} {u : Ty} {k : Nat} {p : Val} :
      e ∈ es → ArcIn t e u k p → ArcIn (.vec t) (.node t' c d es) u k p
  | fst {a b : Ty} {x y : Val} {u : Ty} {k : Nat} {p : Val} :
      ArcIn a x u k p → ArcIn (.prod a b) (.pair x y) u k p
  | snd {a b : Ty} {x y : Val} {u : Ty} {k : Nat} {p : Val} :
      ArcIn b y u k p → ArcIn (.prod a b) (.pair x y) u k p
  | inl {a b : Ty} {x : Val} {u : Ty} {k : Nat} {p : Val} : ArcIn a x u k p → ArcIn (.sum a b) (.inl x) u k p
  | inr {a b : Ty} {x : Val} {u : Ty} {k : Nat} {p : Val} : ArcIn b x u k p → ArcIn (.sum a b) (.inr x) u k p
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {x : Val} {cs : List (Var × PMode × Ty)} {u : Ty}
      {k : Nat} {p : Val} : ArcIn te x u k p → ArcIn (.fn ms) (.pkg fs te ms x cs) u k p

/-- A3.1: every share a tree holds names a block of the store `B` that
    holds the payload the share carries, of the share's type (the block
    lives while a share of it is owned; a payload never changes). -/
def SharesIn (B : Nat → Option Blk) (τ : Ty) (T : Val) : Prop :=
  ∀ u k p, ArcIn τ T u k p → B k = some ⟨u, p⟩

/-- `SharesIn` over a memory's blocks. -/
def SharesOK (m : Mem) (τ : Ty) (T : Val) : Prop := SharesIn m.blk τ T

/-- A3.1: every block of the store `B` holds a well-formed tree of a type
    that holds no views, and the shares it holds name blocks of `B` too. -/
def BlocksOK (B : Nat → Option Blk) : Prop :=
  ∀ k bl, B k = some bl → bl.ty.ok = true ∧ bl.ty.holdsView = false ∧ WFv bl.ty bl.pay ∧
    SharesIn B bl.ty bl.pay

theorem SharesOK.of_blk {m m' : Mem} {τ : Ty} {T : Val} (h : SharesOK m τ T) (hb : m'.blk = m.blk) :
    SharesOK m' τ T := fun u k p ha => by rw [hb]; exact h u k p ha

theorem SharesOK.fst {m : Mem} {a b : Ty} {x y : Val} (h : SharesOK m (.prod a b) (.pair x y)) :
    SharesOK m a x := fun u k p ha => h u k p (.fst ha)
theorem SharesOK.snd {m : Mem} {a b : Ty} {x y : Val} (h : SharesOK m (.prod a b) (.pair x y)) :
    SharesOK m b y := fun u k p ha => h u k p (.snd ha)
theorem SharesOK.inl {m : Mem} {a b : Ty} {x : Val} (h : SharesOK m (.sum a b) (.inl x)) :
    SharesOK m a x := fun u k p ha => h u k p (.inl ha)
theorem SharesOK.inr {m : Mem} {a b : Ty} {x : Val} (h : SharesOK m (.sum a b) (.inr x)) :
    SharesOK m b x := fun u k p ha => h u k p (.inr ha)
theorem SharesOK.elem {m : Mem} {t t' : Ty} {c d : Nat} {es : List Val} {e : Val}
    (h : SharesOK m (.vec t) (.node t' c d es)) (he : e ∈ es) : SharesOK m t e :=
  fun u k p ha => h u k p (.child he ha)
theorem SharesOK.pkg {m : Mem} {fs : List Nat} {te : Ty} {ms : List Nat} {x : Val}
    {cs : List (Var × PMode × Ty)} (h : SharesOK m (.fn ms) (.pkg fs te ms x cs)) : SharesOK m te x :=
  fun u k p ha => h u k p (.pkg ha)
theorem SharesOK.here {m : Mem} {t : Ty} {k : Nat} {p : Val} (h : SharesOK m (.arc t) (.arc k p)) :
    m.blk k = some ⟨t, p⟩ := h t k p .here

theorem ArcIn.hasArc {τ : Ty} {T : Val} {u : Ty} {k : Nat} {p : Val} (h : ArcIn τ T u k p) :
    τ.hasArc = true := by
  induction h with
  | here => rfl
  | child _ _ ih => exact ih
  | fst _ ih => simp [Ty.hasArc, ih]
  | snd _ ih => simp [Ty.hasArc, ih]
  | inl _ ih => simp [Ty.hasArc, ih]
  | inr _ ih => simp [Ty.hasArc, ih]
  | pkg _ _ => rfl

/-- A node whose elements are among another's, where the blocks are as
    they were (a `Vec` that shrank, or that was copied). -/
theorem SharesOK.node_sub {m m' : Mem} {t t1 t2 : Ty} {c d c' d' : Nat} {es es' : List Val}
    (h : SharesOK m (.vec t) (.node t1 c d es)) (hsub : ∀ e ∈ es', e ∈ es) (hb : m'.blk = m.blk) :
    SharesOK m' (.vec t) (.node t2 c' d' es') := fun u k p ha => by
  cases ha with
  | child he ha' => rw [hb]; exact h u k p (.child (hsub _ he) ha')

/-- ... and a `Vec` with one element more (`vec_push`). -/
theorem SharesOK.node_push {m m' : Mem} {t t1 t2 : Ty} {c d c' d' : Nat} {es : List Val} {v : Val}
    (h : SharesOK m (.vec t) (.node t1 c d es)) (hv : SharesOK m t v) (hb : m'.blk = m.blk) :
    SharesOK m' (.vec t) (.node t2 c' d' (es ++ [v])) := fun u k p ha => by
  cases ha with
  | child he ha' =>
    rw [hb]
    rcases List.mem_append.mp he with he | he
    · exact h u k p (.child he ha')
    · rw [List.mem_singleton] at he; subst he; exact hv u k p ha'

theorem SharesOK.mk_pair {m : Mem} {a b : Ty} {x y : Val} (hx : SharesOK m a x) (hy : SharesOK m b y) :
    SharesOK m (.prod a b) (.pair x y) := fun u k p ha => by
  cases ha with
  | fst h => exact hx u k p h
  | snd h => exact hy u k p h
theorem SharesOK.mk_inl {m : Mem} {a b : Ty} {x : Val} (hx : SharesOK m a x) :
    SharesOK m (.sum a b) (.inl x) := fun u k p ha => by cases ha with | inl h => exact hx u k p h
theorem SharesOK.mk_inr {m : Mem} {a b : Ty} {x : Val} (hx : SharesOK m b x) :
    SharesOK m (.sum a b) (.inr x) := fun u k p ha => by cases ha with | inr h => exact hx u k p h
theorem SharesOK.mk_pkg {m : Mem} {fs : List Nat} {te : Ty} {ms : List Nat} {x : Val}
    {cs : List (Var × PMode × Ty)} (hx : SharesOK m te x) : SharesOK m (.fn ms) (.pkg fs te ms x cs) :=
  fun u k p ha => by cases ha with | pkg h => exact hx u k p h
theorem SharesOK.nil_node {m : Mem} {t t1 : Ty} {c d : Nat} : SharesOK m (.vec t) (.node t1 c d []) :=
  fun u k p ha => by cases ha with | child he _ => cases he

/-- A tree of a type that holds no share holds none to check. -/
theorem SharesOK.of_noArc {m : Mem} {τ : Ty} {T : Val} (h : τ.hasArc = false) : SharesOK m τ T :=
  fun _ _ _ ha => by rw [ha.hasArc] at h; cases h

/-- `e` is a part of `t` one level down: an element of a `Vec`, or a field
    of a struct. -/
inductive Child : Val → Val → Prop
  | elem {e : Val} {ty : Ty} {c d : Nat} {es : List Val} : e ∈ es → Child e (.node ty c d es)
  | fst {v w : Val} : Child v (.pair v w)
  | snd {v w : Val} : Child w (.pair v w)
  | inl {v : Val} : Child v (.inl v)
  | inr {v : Val} : Child v (.inr v)
  | pkg {v : Val} {fs : List Nat} {te : Ty} {ms : List Nat} {cs : List (Var × PMode × Ty)} :
      Child v (.pkg fs te ms v cs)

/-- `n` lies strictly inside `t`. -/
def Below (n t : Val) : Prop := ∃ e, Child e t ∧ Sub n e

/-- `n` is `v` or one of its parts through struct fields and enum payloads
    (never through a `Vec`'s elements): what a binding holds directly. -/
inductive Top : Val → Val → Prop
  | refl (v : Val) : Top v v
  | fst {n a b : Val} : Top n a → Top n (.pair a b)
  | snd {n a b : Val} : Top n b → Top n (.pair a b)
  | inl {n a : Val} : Top n a → Top n (.inl a)
  | inr {n a : Val} : Top n a → Top n (.inr a)
  | pkg {n a : Val} {fs : List Nat} {te : Ty} {ms : List Nat} {cs : List (Var × PMode × Ty)} :
      Top n a → Top n (.pkg fs te ms a cs)

/-- A node a root's slot reaches directly: one at the top of its own tree, or
    one a handle it holds names (a borrowed struct is a bundle of handles). -/
def RootNode (m : Mem) (r : Var) (n : Val) : Prop :=
  (∃ T, m.st r = some ⟨true, some T⟩ ∧ Top n T) ∨
  (∃ v c, m.st r = some ⟨false, some v⟩ ∧ Top (.href c) v ∧ NodeAt m c n) ∨
  (∃ v d o l, m.st r = some ⟨false, some v⟩ ∧ Top (.view d o l) v ∧ DataAt m d n)

/-- The view `(d, o, l)` of element type `t` is valid through `dep`. -/
def ViewAt (m : Mem) (dep : Dep) (d o l : Nat) (t : Ty) : Prop :=
  ∃ n0 c es, RootNode m dep.root n0 ∧
    (dep.kind = .view ∧ Val.node t c d es = n0 ∨ dep.kind = .inner ∧ Below (.node t c d es) n0) ∧
    o + l ≤ es.length ∧ WFv (.vec t) (.node t c d es)

/-- Every view stored in `T` is valid through some dependency in `H`. -/
def ViewsOK (m : Mem) (τ : Ty) (T : Val) (H : List Dep) : Prop :=
  ∀ s v, ViewIn τ T s v → ∃ d o l, v = .view d o l ∧ ∃ dep ∈ H, ViewAt m dep d o l s

/-- Where a value reached through a dependency of a given kind lies: the
    root's node itself, or strictly inside it. -/
def Lands (k : Kind) (n n0 : Val) : Prop :=
  k = .self ∧ n = n0 ∨ k = .view ∧ n = n0 ∨ k = .inner ∧ Below n n0 ∨
  -- A3.1: a payload borrow: in a payload a share in the root's node reaches
  k = .share ∧ ThruS n n0

/-- What a value captured by name (the closures in it) is held, by name,
    in `H`. -/
def NamesIn (T : Val) (H : List Dep) : Prop :=
  ∀ c ∈ T.names, (⟨c.1, .name c.2.1.bound c.2.2⟩ : Dep) ∈ H

/-- A closure's captures by name are distinct, each read or changed, and
    one captured again inside its environment is only read, by both. -/
def PkgsOK (T : Val) : Prop :=
  ∀ fs te ms e cs, Sub (.pkg fs te ms e cs) T →
    (cs.map (·.1)).Nodup ∧ (∀ c ∈ cs, c.2.1 = .inp ∨ ∃ b, c.2.1 = .inout b ∧ b ≠ .none) ∧
    (∀ c ∈ cs, ∀ c' ∈ e.names, c.1 = c'.1 → c.2.1 = .inp ∧ c'.2.1 = .inp)

/-- The borrowed `Vec` `c` of element type `t` is valid through `dep`. -/
def HrefAt (m : Mem) (dep : Dep) (c : Nat) (t : Ty) (H : List Dep) : Prop :=
  ∃ n0 d es, RootNode m dep.root n0 ∧ Lands dep.kind (.node t c d es) n0 ∧
    WFv (.vec t) (.node t c d es) ∧ ViewsOK m (.vec t) (.node t c d es) H ∧
    NamesIn (.node t c d es) H ∧ SharesOK m (.vec t) (.node t c d es)

/-- A borrowed value of type `τ`, depending on `P` and holding `H`.  The parts
    of a borrowed struct are valid through what it depends on or holds. -/
inductive ValOK (m : Mem) : Ty → Val → List Dep → List Dep → Prop
  | int {n : Nat} {P H : List Dep} : ValOK m .int (.int n) P H
  | href {t : Ty} {c : Nat} {P H : List Dep} :
      (∃ dep ∈ P, HrefAt m dep c t H) → ValOK m (.vec t) (.href c) P H
  | view {t : Ty} {d o l : Nat} {P H : List Dep} :
      (∃ dep ∈ P, ViewAt m dep d o l t) → ValOK m (.slice t) (.view d o l) P H
  | pair {a b : Ty} {x y : Val} {P H : List Dep} :
      ValOK m a x (P ++ H) H → ValOK m b y (P ++ H) H → ValOK m (.prod a b) (.pair x y) P H
  | inl {a b : Ty} {x : Val} {P H : List Dep} : ValOK m a x (P ++ H) H → ValOK m (.sum a b) (.inl x) P H
  | inr {a b : Ty} {x : Val} {P H : List Dep} : ValOK m b x (P ++ H) H → ValOK m (.sum a b) (.inr x) P H
  -- a package's environment is valid through what the package depends on and
  -- holds but its own writer captures, which are no part of it (they are its
  -- arguments of their own when it is called); a closure it holds that may
  -- change some other binding by name is part of it
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {x : Val} {cs : List (Var × PMode × Ty)}
      {P H : List Dep} :
      ValOK m te x (P ++ envDeps cs H) (envDeps cs H) → ValOK m (.fn ms) (.pkg fs te ms x cs) P H
  /-- A3.1: a share lent: its block holds the payload it carries, of its
      type (in the first cut, one that holds no view). -/
  | arc {t : Ty} {k : Nat} {p : Val} {P H : List Dep} :
      m.blk k = some ⟨t, p⟩ → WFv t p → t.holdsView = false → ValOK m (.arc t) (.arc k p) P H

section ValOK
variable {m : Mem} {v : Val} {P H : List Dep}

theorem valOK_int : ValOK m .int v P H ↔ ∃ n, v = .int n := by
  constructor
  · intro h; cases h; exact ⟨_, rfl⟩
  · rintro ⟨n, rfl⟩; exact .int

theorem valOK_vec {t : Ty} : ValOK m (.vec t) v P H ↔ ∃ c, v = .href c ∧ ∃ dep ∈ P, HrefAt m dep c t H := by
  constructor
  · intro h; cases h with | href h => exact ⟨_, rfl, h⟩
  · rintro ⟨c, rfl, h⟩; exact .href h

theorem valOK_slice {t : Ty} :
    ValOK m (.slice t) v P H ↔ ∃ d o l, v = .view d o l ∧ ∃ dep ∈ P, ViewAt m dep d o l t := by
  constructor
  · intro h; cases h with | view h => exact ⟨_, _, _, rfl, h⟩
  · rintro ⟨d, o, l, rfl, h⟩; exact .view h

theorem valOK_prod {a b : Ty} :
    ValOK m (.prod a b) v P H ↔ ∃ x y, v = .pair x y ∧ ValOK m a x (P ++ H) H ∧ ValOK m b y (P ++ H) H := by
  constructor
  · intro h; cases h with | pair hx hy => exact ⟨_, _, rfl, hx, hy⟩
  · rintro ⟨x, y, rfl, hx, hy⟩; exact .pair hx hy

theorem valOK_sum {a b : Ty} :
    ValOK m (.sum a b) v P H ↔
      (∃ x, v = .inl x ∧ ValOK m a x (P ++ H) H) ∨ (∃ x, v = .inr x ∧ ValOK m b x (P ++ H) H) := by
  constructor
  · intro h
    cases h with
    | inl hx => exact Or.inl ⟨_, rfl, hx⟩
    | inr hx => exact Or.inr ⟨_, rfl, hx⟩
  · rintro (⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩)
    · exact .inl hx
    · exact .inr hx

theorem valOK_fn {ms : List Nat} :
    ValOK m (.fn ms) v P H ↔
      ∃ fs te x cs, v = .pkg fs te ms x cs ∧ ValOK m te x (P ++ envDeps cs H) (envDeps cs H) := by
  constructor
  · intro h; cases h with | pkg hx => exact ⟨_, _, _, _, rfl, hx⟩
  · rintro ⟨f, te, x, cs, rfl, hx⟩; exact .pkg hx

/-- An integer depends on nothing. -/
theorem ValOK.int_any {m' : Mem} {P' H' : List Dep} (h : ValOK m .int v P H) : ValOK m' .int v P' H' := by
  cases h; exact .int

end ValOK

mutual
def Val.ids : Val → List Nat
  | .node _ c d es => c :: d :: idsL es
  | .pair v w => v.ids ++ w.ids
  | .inl v => v.ids
  | .inr v => v.ids
  | .pkg _ _ _ v _ => v.ids
  | _ => []
def idsL : List Val → List Nat
  | [] => []
  | e :: es => e.ids ++ idsL es
end

def OwnedAt (m : Mem) (x : Var) (t : Val) : Prop := m.st x = some ⟨true, some t⟩

/-- No view stored in a tree points into that same tree's buffers (a struct
    never views its own field). -/
def SelfFree (T : Val) : Prop :=
  ∀ d o l, Sub (.view d o l) T → ∀ u c es, ¬ Sub (.node u c d es) T

/-- One owner per allocation, every owned address is live, and no owned tree
    views itself. -/
structure HeapOK (m : Mem) : Prop where
  nodup : ∀ x t, OwnedAt m x t → t.ids.Nodup
  disj  : ∀ x y t u, x ≠ y → OwnedAt m x t → OwnedAt m y u → ∀ i ∈ t.ids, i ∉ u.ids
  alloc : ∀ x t, OwnedAt m x t → ∀ i ∈ t.ids, m.alloc i = true ∧ i < m.nid
  self  : ∀ x t, OwnedAt m x t → SelfFree t
  -- A3.1: a block owns its own address and its payload's, as a slot owns
  -- its tree's: distinct, live, and no other owner's
  bnodup : ∀ k bl, m.blk k = some bl → (k :: bl.pay.ids).Nodup
  bdisj  : ∀ k bl x t, m.blk k = some bl → OwnedAt m x t → ∀ i ∈ k :: bl.pay.ids, i ∉ t.ids
  bdisj2 : ∀ k k' bl bl', k ≠ k' → m.blk k = some bl → m.blk k' = some bl' →
             ∀ i ∈ k :: bl.pay.ids, i ∉ k' :: bl'.pay.ids
  balloc : ∀ k bl, m.blk k = some bl → ∀ i ∈ k :: bl.pay.ids, m.alloc i = true ∧ i < m.nid

/-- A binding's slot agrees with its entry. -/
def SlotOK (m : Mem) (E : Entry) (sl : Slot) : Prop :=
  sl.own = E.mode.ownSlot ∧
  (E.mode.ownSlot = true →
    E.ty.owning = true ∧ (∀ T, sl.val = some T → WFv E.ty T) ∧
    (E.live = true → ∃ T, sl.val = some T ∧ ViewsOK m E.ty T E.held)) ∧
  (E.mode.ownSlot = false →
    (E.live = true → ∃ v, sl.val = some v ∧ ValOK m E.ty v E.path E.held))

/-- A2-drop.2: a binding `letd` made whose slot owns a value is armed, and
    the value's views are valid, whether its entry is live or not: the
    destructor reads them where the scope ends (after a join on which one
    path moved it, the entry is dead but the slot may own). -/
def ArmOK (m : Mem) (E : Entry) (sl : Slot) : Prop :=
  E.dbind = true → E.mode.ownSlot = true → ∀ T, sl.val = some T → E.dtor = true ∧ ViewsOK m E.ty T E.held

/-- The bindings of the run-time scopes a statement is inside of, innermost
    last: they are bound for as long as the statement runs. -/
def Stmt.spine : Stmt → List Var
  | .seq a _ => a.spine
  | .scope x s => x :: s.spine
  | .scopeD x _ s => x :: s.spine
  | .rbind p s => p :: s.spine
  | .frozen _ s => s.spine
  | .catchR _ _ s => s.spine
  | _ => []

/-- A3.1: every share an owned tree holds (a slot's, or a block's payload)
    carries the payload its block holds. It follows from `MInv`
    (`MInv.sharesHeld`), and lets a borrow that reaches into a payload
    through a share find that payload's nodes in memory (`SubS.loc`). -/
def SharesHeld (m : Mem) : Prop :=
  ∀ T, TreeAt m T → ∀ k p, Sub (.arc k p) T → ∃ u, m.blk k = some ⟨u, p⟩

/-- Nothing leaks: every live address is in a tree some binding owns, or
    (A3.1) is a block's or its payload's. -/
def Covers (m : Mem) : Prop := ∀ i, m.alloc i = true →
  (∃ x t, OwnedAt m x t ∧ i ∈ t.ids) ∨ (∃ k bl, m.blk k = some bl ∧ i ∈ k :: bl.pay.ids)

/-- A `recover` frame returns to its caller's store: every binding outside
    the frames it has opened (and its result `x`) is as the caller left it. -/
def CatchOK (m : Mem) : Stmt → Prop
  | .seq a _ => CatchOK m a
  | .scope _ s => CatchOK m s
  | .scopeD _ _ s => CatchOK m s
  | .rbind _ s => CatchOK m s
  | .frozen _ s => CatchOK m s
  | .catchR x m0 s => (∀ v, v ∉ s.spine → v ≠ x → m.st v = m0.st v) ∧
      x ∉ s.spine ∧ m0.nv ≤ m.nv ∧
      -- A3.1 (so far): no step changes the counted blocks
      m.blk = m0.blk ∧ CatchOK m s
  | _ => True

/-- A borrowed parameter depends only on what was bound before its call: on
    no binding of a run-time scope the call's body has opened. A panic that
    unwinds those scopes therefore leaves its dependencies bound. -/
def PinOK (Γ : Ctx) : Stmt → Prop
  | .seq a _ => PinOK Γ a
  | .scope _ s => PinOK Γ s
  | .scopeD _ _ s => PinOK Γ s
  | .rbind p s => (∀ E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r ∉ s.spine) ∧ PinOK Γ s
  | .frozen _ s => PinOK Γ s
  | .catchR _ _ s => PinOK Γ s
  | _ => True

/-- A2-drop.2: a binding `letd` made depends, in memory, on no binding of
    a run-time scope opened inside its own frame, so a panic that unwinds
    those scopes leaves its views bound (nurlc #254). -/
def DtorIn (Γ : Ctx) (x : Var) (s : Stmt) : Prop :=
  ∀ E, Γ x = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
    ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∉ s.spine

def DtorPinOK (Γ : Ctx) : Stmt → Prop
  | .seq a _ => DtorPinOK Γ a
  | .scope x s => DtorIn Γ x s ∧ DtorPinOK Γ s
  | .scopeD x _ s => DtorIn Γ x s ∧ DtorPinOK Γ s
  | .rbind p s => DtorIn Γ p s ∧ DtorPinOK Γ s
  | .frozen _ s => DtorPinOK Γ s
  | .catchR _ _ s => DtorPinOK Γ s
  | _ => True

/-- A statement inside no run-time scope pins nothing. -/
theorem DtorPinOK.of_spine_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) : DtorPinOK Γ s := by
  induction s with
  | seq a _ iha _ => exact iha h
  | frozen _ k ih => exact ih h
  | catchR _ _ k ih => exact ih h
  | scope _ _ _ => simp [Stmt.spine] at h
  | scopeD _ _ _ _ => simp [Stmt.spine] at h
  | rbind _ _ _ => simp [Stmt.spine] at h
  | _ => trivial

/-- `DtorPinOK` reads only what the `letd` bindings view: a context that
    keeps them, or views less, keeps it. -/
theorem DtorPinOK.of_dbind {Γ Γ' : Ctx}
    (h : ∀ v E', Γ' v = some E' → E'.dbind = true → E'.mode.ownSlot = true →
      (E'.ty ≠ .int ∨ E'.mode = .rootb) → ∃ E, Γ v = some E ∧ E.dbind = true ∧ E.mode.ownSlot = true ∧
        (E.ty ≠ .int ∨ E.mode = .rootb) ∧ ∀ d ∈ E'.vdeps, d.kind.isName = false → d ∈ E.vdeps)
    {s : Stmt} (hp : DtorPinOK Γ s) : DtorPinOK Γ' s := by
  have hin : ∀ x k, DtorIn Γ x k → DtorIn Γ' x k := by
    intro x k hx E' hE' hd hos hn d hdd hnm
    obtain ⟨E, hE, hd0, hos0, hn0, hsub⟩ := h x E' hE' hd hos hn
    exact hx E hE hd0 hos0 hn0 d (hsub d hdd hnm) hnm
  induction s with
  | seq a _ iha _ => exact iha hp
  | scope x k ih => exact ⟨hin x k hp.1, ih hp.2⟩
  | scopeD x _ k ih => exact ⟨hin x k hp.1, ih hp.2⟩
  | rbind p k ih => exact ⟨hin p k hp.1, ih hp.2⟩
  | frozen _ k ih => exact ih hp
  | catchR _ _ k ih => exact ih hp
  | _ => trivial

theorem dtorOut_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) :
    ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true → (E.ty ≠ .int ∨ E.mode = .rootb) →
      v ∉ s.spine → ∀ d ∈ E.vdeps, d.kind.isName = false → d.root ∉ s.spine :=
  fun _ _ _ _ _ _ _ _ _ _ hr => by rw [h] at hr; cases hr

/-- `PinOK` reads only borrowed parameters: a context that keeps them keeps it. -/
theorem PinOK.of_rootb {Γ Γ' : Ctx} (h : ∀ p E, Γ' p = some E → E.mode = .rootb → Γ p = some E)
    {s : Stmt} (hp : PinOK Γ s) : PinOK Γ' s := by
  induction s with
  | seq a _ iha _ => exact iha hp
  | scope _ k ih => exact ih hp
  | scopeD _ _ k ih => exact ih hp
  | rbind p k ih => exact ⟨fun E hE hm => hp.1 E (h p E hE hm) hm, ih hp.2⟩
  | frozen _ k ih => exact ih hp
  | catchR _ _ k ih => exact ih hp
  | _ => trivial

/-- A statement inside no run-time scope is inside no call either. -/
theorem PinOK.of_spine_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) : PinOK Γ s := by
  induction s with
  | seq a _ iha _ => exact iha h
  | frozen _ k ih => exact ih h
  | catchR _ _ k ih => exact ih h
  | scope _ _ _ => simp [Stmt.spine] at h
  | scopeD _ _ _ _ => simp [Stmt.spine] at h
  | rbind _ _ _ => simp [Stmt.spine] at h
  | _ => trivial

theorem pinOut_nil {Γ : Ctx} {s : Stmt} (h : s.spine = []) :
    ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ r ∈ roots E.vdeps, r ∉ s.spine :=
  fun _ _ _ _ _ _ _ hr => by rw [h] at hr; cases hr

/-- A borrowed parameter is anchored: what it borrows from, and what the
    closures it holds only read, are lent out (`F`) for as long as it is
    bound.  (What those closures may change is pinned: no rule replaces it,
    `NoPin`.) -/
def Anchored (E : Entry) (F : List Var) : Prop :=
  ∀ d ∈ E.vdeps, d.kind.bound = .none → d.root ∈ F

/-- The borrowed parameters' anchors. -/
def RootbAnch (Γ : Ctx) (F : List Var) : Prop :=
  ∀ p E, Γ p = some E → E.mode = .rootb → Anchored E F

theorem Anchored.mono {E : Entry} {F F' : List Var} (h : Anchored E F) (hF : ∀ v ∈ F, v ∈ F') :
    Anchored E F' :=
  fun d hd hb => hF _ (h d hd hb)


/-- What memory and context guarantee, whatever is running. -/
structure MInv (m : Mem) (Γ : Ctx) : Prop where
  dom       : ∀ v, (Γ v).isSome = (m.st v).isSome
  slot      : ∀ v E, Γ v = some E → ∃ sl, m.st v = some sl ∧ E.ty.ok = true ∧ SlotOK m E sl
  heap      : HeapOK m
  nvSt      : ∀ v, (m.st v).isSome → v < m.nv
  noInout   : ∀ v E b, Γ v = some E → E.mode ≠ .inout b
  wf        : CtxWF Γ
  rootbLive : ∀ p E, Γ p = some E → E.mode = .rootb → E.live = true
  rootbLt   : ∀ p E, Γ p = some E → E.mode = .rootb → ∀ r ∈ roots E.vdeps, r < p
  names     : NameWF Γ
  held      : ∀ v E sl T, Γ v = some E → E.live = true → m.st v = some sl → sl.val = some T →
                NamesIn T E.held
  pkgs      : ∀ v sl T, m.st v = some sl → sl.val = some T → PkgsOK T
  armed     : ∀ v E sl, Γ v = some E → m.st v = some sl → ArmOK m E sl
  /-- A3.1: every share an owned tree holds names a live block of its type. -/
  shares    : ∀ v E sl T, Γ v = some E → m.st v = some sl → sl.own = true → sl.val = some T →
                SharesOK m E.ty T
  /-- A3.1: a block's payload is a well-formed tree of a type that holds no
      views, and the shares it holds name blocks too. -/
  blocks    : ∀ k bl, m.blk k = some bl → bl.ty.ok = true ∧ bl.ty.holdsView = false ∧
                WFv bl.ty bl.pay ∧ SharesOK m bl.ty bl.pay

/-- The invariant of a configuration running `s` in context `Γ`, with `F`
    lent out. -/
structure Inv (m : Mem) (Γ : Ctx) (F : List Var) (s : Stmt) : Prop extends MInv m Γ where
  nvS       : ∀ v ∈ s.vars, v < m.nv
  nvF       : ∀ v ∈ F, v < m.nv
  anch      : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → Anchored E F
  spineNd   : s.spine.Nodup
  spineDom  : ∀ v ∈ s.spine, ∃ E, Γ v = some E
  catchOK   : CatchOK m s
  cover     : Covers m
  /-- A borrowed parameter bound outside the running scopes depends on none
      of their bindings, and each one bound inside depends on none of the
      scopes opened inside its call (`PinOK`). -/
  pinOut    : ∀ p E, Γ p = some E → E.mode = .rootb → p ∉ s.spine → ∀ r ∈ roots E.vdeps, r ∉ s.spine
  pinIn     : PinOK Γ s
  /-- A2-drop.2: so for a binding `letd` made, in memory (the panic path,
      nurlc #254). -/
  dtorOut   : ∀ v E, Γ v = some E → E.dbind = true → E.mode.ownSlot = true →
                (E.ty ≠ .int ∨ E.mode = .rootb) → v ∉ s.spine → ∀ d ∈ E.vdeps,
                d.kind.isName = false → d.root ∉ s.spine
  dtorIn    : DtorPinOK Γ s

/-! ### Typing of statements

Here, after the invariant, because the run-time form of a `recover` frame
is typed by the store it will return to. -/

/-- The bindings outside `sp` are those of `Δ`, with their modes and types,
    and a borrowed parameter's entry unchanged. -/
def KeepOut (Γ Δ : Ctx) (sp : List Var) : Prop :=
  (∀ v E, Γ v = some E → v ∉ sp →
    ∃ E', Δ v = some E' ∧ E'.mode = E.mode ∧ E'.ty = E.ty ∧ (E.mode = .rootb → E' = E)) ∧
  (∀ v E', Δ v = some E' → v ∉ sp ∧ ∃ E, Γ v = some E)

/-- `f` is a destructor for values of type `t`: it takes one borrowed `t`,
    returns an integer and lends, holds and stores nothing. -/
def DtorOK (P : Prog) (f : Nat) (t : Ty) : Prop :=
  ∃ fn, P[f]? = some fn ∧ fn.params = [(.inp, t)] ∧ fn.resTy = .int ∧ fn.resOwn = false ∧
    fn.lends = [] ∧ fn.rholds = [] ∧ fn.outHolds = []

inductive StmtT (P : Prog) : Ctx → List Var → Stmt → Ctx → Prop
  | skip {Γ : Ctx} {F : List Var} : StmtT P Γ F .skip Γ
  | seq {Γ Γ1 Δ : Ctx} {F : List Var} {a b : Stmt} :
      b.src = true → StmtT P Γ F a Γ1 → StmtT P Γ1 F b Δ → StmtT P Γ F (.seq a b) Δ
  | letv {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {r : Rhs} {s : Stmt} {E : Entry} :
      s.src = true → Γ x = none → x ∉ F → RhsT Γ F r E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letv x r s) (exitScope x Δ)
  | letcall {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {s : Stmt}
      {E : Entry} :
      s.src = true → Γ x = none → x ∉ F → CallT P Γ F f args E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letcall x f args s) (exitScope x Δ)
  | scope {Γ Δ : Ctx} {F : List Var} {x : Var} {s : Stmt} :
      (∃ E, Γ x = some E ∧ E.mode ≠ .rootb) → x ∉ F → StmtT P Γ F s Δ → EndOK Δ x →
      StmtT P Γ F (.scope x s) (exitScope x Δ)
  | rbind {Γ Δ : Ctx} {F : List Var} {p : Var} {s : Stmt} {E : Entry} :
      Γ p = some E → E.mode = .rootb → E.live = true → Anchored E F → p ∉ F →
      StmtT P Γ F s Δ →
      -- what the borrowed binding may change by name is not lent, but stays
      -- bound for its scope: it is the caller's
      (∀ d ∈ E.vdeps, d.kind.bound ≠ .none → d.root ≠ p ∧ ∃ Er, Δ d.root = some Er ∧ Er.mode.isRoot = true) →
      StmtT P Γ F (.rbind p s) (exitRoot p (E.path ++ E.held) Δ)
  | frozen {Γ Δ : Ctx} {F z z' : List Var} {s : Stmt} :
      -- `z` bounds what is lent: the typing lends a part of it
      StmtT P Γ (F ++ z') s Δ → (∀ v ∈ z', v ∈ z) → StmtT P Γ F (.frozen z s) Δ
  | assign {Γ Γ1 : Ctx} {F : List Var} {x : Var} {r : Rhs} {Ex E : Entry} :
      Γ x = some Ex → x ∉ F →
      (Ex.mode = .own ∧ E.mode = .own ∨ Ex.mode = .inout .replace ∧ E.mode = .own ∨
        Ex.mode = .bor ∧ E.mode = .bor) →
      RhsT Γ F r E Γ1 → E.ty = Ex.ty → x ∉ roots E.vdeps → (Γ1 x).isSome → NoPin Γ x →
      DtorSafe Γ1 .replace false x →
      -- A2-drop.2: a binding `letd` made gains no view (nurlc #254; its rule,
      -- views of older bindings only, needs an age the calculus lacks)
      Ex.dbind = false →
      StmtT P Γ F (.assign x r) (setE (kill .replace false x Γ1) x { E with mode := Ex.mode })
  | ite {Γ Δ : Ctx} {F : List Var} {c : Expr} {a b : Stmt} :
      a.src = true → b.src = true → ExprT Γ c → StmtT P Γ F a Δ → StmtT P Γ F b Δ →
      StmtT P Γ F (.ite c a b) Δ
  | while {Γ : Ctx} {F : List Var} {c : Expr} {s : Stmt} :
      s.src = true → ExprT Γ c → StmtT P Γ F s Γ → StmtT P Γ F (.while c s) Γ
  | push {Γ Γ1 : Ctx} {F : List Var} {x y : Var} {Ex Ey Ex1 : Entry} {t : Ty} {D : List Dep} :
      Γ x = some Ex → Ex.live = true → Ex.ty = .vec t → canDo Ex.mode .realloc → x ∉ F →
      Γ y = some Ey → Ey.live = true → Ey.ty = t → y ≠ x →
      PushArg Γ F y Ey t D Γ1 → x ∉ roots D →
      Γ1 x = some Ex1 → Ex1.live = true → DtorSafe Γ1 .realloc t.holdsView x →
      -- A2-drop.2: a destructor binding gains no view
      (Ex.dbind = true → t.holdsView = false) →
      StmtT P Γ F (.push x y)
        (setE (kill .realloc t.holdsView x Γ1) x { Ex1 with held := Ex1.held ++ ownHeld true t D })
  | free {Γ : Ctx} {F : List Var} {x : Var} {E : Entry} {t : Ty} :
      Γ x = some E → E.live = true → E.mode = .own → E.ty = .vec t → x ∉ F → EndOK Γ x →
      StmtT P Γ F (.free x) (setE (kill .replace false x Γ) x { E with live := false, dtor := false })
  | sub {Γ Γ0 Δ0 Δ : Ctx} {F : List Var} {s : Stmt} :
      Weaker Γ Γ0 → StmtT P Γ0 F s Δ0 → (Δ0 = Δ ∨ Weaker Δ0 Δ) → StmtT P Γ F s Δ
  | panic {Γ Δ : Ctx} {F : List Var} :
      -- a panic never ends normally: what follows it may assume any context
      -- with the same bindings, modes and types, fixed entries as they were
      CtxWF Δ → NameWF Δ → (∀ v, (Γ v).isSome = (Δ v).isSome) →
      (∀ v E, Δ v = some E → ∃ E0, Γ v = some E0 ∧ E.mode = E0.mode ∧ E.ty = E0.ty ∧
        (E0.fixed → E = E0)) →
      -- A2-drop.2: ... and no binding `letd` made viewing more than it did,
      -- nor any no longer `letd`'s
      DKeep Γ Δ [] → DStay Γ Δ [] →
      StmtT P Γ F .panic Δ
  | letrec {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt} {E : Entry} {fn : Fn} :
      s.src = true → Γ x = none → x ∉ F → P[f]? = some fn → fn.params = [] → fn.resTy = .int →
      fn.resOwn = false → CallT P Γ F f [] E Γ1 → StmtT P (setE Γ1 x E) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letrec x f s) (exitScope x Δ)
  | unpair {Γ Δ : Ctx} {F : List Var} {y x z : Var} {s : Stmt} {E : Entry} {a b : Ty} :
      -- (an `inout` struct that may be replaced is taken apart too: a field
      -- replaced in place is the struct taken apart and assigned again)
      s.src = true → Γ y = some E → E.live = true → canDo E.mode .replace → E.ty = .prod a b → y ∉ F →
      Γ x = none → Γ z = none → x ≠ z → x ∉ F → z ∉ F →
      StmtT P (setE (setE (setE (kill .replace false y Γ) y { E with live := false, dtor := false }) x (compE E a)) z
        (compE E b)) F s Δ →
      -- `y` is replaced, not ended: what borrows it by name, and a destructor
      -- that views it, are what replacing it ends
      NoPin Γ y → DtorSafe Γ .replace false y → EndOK Δ z → EndOK (exitScope z Δ) x →
      StmtT P Γ F (.unpair y x z s) (exitScope x (exitScope z Δ))
  | callc {Γ Γ1 Δ : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt}
      {Ec E : Entry} {ms : List Nat} {σ : Nat} {sig : Fn} :
      k.src = true → Γ x = none → x ∉ F → Γ c = some Ec → Ec.ty = .fn ms → ms[j]? = some σ →
      P[σ]? = some sig → sig.params.head? = some (.inp, .fn ms) → (∀ o ∈ sig.outHolds, o.2.1 ≠ 0) →
      CallT P Γ F σ (c :: zs) E Γ1 →
      -- no argument is a binding the package may change by name (it is
      -- handed to the code as an `inout` argument of its own)
      (∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) →
      StmtT P (setE Γ1 x (recvRes c Ec E)) F k Δ →
      EndOK Δ x → StmtT P Γ F (.callc x c j zs k) (exitScope x Δ)
  | catchR {Γ Δ : Ctx} {F : List Var} {x : Var} {m0 : Mem} {s : Stmt} :
      x ∉ F → StmtT P Γ (F ++ (List.range m0.nv).filter (· ≠ x)) s Δ →
      MInv (m0.set x ⟨false, some (.int 1)⟩) Δ →
      (RootbAnch Δ F) →
      KeepOut Γ Δ s.spine → DStay Γ Δ s.spine →
      StmtT P Γ F (.catchR x m0 s) Δ
  /-- A2-drop.1: a binding with a destructor, of a type that holds no views
      (its value is valid however the binding died). -/
  | letd {Γ Γ1 Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {r : Rhs} {s : Stmt} {E : Entry}
      {H : List Dep} :
      s.src = true → Γ x = none → x ∉ F → RhsT Γ F r E Γ1 → E.mode = .own →
      E.ty.hasFn = false → DtorOK P f E.ty →
      -- A2-drop.2: the binding, armed, views what the value does, or more
      HeldUp Γ1 E H → StmtT P (setE Γ1 x (Entry.arm { E with held := H })) F s Δ →
      EndOK Δ x → StmtT P Γ F (.letd x f r s) (exitScope x Δ)
  | scopeD {Γ Δ : Ctx} {F : List Var} {x : Var} {f : Nat} {s : Stmt} :
      (∃ E, Γ x = some E ∧ E.mode = .own ∧ E.ty.hasFn = false ∧ DtorOK P f E.ty) → x ∉ F →
      StmtT P Γ F s Δ → EndOK Δ x →
      KeepOut Γ Δ s.spine → CtxWF Δ → NameWF Δ →
      -- A2-drop.2: the binding is `letd`'s when its type holds views (its
      -- destructor reads them)
      (∀ E, Δ x = some E → E.ty.holdsView = true → E.dbind = true) →
      StmtT P Γ F (.scopeD x f s) (exitScope x Δ)

/-- A function is well-typed when its body is, from its own view of the
    parameters, and ends as its summary says: the result is set and borrows
    and holds only what `lends` and `rholds` name, every `inout` parameter
    is set again and holds only what `outHolds` names (an owned result or
    an `inout` parameter whose type holds no views holds nothing). -/
def FnOK (P : Prog) (fn : Fn) : Prop :=
  fn.body.src = true ∧ fn.params.length < fn.nvars ∧ (∀ v ∈ fn.body.vars, v < fn.nvars) ∧
  fn.resTy.ok = true ∧ (fn.resOwn = true → fn.resTy.owning = true) ∧
  (∀ pt ∈ fn.params, pt.2.ok = true ∧
    (pt.1 = .sink → pt.2.owning = true) ∧ (∀ b, pt.1 = .inout b → pt.2.owning = true)) ∧
  (∀ jk ∈ fn.lends, lendable fn jk.1 ∧ jk.2.isName = false) ∧
  (∀ jk ∈ fn.rholds, lendable fn jk.1 ∧ jk.2.isName = false) ∧
  (∀ o ∈ fn.outHolds, lendable fn o.2.1 ∧ o.2.2.isName = false) ∧
  (∀ jk ∈ fn.lends ++ fn.rholds, kindFits fn jk.1 jk.2) ∧ (∀ o ∈ fn.outHolds, kindFits fn o.2.1 o.2.2) ∧
  ∃ Δ, StmtT P (sigCtx fn) [] fn.body Δ ∧
    -- A2-drop.2: the body's own destructor bindings have ended, and no
    -- parameter or result runs a destructor
    (∀ v E, Δ v = some E → E.dtor = false ∧ E.dbind = false) ∧
    (∃ Er, Δ fn.params.length = some Er ∧ Er.live = true ∧ Er.ty = fn.resTy ∧
      Er.mode = resMode fn ∧
      (∀ d ∈ Er.path, (d.root, d.kind) ∈ fn.lends) ∧
      (∀ d ∈ Er.held, (d.root, d.kind) ∈ fn.rholds) ∧
      (fn.resOwn = true → fn.resTy.holdsView = false → Er.held = [])) ∧
    (∀ i (h : i < fn.params.length) b, fn.params[i].1 = .inout b →
      ∃ Ei, Δ i = some Ei ∧ Ei.live = true ∧ (∀ d ∈ Ei.held, (i, d.root, d.kind) ∈ fn.outHolds) ∧
        (fn.params[i].2.holdsView = false → Ei.held = []))

def ProgOK (P : Prog) : Prop := ∀ fn ∈ P, FnOK P fn

/-! ### Packages name code of their signature -/

/-- Code `f`, on an environment of type `te`, implements the interface `σ`:
    it takes the environment where the interface takes the receiver, and
    the interface's other parameters as the interface does; it returns what
    the interface returns, and lends, holds and stores no more than the
    interface says. -/
def Implements (P : Prog) (f : Nat) (te : Ty) (cs : List (Var × PMode × Ty)) (σ : Nat) : Prop :=
  ∃ fn sig, P[f]? = some fn ∧ P[σ]? = some sig ∧
    fn.params = (.inp, te) :: sig.params.tail ++ cs.map (·.2) ∧
    fn.resTy = sig.resTy ∧ fn.resOwn = sig.resOwn ∧ fn.lends ⊆ sig.lends ∧ fn.rholds ⊆ sig.rholds ∧
    fn.outHolds ⊆ sig.outHolds

/-- A package's code implements its interfaces, method by method. -/
def CodeOK (P : Prog) (fs : List Nat) (te : Ty) (ms : List Nat) (cs : List (Var × PMode × Ty)) : Prop :=
  fs.length = ms.length ∧ ∀ (j f σ : Nat), fs[j]? = some f → ms[j]? = some σ → Implements P f te cs σ

/-- Every package in memory names code that implements its interfaces. -/
def MemCodes (P : Prog) (m : Mem) : Prop :=
  ∀ x o V fs te ms e cs, m.st x = some ⟨o, some V⟩ → Sub (.pkg fs te ms e cs) V → CodeOK P fs te ms cs

def Rhs.codeOK (P : Prog) : Rhs → Prop
  | .pack fs te ms _ cs => CodeOK P fs te ms cs
  | _ => True

/-- Every package a statement makes names code of its signature (a closure
    literal's body is its code, checked with it). -/
def Stmt.codesOK (P : Prog) : Stmt → Prop
  | .seq a b => a.codesOK P ∧ b.codesOK P
  | .letv _ r s => r.codeOK P ∧ s.codesOK P
  | .letcall _ _ _ s => s.codesOK P
  | .assign _ r => r.codeOK P
  | .ite _ a b => a.codesOK P ∧ b.codesOK P
  | .while _ s => s.codesOK P
  | .scope _ s => s.codesOK P
  | .rbind _ s => s.codesOK P
  | .frozen _ s => s.codesOK P
  | .letrec _ _ s => s.codesOK P
  | .catchR _ _ s => s.codesOK P
  | .unpair _ _ _ s => s.codesOK P
  | .callc _ _ _ _ s => s.codesOK P
  | .letd _ _ r s => r.codeOK P ∧ s.codesOK P
  | .scopeD _ _ s => s.codesOK P
  | _ => True

def ProgCodes (P : Prog) : Prop := ∀ fn ∈ P, fn.body.codesOK P

end A2
