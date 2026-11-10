import A2.Syntax

/-
  A2 — operational semantics.

  Memory.  Every `Vec` has two allocations, a control block (`c`) and an
  element buffer (`d`).  `alloc` says which addresses are live; a freed
  address is never handed out again, so any later access to it is caught
  (an allocator that reuses addresses only hides such an access, so a
  program that never makes one behaves the same under it).

  An owned `Vec` is the tree `node t c d es` held in its owner's slot; its
  elements are inside it.  A borrowed `Vec` is `href c` and a view is
  `view d off len` — bare addresses, found again in memory on every use.
  Every access checks that the addresses it touches are allocated and, for
  a view, that the element is inside the buffer: a use after free, a
  double free, a read through a dangling view and an out-of-bounds read all
  have no step.  A moved-from slot holds nothing (its drop flag is clear).

  `vec_push` may or may not move the buffer: both are steps, so everything
  proven holds whatever the allocator does.  A bounds-checked access that
  fails panics, which is a defined way to stop (A2 adds what a panic
  releases).
-/

namespace A2

/-- `v` occurs in tree `t` (reflexively). -/
inductive Sub : Val → Val → Prop
  | refl (v : Val) : Sub v v
  | child {v e : Val} {t : Ty} {c d : Nat} {es : List Val} :
      e ∈ es → Sub v e → Sub v (.node t c d es)
  | fst {v a b : Val} : Sub v a → Sub v (.pair a b)
  | snd {v a b : Val} : Sub v b → Sub v (.pair a b)
  | inl {v a : Val} : Sub v a → Sub v (.inl a)
  | inr {v a : Val} : Sub v a → Sub v (.inr a)
  | pkg {v e : Val} {fs : List Nat} {te : Ty} {ms : List Nat} {cs : List (Var × PMode × Ty)} :
      Sub v e → Sub v (.pkg fs te ms e cs)

/-- `Repl n n' T T'`: `T'` is `T` with one occurrence of `n` replaced by `n'`
    (a change through a borrowed handle rewrites the node at its cell in its
    owner's tree; the lemmas are in `Repl.lean`, Agora #295). -/
inductive Repl (n n' : Val) : Val → Val → Prop
  | here : Repl n n' n n'
  | elem {t : Ty} {c d : Nat} {pre post : List Val} {e e' : Val} :
      Repl n n' e e' → Repl n n' (.node t c d (pre ++ e :: post)) (.node t c d (pre ++ e' :: post))
  | fst {a a' b : Val} : Repl n n' a a' → Repl n n' (.pair a b) (.pair a' b)
  | snd {a b b' : Val} : Repl n n' b b' → Repl n n' (.pair a b) (.pair a b')
  | inl {a a' : Val} : Repl n n' a a' → Repl n n' (.inl a) (.inl a')
  | inr {a a' : Val} : Repl n n' a a' → Repl n n' (.inr a) (.inr a')
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {cs : List (Var × PMode × Ty)} {a a' : Val} :
      Repl n n' a a' → Repl n n' (.pkg fs te ms a cs) (.pkg fs te ms a' cs)

/-- A3.2: the tree a block owns: its payload, or nothing (`.int 0`, which
    owns no address and holds no handle or share) while a `lock` block's
    payload is checked out. -/
def Blk.tree (bl : Blk) : Val :=
  match bl.kind with
  | .view => .int 0   -- A3.3: a view owns nothing (its lock block owns what it reads)
  | _ => bl.pay.getD (.int 0)

/-- A3.2: the payload a block's holders read: an `arc` block's.  No one
    reads a `lock` block's payload while it is in the block, so nothing
    (`.int 0`) is read of it.  A3.3: a view's holders read its payload (the
    share of its lock block, and that block's payload). -/
def Blk.rd (bl : Blk) : Val :=
  match bl.kind with
  | .arc => bl.tree
  | .lock => .int 0
  | .view => bl.pay.getD (.int 0)

/-- A3.3: a view of lock block `k` lives (a read guard of an `RwLocked`): its
    payload is read, so whatever would change it waits (a writer's
    `withLock`, and an atomic or channel step on the block). -/
def HasView (B : Nat → Option Blk) (k : Nat) : Prop :=
  ∃ k' t p, B k' = some ⟨t, .view, some (.pair (.lk k) p)⟩

/-- The node with control block `c`, found in an owned tree, or (A3.1) in a
    live block's payload that its holders read (an `arc` block's, A3.2),
    which nothing writes. -/
def NodeAt (m : Mem) (c : Nat) (n : Val) : Prop :=
  (∃ x t, m.st x = some ⟨true, some t⟩ ∧ Sub n t ∧ ∃ ty d es, n = .node ty c d es) ∨
  (∃ k bl, m.blk k = some bl ∧ Sub n bl.rd ∧ ∃ ty d es, n = .node ty c d es)

/-- The node whose element buffer is `d`, found in an owned tree. -/
def DataAt (m : Mem) (d : Nat) (n : Val) : Prop :=
  (∃ x t, m.st x = some ⟨true, some t⟩ ∧ Sub n t ∧ ∃ ty c es, n = .node ty c d es) ∨
  (∃ k bl, m.blk k = some bl ∧ Sub n bl.rd ∧ ∃ ty c es, n = .node ty c d es)

-- Releasing a tree: each address must be live when it is freed.
mutual
inductive Frees : (Nat → Bool) → Val → (Nat → Bool) → Prop
  | int {a : Nat → Bool} {n : Nat} : Frees a (.int n) a
  | view {a : Nat → Bool} {d o l : Nat} : Frees a (.view d o l) a
  /-- A3.1: a share frees nothing by itself.  (The count is ghost; a block
      no share reaches is freed by the sweep that ends the step, `Steps`.) -/
  | arc {a : Nat → Bool} {k : Nat} {p : Val} : Frees a (.arc k p) a
  /-- A3.2: so does a lock share. -/
  | lk {a : Nat → Bool} {k : Nat} : Frees a (.lk k) a
  /-- A3.5: and a cell share. -/
  | cell {a : Nat → Bool} {k : Nat} : Frees a (.cell k) a
  | node {a a' : Nat → Bool} {t : Ty} {c d : Nat} {es : List Val} :
      a c = true → upd a c false d = true →
      FreesL (upd (upd a c false) d false) es a' →
      Frees a (.node t c d es) a'
  | pair {a a1 a2 : Nat → Bool} {v w : Val} : Frees a v a1 → Frees a1 w a2 → Frees a (.pair v w) a2
  | inl {a a1 : Nat → Bool} {v : Val} : Frees a v a1 → Frees a (.inl v) a1
  | inr {a a1 : Nat → Bool} {v : Val} : Frees a v a1 → Frees a (.inr v) a1
  | pkg {a a1 : Nat → Bool} {fs : List Nat} {te : Ty} {ms : List Nat} {v : Val}
      {cs : List (Var × PMode × Ty)} :
      Frees a v a1 → Frees a (.pkg fs te ms v cs) a1
inductive FreesL : (Nat → Bool) → List Val → (Nat → Bool) → Prop
  | nil {a : Nat → Bool} : FreesL a [] a
  | cons {a a1 a2 : Nat → Bool} {e : Val} {es : List Val} :
      Frees a e a1 → FreesL a1 es a2 → FreesL a (e :: es) a2
end

-- The addresses a tree owns: every node's control block and buffer.
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

/-! ### A3.1: blocks are collected by reachability

A block lives while some slot's value, or the payload of a block that lives,
holds a share of it or a handle into its payload.  A payload holds only
shares of older blocks (its value was made before the block), so nothing
cycles, and the blocks nothing reaches are exactly those the runtime's
count would have freed, one after the other, newest first; the model frees
them together, at the end of the step (`Mem.sweep`). -/

/-- A3.2: a share of block `k`: an `arc` share carrying its payload
    (`some p`), or a lock share (`none`). -/
def Val.share (k : Nat) : Option Val → Val
  | some p => .arc k p
  | none => .lk k

/-- `v` holds a share of block `k`: an `arc` or a lock share (`Val.share`), or
    (A3.5) a cell share. -/
def ShareIn (k : Nat) (v : Val) : Prop := (∃ p, Sub (Val.share k p) v) ∨ Sub (.cell k) v

/-- `v` refers to block `k` of `B`: it holds a share of it, or a handle whose
    address lies in its payload. -/
def Refers (B : Nat → Option Blk) (v : Val) (k : Nat) : Prop :=
  ShareIn k v ∨ ∃ bl, B k = some bl ∧
    ((∃ c, Sub (.href c) v ∧ c ∈ bl.rd.ids) ∨ ∃ d o l, Sub (.view d o l) v ∧ d ∈ bl.rd.ids)

/-- A3.2's second cut: what a block's payload keeps alive, whatever its kind:
    the payload it holds — an `arc` block's and a view's (what their holders
    read), and a lock block's while it is in the block (no one reads it, but
    the shares in it are the block's).  A checked-out payload is in its
    holder's slot, a root of its own. -/
def Blk.keeps (bl : Blk) : Val := bl.pay.getD (.int 0)

/-- The blocks of `B` reached from the values `R` (the slots' values), through
    the payloads of reached blocks (`Blk.keeps`; A3.2's second cut: a lock
    block's too, which may hold shares). -/
inductive Reached (R : Val → Prop) (B : Nat → Option Blk) : Nat → Prop
  | root {v : Val} {k : Nat} : R v → Refers B v k → Reached R B k
  | pay {k k' : Nat} {bl : Blk} : Reached R B k' → B k' = some bl → Refers B bl.keeps k → Reached R B k

/-- A3.2's second cut: a block as its holders see it, a lock block with its
    payload left out (no one reads it while it is in).  What `R` reaches
    through these (`Reached R (rdBlk B)`) it reaches through payloads that
    are read, which no step changes; a `recover` frame's store keeps that
    (`CatchOK`), where a lock's payload may change under it. -/
def Blk.rdOnly (bl : Blk) : Blk := if bl.kind = .lock then { bl with pay := none } else bl

def rdBlk (B : Nat → Option Blk) : Nat → Option Blk := fun k => (B k).map Blk.rdOnly

/-- What a store's slots hold. -/
def Mem.vals (m : Mem) (v : Val) : Prop := ∃ x o, m.st x = some ⟨o, some v⟩

/-- An address the payload of a block nothing reaches owns: the sweep frees it. -/
def Unreached (R : Val → Prop) (B : Nat → Option Blk) (i : Nat) : Prop :=
  ∃ k bl, B k = some bl ∧ ¬ Reached R B k ∧ i ∈ bl.tree.ids

open Classical in
/-- The sweep's addresses: every one an unreached payload owns is freed. -/
noncomputable def sweepAlloc (R : Val → Prop) (B : Nat → Option Blk) (a : Nat → Bool) : Nat → Bool :=
  fun i => a i && !decide (Unreached R B i)

open Classical in
/-- The sweep's blocks: the reached ones. -/
noncomputable def sweepBlk (R : Val → Prop) (B : Nat → Option Blk) : Nat → Option Blk :=
  fun k => if Reached R B k then B k else none

/-- **The sweep** at the end of a step: every block no slot's value reaches is
    removed and its payload tree freed. -/
noncomputable def Mem.sweep (m : Mem) : Mem :=
  { m with alloc := sweepAlloc m.vals m.blk m.alloc, blk := sweepBlk m.vals m.blk }

/-- What leaving a scope releases: an owned value whose flag is set. -/
inductive DropSlot : (Nat → Bool) → Slot → (Nat → Bool) → Prop
  | owned {a a' : Nat → Bool} {t : Val} : Frees a t a' → DropSlot a ⟨true, some t⟩ a'
  | moved {a : Nat → Bool} : DropSlot a ⟨true, none⟩ a
  | borrowed {a : Nat → Bool} {v : Option Val} : DropSlot a ⟨false, v⟩ a

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
  /-- A3.5b: the environment holds no more than the closure's type says. -/
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {q : Cross} {v : Val} {cs : List (Var × PMode × Ty)} :
      WFv te v → q.Fits te cs → WFv (.fn ms q) (.pkg fs te ms v cs)
  /-- A3.1: a share; its block, in memory, holds the payload it carries, one
      that holds no view. -/
  | arc {t : Ty} {k : Nat} {p : Val} : WFv t p → t.holdsView = false → WFv (.arc t) (.arc k p)
  /-- A3.2: a lock share; its block, in memory, is a lock block of its type. -/
  | lk {t : Ty} {k : Nat} : WFv (.lk t) (.lk k)
  /-- A3.5: a cell share; its block is a lock block of its type too. -/
  | cell {t : Ty} {k : Nat} : WFv (.cell t) (.cell k)
  /-- A2-drop.3: a destructor type's values are its inner type's, a struct's
      or an enum's (`% Drop` is on one of these). -/
  | dtor {f : Nat} {t : Ty} {v : Val} : t.isStruct = true → WFv t v → WFv (.dtor f t) v

/-- A3.1: tree `T` of type `τ` holds a share of block `k`, whose payload is
    a `u`: the one it carries, `some p`, or (A3.2) none, for a lock share.
    (Not inside a payload: the block's own shares are the block's.) -/
inductive ArcIn : Ty → Val → Ty → Nat → Option Val → Prop
  | here {u : Ty} {k : Nat} {p : Val} : ArcIn (.arc u) (.arc k p) u k (some p)
  /-- A3.2: a lock share of block `k`, of payload type `u` (it carries no
      payload: `none`). -/
  | lk {u : Ty} {k : Nat} : ArcIn (.lk u) (.lk k) u k none
  /-- A3.5: a cell share of block `k`, a lock block of payload type `u`. -/
  | cell {u : Ty} {k : Nat} : ArcIn (.cell u) (.cell k) u k none
  | child {t t' : Ty} {c d : Nat} {es : List Val} {e : Val} {u : Ty} {k : Nat} {p : Option Val} :
      e ∈ es → ArcIn t e u k p → ArcIn (.vec t) (.node t' c d es) u k p
  | fst {a b : Ty} {x y : Val} {u : Ty} {k : Nat} {p : Option Val} :
      ArcIn a x u k p → ArcIn (.prod a b) (.pair x y) u k p
  | snd {a b : Ty} {x y : Val} {u : Ty} {k : Nat} {p : Option Val} :
      ArcIn b y u k p → ArcIn (.prod a b) (.pair x y) u k p
  | inl {a b : Ty} {x : Val} {u : Ty} {k : Nat} {p : Option Val} : ArcIn a x u k p → ArcIn (.sum a b) (.inl x) u k p
  | inr {a b : Ty} {x : Val} {u : Ty} {k : Nat} {p : Option Val} : ArcIn b x u k p → ArcIn (.sum a b) (.inr x) u k p
  /-- (A3.5b: only a closure whose type may hold shares has one in its
      environment; a bare one's holds none, `WFv.pkg`.) -/
  | pkg {fs : List Nat} {te : Ty} {ms : List Nat} {x : Val} {cs : List (Var × PMode × Ty)} {u : Ty}
      {k : Nat} {p : Option Val} {q : Cross} :
      ArcIn te x u k p → q.shares = true → ArcIn (.fn ms q) (.pkg fs te ms x cs) u k p
  /-- A2-drop.3: a destructor type's values are its inner type's. -/
  | dtor {f : Nat} {t : Ty} {x : Val} {u : Ty} {k : Nat} {p : Option Val} :
      ArcIn t x u k p → ArcIn (.dtor f t) x u k p

/-- A3.3: a block an `arc` share names: an `arc` block holding `p`, or a
    view of a lock block (`rw_read`'s guard), whose payload `p` is a share of
    the lock block and that block's payload.  Both are frozen while they
    live. -/
def ArcBlk (b : Option Blk) (u : Ty) (p : Val) : Prop :=
  b = some ⟨u, .arc, some p⟩ ∨ b = some ⟨u, .view, some p⟩

/-- A3.2: what a share asks of its block: an `arc` share (carrying `some p`)
    an `arc` block holding `p`, a lock share (`none`) a lock block of its
    payload's type, holding its payload or not. -/
def ShareFits (b : Option Blk) (u : Ty) : Option Val → Prop
  | some p => ArcBlk b u p
  | none => ∃ o, b = some ⟨u, .lock, o⟩

/-- A3.1: every share a tree holds names a block of the store `B` that
    holds the payload the share carries, of the share's type (the block
    lives while a share of it is owned; an `arc` payload never changes), or
    (A3.2) a lock block of its type. -/
def SharesIn (B : Nat → Option Blk) (τ : Ty) (T : Val) : Prop :=
  ∀ u k p, ArcIn τ T u k p → ShareFits (B k) u p

/-! A2-drop.3: a destructor type's values are its inner type's. -/
theorem WFv.dtor_iff {f : Nat} {t : Ty} {v : Val} : WFv (.dtor f t) v ↔ t.isStruct = true ∧ WFv t v :=
  ⟨fun h => by cases h; constructor <;> assumption, fun ⟨ho, h⟩ => .dtor ho h⟩
theorem WFv.undtor {τ : Ty} {v : Val} (h : WFv τ v) : WFv τ.undtor v := by
  induction τ with
  | dtor _ _ ih => exact ih (WFv.dtor_iff.mp h).2
  | _ => exact h
/-- A tree of `τ` and one of the type under its wrappers: the second is a
    tree of `τ` too (what a wrapper asks is of the type, not the value). -/
theorem WFv.rewrap {τ : Ty} {v v' : Val} (h : WFv τ v) (h' : WFv τ.undtor v') : WFv τ v' := by
  induction τ with
  | dtor _ _ ih =>
    obtain ⟨ho, hi⟩ := WFv.dtor_iff.mp h
    exact .dtor ho (ih hi h')
  | _ => exact h'
/-- An integer is a tree of the integer type only. -/
theorem WFv.int_inv {t : Ty} {n : Nat} (h : WFv t (.int n)) : t = .int := by
  generalize hv : Val.int n = v at h
  induction h with
  | int => rfl
  | dtor ho _ ih => cases ih hv; cases ho
  | _ => cases hv

/-- An integer holds no share. -/
theorem ArcIn.not_int {t : Ty} {n : Nat} {u : Ty} {k : Nat} {p : Option Val} (h : ArcIn t (.int n) u k p) :
    False := by
  generalize hv : Val.int n = v at h
  induction h with
  | dtor _ ih => exact ih hv
  | _ => cases hv

/-- A node is a tree of a `Vec` of its own element type, under wrappers. -/
theorem WFv.node_ty {σ t : Ty} {c d : Nat} {es : List Val} (h : WFv σ (.node t c d es)) :
    σ.undtor = .vec t := by
  have hu := h.undtor; have hnd := Ty.undtor_ne σ
  generalize σ.undtor = σ' at hu hnd ⊢
  cases hu with
  | node => rfl
  | dtor => exact absurd rfl (hnd _ _)

/-- A node in the place of one of the same element type, at the type the
    first is a tree of. -/
theorem WFv.node_hole {σ t : Ty} {c d c' d' : Nat} {es es' : List Val} (h : WFv σ (.node t c d es))
    (h' : WFv (.vec t) (.node t c' d' es')) : WFv σ (.node t c' d' es') :=
  h.rewrap (by rw [h.node_ty]; exact h')

theorem ArcIn.dtor_iff {f : Nat} {t : Ty} {x : Val} {u : Ty} {k : Nat} {p : Option Val} :
    ArcIn (.dtor f t) x u k p ↔ ArcIn t x u k p :=
  ⟨fun h => by cases h; assumption, .dtor⟩
theorem ArcIn.undtor_iff {τ : Ty} {x : Val} {u : Ty} {k : Nat} {p : Option Val} :
    ArcIn τ.undtor x u k p ↔ ArcIn τ x u k p := by
  induction τ with
  | dtor _ _ ih => rw [Ty.undtor_dtor, ih, ArcIn.dtor_iff]
  | _ => exact Iff.rfl
theorem SharesIn.dtor_iff {B : Nat → Option Blk} {f : Nat} {t : Ty} {T : Val} :
    SharesIn B (.dtor f t) T ↔ SharesIn B t T := by
  simp only [SharesIn, ArcIn.dtor_iff]
theorem SharesIn.undtor_iff {B : Nat → Option Blk} {τ : Ty} {T : Val} :
    SharesIn B τ.undtor T ↔ SharesIn B τ T := by
  simp only [SharesIn, ArcIn.undtor_iff]

/-- A2-drop.3: `peel_dtor τ σ hnd hw` peels the destructor wrappers off `τ`:
    the tree's `hw : WFv τ v`, and every `ArcIn` and `SharesIn` at `τ` (and,
    from `Invariant.lean` on, every `SharesOK`, `ViewIn`, `ViewsOK` and `ValOK`),
    in the goal and the hypotheses, is restated at `σ`, its type under the wrappers, and `hnd : ∀ f t, σ ≠ .dtor
    f t`.  A case split on `hw` then meets no `dtor` case but the absurd one. -/
syntax "peel_dtor " ident ident ident ident : tactic
macro_rules
  | `(tactic| peel_dtor $τ $σ $hnd $hw) => `(tactic| (
      have $hnd := Ty.undtor_ne $τ
      replace $hw := WFv.undtor $hw
      try simp only [← ArcIn.undtor_iff (τ := $τ)] at *
      try simp only [← SharesIn.undtor_iff (τ := $τ)] at *
      generalize ($τ).undtor = $σ at *))

/-- A3.3, **read guards are `% NotSend`**: a read guard (a share of a view,
    what `rw_read` hands back) is released by the thread that took it — the
    runtime's `RGuard_drop` unlocks on that thread — so no guard crosses to
    another: neither one a crossing value holds, at any depth (a field, an
    element, a closure's environment), nor one in a block the value reaches
    (an `Arc`'s payload, a lock's).  As a check: no view is reached from the
    values (`Reached`, through the payloads of the blocks their shares name).
    nurlc refuses such a crossing statically (`% NotSend RGuard`, which
    propagates through fields, elements, closures and containers); the model
    asks it at run time, with the library handles' count (`SendCheck`), so a
    crossing nurlc refuses panics here.  A write guard is no value (it is a
    lock scope, `scopeL`), and a value lent through a guard is a borrow, which
    no crossing takes. -/
def NoGuard (B : Nat → Option Blk) (vs : List Val) : Prop :=
  ∀ k, Reached (· ∈ vs) B k → ∀ bl, B k = some bl → bl.kind ≠ .view

/-- A3.5, **the crossing check** (`mem_send_check`, docs/MEMORY.md §6.5): a
    library handle whose copies are one state (a cell) may cross only with
    every other owner of that state.  For every cell a crossing value holds a
    share of, no owned slot left behind (`st'`) holds one: the check is the
    runtime's count of the places in the values that hold each cell's block
    against its owners.  A borrow left behind is not counted (A3.5's third
    cut: a lent cell share is the share), as the runtime's count does not
    count it: a live borrow's owner is in the store (`MInv.cell_owned`), so
    where no owner is left behind no live borrow is, and a dead one is never
    read.  (`Sub` does not enter a share: a lock share's
    payload is the lock's, and moves with no crossing.)  A3.5 runs it at a
    spawn (`TStep.spawn`); A3.5's second cut at every value going into a lock
    block too — `locked_new` and a cell's constructor (`EvalR.lockNew`,
    `EvalR.cellNew`), `locked_restore` (`EvalR.lockRestore`), the give-back
    at a lock scope's end (`Release.put`, `Step.scopeLSkip`) and `chan_send`
    (`EvalR.chanSend`) — and a failed check panics there, as
    `mem_send_check` calls `nurl_panic`.  A3.3: the check also asks that no
    read guard crosses (`NoGuard`), which nurlc asks statically. -/
def SendCheck (B : Nat → Option Blk) (vs : List Val) (st' : Var → Option Slot) : Prop :=
  (∀ k, (∃ v ∈ vs, Sub (.cell k) v) → ∀ y w, st' y = some ⟨true, some w⟩ → ¬ Sub (.cell k) w) ∧
  NoGuard B vs

/-- A3.5's second cut: a channel's head, received, holds every owner of each
    cell it holds that the rest of the queue held: no element left behind
    holds a share of one.  The runtime has no such check, and needs none: a
    `Channel`'s queue is filled by `chan_send` alone, one checked value at a
    time.  The model's channel is a lock block, whose queue a `withLock` may
    also fill (`Locked (Vec T, i)` and `Channel T` are one type here), with
    two elements that share a cell; receiving one of them panics
    (`EvalR.chanRecvFail`), so no receive splits a cell's owners. -/
def RecvCheck (v : Val) (es : List Val) : Prop := ∀ k, Sub (.cell k) v → ∀ e ∈ es, ¬ Sub (.cell k) e

/-- A3.5's second cut: the give-back's crossing check.  What `x`'s slot gives
    back to its lock holds every owner of each cell it holds: no other slot
    holds a share of one (`SendCheck`).  `locked_with` and `locked_update`
    check the value after the closure ran on it, before they let the lock
    go: the closure may have kept a copy of a handle in it, or stored into
    it one kept outside. -/
def GiveCheck (m : Mem) (x : Var) (sl : Slot) : Prop := ∀ v, sl.val = some v → SendCheck m.blk [v] (m.remove x).st

/-- A3.2: what `x`'s slot can give back to a lock whose payload is a `t`:
    the tree it owns, or, for an integer payload, the integer it holds (an
    integer binding is a plain one).  A3.3: a tree of the payload's type
    (which a typed program's `x` always holds), so a give-back on a panic's
    unwinding keeps the block well formed with no typing at hand.  A3.2's
    second cut: and whose shares name blocks of `B` as the payload's type
    says (`SharesIn`), for the same reason, now that a payload may hold
    shares. -/
def Giveable (B : Nat → Option Blk) (t : Ty) : Slot → Prop
  | ⟨true, some v⟩ => WFv t v ∧ SharesIn B t v
  | ⟨false, some (.int _)⟩ => t = .int
  | _ => False

/-- A3.2: the end of `x`'s lock scope on lock block `k`, whose payload is a
    `t`: `x`'s value goes back into the block, which has it checked out; or
    else `x`'s slot is dropped as a scope's is.  That is when the block is
    gone (no share reaches it any more), or `x` holds nothing it can give
    back (it was moved out: the lock stays checked out until a restore, as
    `locked_take` leaves it, `Rhs.lockTake`); a typed program meets
    no other case (the block is the one `x` took its payload from), but
    the rule needs no invariant to say so.  A3.5's second cut: or what it
    would give back fails the crossing check (`GiveCheck`).  That is the
    panic's unwinding only: at the scope's normal end a failed check panics
    first (`Step.scopeLFail`). -/
inductive Release (m : Mem) (k : Nat) (t : Ty) (x : Var) : Mem → Prop
  | put {o : Bool} {v : Val} : m.st x = some ⟨o, some v⟩ → Giveable m.blk t ⟨o, some v⟩ →
      m.blk k = some ⟨t, .lock, none⟩ → GiveCheck m x ⟨o, some v⟩ →
      Release m k t x ({ m with blk := upd m.blk k (some ⟨t, .lock, some v⟩) }.remove x)
  | drop {sl : Slot} {a' : Nat → Bool} :
      (m.blk k ≠ some ⟨t, .lock, none⟩ ∨ ¬ Giveable m.blk t sl ∨ ¬ GiveCheck m x sl) →
      m.st x = some sl → DropSlot m.alloc sl a' → Release m k t x ({ m with alloc := a' }.remove x)

/-- The vector `x` names — its own tree, or the one its borrow points at —
    with both of its addresses live. -/
def VecOf (m : Mem) (x : Var) (t : Ty) (c d : Nat) (es : List Val) : Prop :=
  m.alloc c = true ∧ m.alloc d = true ∧
  (m.st x = some ⟨true, some (.node t c d es)⟩ ∨
   (m.st x = some ⟨false, some (.href c)⟩ ∧ NodeAt m c (.node t c d es)))

/-- The vector `x` names and the slot `o` whose tree `T` holds it: `x`'s own
    tree (`o = x`), or, for a borrowed `x`, the owned tree its handle points
    into, at any depth (#295). -/
def NodeOf (m : Mem) (x o : Var) (T : Val) (t : Ty) (c d : Nat) (es : List Val) : Prop :=
  m.alloc c = true ∧ m.alloc d = true ∧ m.st o = some ⟨true, some T⟩ ∧
  ((o = x ∧ T = .node t c d es) ∨ (m.st x = some ⟨false, some (.href c)⟩ ∧ Sub (.node t c d es) T))

inductive Eval (m : Mem) : Expr → Nat → Prop
  | lit {n : Nat} : Eval m (.lit n) n
  | var {x : Var} {n : Nat} : m.st x = some ⟨false, some (.int n)⟩ → Eval m (.var x) n
  | add {a b : Expr} {p q : Nat} : Eval m a p → Eval m b q → Eval m (.add a b) (p + q)
  | lt {a b : Expr} {p q : Nat} :
      Eval m a p → Eval m b q → Eval m (.lt a b) (if p < q then 1 else 0)
  | len {x : Var} {t : Ty} {c d : Nat} {es : List Val} :
      VecOf m x t c d es → Eval m (.len x) es.length
  | slen {x : Var} {d o l : Nat} :
      m.st x = some ⟨false, some (.view d o l)⟩ → Eval m (.slen x) l
  | isl {x : Var} {o : Bool} {v : Val} : m.st x = some ⟨o, some (.inl v)⟩ → Eval m (.isl x) 1
  | isr {x : Var} {o : Bool} {v : Val} : m.st x = some ⟨o, some (.inr v)⟩ → Eval m (.isl x) 0

/-- An element read out of a buffer: an element `Vec` is lent, as `href`;
    a struct is copied with what it holds lent.  A share is lent as itself,
    a word that names its block: an `arc` share, a lock share and (A3.5's
    third cut) a cell share.  A borrow of a library handle is the handle, as
    the runtime's pointer copy is: the library changes the state through it
    and copies it (`withCell`, `cellClone` through a borrowed root).  It
    never leaves its thread (a spawn's and a lock's value is owned and holds
    no view), so the crossing check counts it as its owner's thread's
    (`SendCheck`). -/
def lendOf : Val → Val
  | .node _ c _ _ => .href c
  | .pair v w => .pair (lendOf v) (lendOf w)
  | .inl v => .inl (lendOf v)
  | .inr v => .inr (lendOf v)
  | .pkg fs te ms v cs => .pkg fs te ms (lendOf v) cs
  | v => v

mutual
/-- The bindings captured by name anywhere in a value, with how each is
    captured and its type. -/
def Val.names : Val → List (Var × PMode × Ty)
  | .node _ _ _ es => namesL es
  | .pair v w => v.names ++ w.names
  | .inl v => v.names
  | .inr v => v.names
  | .pkg _ _ _ v cs => cs ++ v.names
  | _ => []
def namesL : List Val → List (Var × PMode × Ty)
  | [] => []
  | e :: es => e.names ++ namesL es
end

/-- Does moving this value move an owned tree (a `Vec` or a struct)? -/
def Val.owns : Val → Bool
  | .node .. => true
  | .pair .. => true
  | .inl .. => true
  | .inr .. => true
  | .pkg .. => true
  | .arc _ _ => true   -- A3.1: a share is owned; dropping it is what counts
  | .lk _ => true      -- A3.2: so is a lock share
  | .cell _ => true    -- A3.5: and a cell share
  | _ => false

/-- A tree of an owning type owns what it holds. -/
theorem WFv.owns {t : Ty} {v : Val} (h : WFv t v) (ho : t.owning = true) : v.owns = true := by
  induction h with
  | int => cases ho
  | view => cases ho
  | dtor h1 _ ih => exact ih (Ty.owning_of_isStruct h1)
  | _ => rfl

/-- Handing a value on: an owner gives up its value, anything else is
    copied.  A3.5's third cut: a borrowed value handed on holds no library
    handle — a typed program hands on a borrowed integer or slice only
    (`PushArg`), and a copy of a borrowed handle is a `cellClone` — so what
    an owned tree gains is an owner's (`A3/Cell.lean`'s confinement over
    owned slots). -/
inductive TakeVal (m : Mem) : Var → Val → Mem → Prop
  | own {y : Var} {v : Val} : m.st y = some ⟨true, some v⟩ → TakeVal m y v (m.set y ⟨true, none⟩)
  | bor {y : Var} {v : Val} : m.st y = some ⟨false, some v⟩ → (∀ k, ¬ Sub (.cell k) v) → TakeVal m y v m

/-- A3.5's third cut: an owned slot of the store holds a share of cell `k`. -/
def OwnedCell (m : Mem) (k : Nat) : Prop := ∃ x T, m.st x = some ⟨true, some T⟩ ∧ Sub (.cell k) T

inductive RRes where
  | ok (v : Val) (own : Bool) (m : Mem)
  | panic

/-- A3.6: what a read of a module global of type `t` finds: a share of a
    block of that type — a lock share of a lock block, or an `arc` share of
    the block whose payload it carries (`ArcBlk`: an `arc` block, or a view, a
    read guard a `make` handed back, which the model's `arc` type does not
    tell from an `Arc`). -/
def GlobFits (B : Nat → Option Blk) (t : Ty) (v : Val) : Prop :=
  (∃ u k o, t = .lk u ∧ v = .lk k ∧ B k = some ⟨u, .lock, o⟩) ∨
  (∃ u k p, t = .arc u ∧ v = .arc k p ∧ ArcBlk (B k) u p)

inductive EvalR (m : Mem) : Rhs → RRes → Prop
  | expr {e : Expr} {n : Nat} : Eval m e n → EvalR m (.expr e) (.ok (.int n) false m)
  | new {t : Ty} :
      EvalR m (.new t)
        (.ok (.node t m.nid (m.nid + 1) []) true
          { m with alloc := upd (upd m.alloc m.nid true) (m.nid + 1) true, nid := m.nid + 2 })
  | moveOwn {y : Var} {v : Val} :
      m.st y = some ⟨true, some v⟩ → EvalR m (.var y) (.ok v true (m.set y ⟨true, none⟩))
  | copy {y : Var} {v : Val} :
      m.st y = some ⟨false, some v⟩ → EvalR m (.var y) (.ok v false m)
  | borrowOwn {y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st y = some ⟨true, some (.node t c d es)⟩ → EvalR m (.borrow y) (.ok (.href c) false m)
  | borrowBor {y : Var} {v : Val} :
      m.st y = some ⟨false, some v⟩ → EvalR m (.borrow y) (.ok v false m)
  | at {y : Var} {i : Expr} {t : Ty} {c d n : Nat} {es : List Val} (h : n < es.length) :
      VecOf m y t c d es → Eval m i n → EvalR m (.at y i) (.ok (lendOf es[n]) false m)
  | atOOB {y : Var} {i : Expr} {t : Ty} {c d n : Nat} {es : List Val} :
      VecOf m y t c d es → Eval m i n → es.length ≤ n → EvalR m (.at y i) .panic
  | view {y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      VecOf m y t c d es → EvalR m (.view y) (.ok (.view d 0 es.length) false m)
  | sat {y : Var} {i : Expr} {t : Ty} {d o l n c : Nat} {es : List Val} (h : o + n < es.length) :
      m.st y = some ⟨false, some (.view d o l)⟩ → Eval m i n → n < l →
      m.alloc d = true → DataAt m d (.node t c d es) →
      EvalR m (.sat y i) (.ok (lendOf es[o + n]) false m)
  | satOOB {y : Var} {i : Expr} {d o l n : Nat} :
      m.st y = some ⟨false, some (.view d o l)⟩ → Eval m i n → l ≤ n → EvalR m (.sat y i) .panic
  | pop {y : Var} {t : Ty} {c d : Nat} {es : List Val} {e : Val} :
      m.st y = some ⟨true, some (.node t c d (es ++ [e]))⟩ → m.alloc c = true → m.alloc d = true →
      EvalR m (.pop y) (.ok e e.owns (m.set y ⟨true, some (.node t c d es)⟩))
  | popEmpty {y : Var} {t : Ty} {c d : Nat} :
      m.st y = some ⟨true, some (.node t c d [])⟩ → EvalR m (.pop y) .panic
  /-- A2-drop.3b: element 0 moves out (the drain's step, in index order). -/
  | popFront {y : Var} {t : Ty} {c d : Nat} {es : List Val} {e : Val} :
      m.st y = some ⟨true, some (.node t c d (e :: es))⟩ → m.alloc c = true → m.alloc d = true →
      EvalR m (.popFront y) (.ok e e.owns (m.set y ⟨true, some (.node t c d es)⟩))
  | popFrontEmpty {y : Var} {t : Ty} {c d : Nat} :
      m.st y = some ⟨true, some (.node t c d [])⟩ → EvalR m (.popFront y) .panic
  | pair {y z : Var} {v w : Val} {m1 m2 : Mem} :
      TakeVal m y v m1 → TakeVal m1 z w m2 → EvalR m (.pair y z) (.ok (.pair v w) true m2)
  | fst {y : Var} {o : Bool} {v w : Val} :
      m.st y = some ⟨o, some (.pair v w)⟩ → EvalR m (.fst y) (.ok (lendOf v) false m)
  | snd {y : Var} {o : Bool} {v w : Val} :
      m.st y = some ⟨o, some (.pair v w)⟩ → EvalR m (.snd y) (.ok (lendOf w) false m)
  | inl {y : Var} {b : Ty} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → EvalR m (.inl y b) (.ok (.inl v) true m1)
  | inr {a : Ty} {y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → EvalR m (.inr a y) (.ok (.inr v) true m1)
  | getl {y : Var} {o : Bool} {v : Val} :
      m.st y = some ⟨o, some (.inl v)⟩ → EvalR m (.getl y) (.ok (lendOf v) false m)
  | getlP {y : Var} {o : Bool} {v : Val} :
      m.st y = some ⟨o, some (.inr v)⟩ → EvalR m (.getl y) .panic
  | getr {y : Var} {o : Bool} {v : Val} :
      m.st y = some ⟨o, some (.inr v)⟩ → EvalR m (.getr y) (.ok (lendOf v) false m)
  | getrP {y : Var} {o : Bool} {v : Val} :
      m.st y = some ⟨o, some (.inl v)⟩ → EvalR m (.getr y) .panic
  | takel {y : Var} {v : Val} :
      m.st y = some ⟨true, some (.inl v)⟩ → EvalR m (.takel y) (.ok v v.owns (m.set y ⟨true, none⟩))
  | takelP {y : Var} {v : Val} :
      m.st y = some ⟨true, some (.inr v)⟩ → EvalR m (.takel y) .panic
  | taker {y : Var} {v : Val} :
      m.st y = some ⟨true, some (.inr v)⟩ → EvalR m (.taker y) (.ok v v.owns (m.set y ⟨true, none⟩))
  | takerP {y : Var} {v : Val} :
      m.st y = some ⟨true, some (.inl v)⟩ → EvalR m (.taker y) .panic
  | pack {fs : List Nat} {te : Ty} {ms : List Nat} {y : Var} {cs : List (Var × PMode × Ty)} {v : Val}
      {m1 : Mem} :
      TakeVal m y v m1 → EvalR m (.pack fs te ms y cs) (.ok (.pkg fs te ms v cs) true m1)
  /-- A3.1: a new block holds the value taken from `y`; its key is taken
      from `nid` (a key, never an address), and the result is its one share.
      The count is ghost (the number of shares), so nothing stores it. -/
  | arcNew {t : Ty} {y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → m1.blk m1.nid = none →
      EvalR m (.arcNew t y)
        (.ok (.arc m1.nid v) true
          { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .arc, some v⟩) })
  /-- A3.1: a read of the share `a` (owned or lent) makes a new share of its
      block. -/
  | arcClone {a : Var} {o : Bool} {k : Nat} {p : Val} :
      m.st a = some ⟨o, some (.arc k p)⟩ → EvalR m (.arcClone a) (.ok (.arc k p) true m)
  /-- A3.1: the payload of the block the share `a` names, lent. -/
  | arcGet {a : Var} {o : Bool} {k : Nat} {p : Val} {bl : Blk} :
      m.st a = some ⟨o, some (.arc k p)⟩ → m.blk k = some bl →
      EvalR m (.arcGet a) (.ok (lendOf bl.rd) false m)
  /-- A3.2: a new lock block holds the value taken from `y`, at a key taken
      from `nid`; the result is its one share. -/
  | lockNew {t : Ty} {y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → m1.blk m1.nid = none → SendCheck m1.blk [v] m1.st →
      EvalR m (.lockNew t y)
        (.ok (.lk m1.nid) true
          { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) })
  /-- A3.5's second cut: ... and when the value fails the crossing check (a
      slot left behind holds a share of a cell it holds), `locked_new` panics,
      the store as it was, as `mem_send_check` does. -/
  | lockNewFail {t : Ty} {y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → ¬ SendCheck m1.blk [v] m1.st → EvalR m (.lockNew t y) .panic
  /-- A3.2: a read of the lock share `a` (owned or lent) makes a new share
      of its block. -/
  | lockClone {a : Var} {o : Bool} {k : Nat} :
      m.st a = some ⟨o, some (.lk k)⟩ → EvalR m (.lockClone a) (.ok (.lk k) true m)
  /-- A3.5: a library handle's constructor: a new lock block holds the value
      taken from `y`, at a key taken from `nid`; the result is its one cell
      share. -/
  | cellNew {t : Ty} {y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → m1.blk m1.nid = none → SendCheck m1.blk [v] m1.st →
      EvalR m (.cellNew t y)
        (.ok (.cell m1.nid) true
          { m1 with nid := m1.nid + 1, blk := upd m1.blk m1.nid (some ⟨t, .lock, some v⟩) })
  /-- ... and panics when the state fails the crossing check (A3.5's second
      cut: a cell's state is a lock's payload). -/
  | cellNewFail {t : Ty} {y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → ¬ SendCheck m1.blk [v] m1.st → EvalR m (.cellNew t y) .panic
  /-- A3.5: a copy of the cell share `a` holds: a new share of its block.
      A3.5's third cut: `a` may be a borrow, and the copy is a new owner on the
      thread an owner of the cell is on (`OwnedCell`: a live borrow's owner
      is in the store, `MInv.cell_owned`, so a typed copy always steps). -/
  | cellClone {a : Var} {o : Bool} {k : Nat} :
      m.st a = some ⟨o, some (.cell k)⟩ → OwnedCell m k → EvalR m (.cellClone a) (.ok (.cell k) true m)
  /-- A3.4: an `Atomic`'s operation: one step on the word, the integer
      payload of the lock block `a` shares; the answer is an integer.  (A
      lock block of an integer whose payload a `withLock` has checked out
      has no step: the thread waits, `RBlocked`.  A source `Atomic` is never
      checked out.) -/
  | atomic {op : AOp} {a : Var} {e1 e2 : Expr} {o : Bool} {k n n1 n2 : Nat} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨.int, .lock, some (.int n)⟩ →
      Eval m e1 n1 → Eval m e2 n2 → ¬ HasView m.blk k →
      EvalR m (.atomic op a e1 e2)
        (.ok (.int (op.run n n1 n2).1) false
          { m with blk := upd m.blk k (some ⟨.int, .lock, some (.int (op.run n n1 n2).2)⟩) })
  /-- A3.4: `chan_send a y` on the channel `a` shares, a lock block whose
      payload is its queue (a `Vec`) and its closed flag: the value taken
      from `y` (an owner's tree moves, an integer is copied, as `vec_push`
      takes it) goes to the back of the open queue, and the answer is 1.  The
      queue's buffer is not moved: nothing views it. -/
  | chanSend {a y : Var} {o : Bool} {k : Nat} {t u : Ty} {c d : Nat} {es : List Val} {v : Val}
      {m1 : Mem} :
      m.st a = some ⟨o, some (.lk k)⟩ → TakeVal m y v m1 →
      m1.blk k = some ⟨t, .lock, some (.pair (.node u c d es) (.int 0))⟩ →
      m1.alloc c = true → m1.alloc d = true → ¬ HasView m1.blk k → SendCheck m1.blk [v] m1.st →
      EvalR m (.chanSend a y)
        (.ok (.int 1) false
          { m1 with blk := upd m1.blk k (some ⟨t, .lock, some (.pair (.node u c d (es ++ [v])) (.int 0))⟩) })
  /-- ... on a closed channel the value is dropped, and the answer is 0. -/
  | chanSendClosed {a y : Var} {o : Bool} {k : Nat} {t : Ty} {q : Val} {f : Nat} {v : Val} {m1 : Mem}
      {a' : Nat → Bool} :
      m.st a = some ⟨o, some (.lk k)⟩ → TakeVal m y v m1 →
      m1.blk k = some ⟨t, .lock, some (.pair q (.int (f + 1)))⟩ → Frees m1.alloc v a' →
      SendCheck m1.blk [v] m1.st →
      EvalR m (.chanSend a y) (.ok (.int 0) false { m1 with alloc := a' })
  /-- A3.5's second cut: a value that fails the crossing check is not sent:
      `chan_send` panics, before it looks at the channel, the store as it was. -/
  | chanSendFail {a y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → ¬ SendCheck m1.blk [v] m1.st → EvalR m (.chanSend a y) .panic
  /-- A3.4: `chan_recv` / `chan_try_recv` on the channel `a` shares, a lock
      block whose payload is its queue (a `Vec`, taken from the front) and
      its closed flag: the head moves out of the queue, an owned `some`.
      (Its payload checked out by a `withLock`, or, for `chan_recv`, its
      queue empty and open, the channel has no step: the thread waits,
      `RBlocked`.) -/
  | chanRecv {w : Bool} {a : Var} {o : Bool} {k : Nat} {t u : Ty} {c d f : Nat} {v : Val}
      {es : List Val} :
      m.st a = some ⟨o, some (.lk k)⟩ →
      m.blk k = some ⟨t, .lock, some (.pair (.node u c d (v :: es)) (.int f))⟩ →
      m.alloc c = true → m.alloc d = true → ¬ HasView m.blk k → RecvCheck v es →
      EvalR m (.chanRecv w a)
        (.ok (.inr v) true { m with blk := upd m.blk k (some ⟨t, .lock, some (.pair (.node u c d es) (.int f))⟩) })
  /-- A3.5's second cut: a head that shares a cell with an element left in the
      queue is not received: the receive panics, the store as it was
      (`RecvCheck`: a state the runtime's channels never reach). -/
  | chanRecvFail {w : Bool} {a : Var} {o : Bool} {k : Nat} {t u : Ty} {c d f : Nat} {v : Val}
      {es : List Val} :
      m.st a = some ⟨o, some (.lk k)⟩ →
      m.blk k = some ⟨t, .lock, some (.pair (.node u c d (v :: es)) (.int f))⟩ → ¬ RecvCheck v es →
      EvalR m (.chanRecv w a) .panic
  /-- ... `none` when the queue is empty and the flag set, or
      (`chan_try_recv`) just empty. -/
  | chanRecvNone {w : Bool} {a : Var} {o : Bool} {k : Nat} {t u : Ty} {c d f : Nat} :
      m.st a = some ⟨o, some (.lk k)⟩ →
      m.blk k = some ⟨t, .lock, some (.pair (.node u c d []) (.int f))⟩ → m.alloc c = true →
      (w = false ∨ f ≠ 0) → EvalR m (.chanRecv w a) (.ok (.inl (.int 0)) true m)
  /-- A3.4: `chan_close`: the flag is set; the queue stays, for receivers to
      drain. -/
  | chanClose {a : Var} {o : Bool} {k : Nat} {t : Ty} {q : Val} {f : Nat} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, some (.pair q (.int f))⟩ →
      ¬ HasView m.blk k →
      EvalR m (.chanClose a)
        (.ok (.int 0) false { m with blk := upd m.blk k (some ⟨t, .lock, some (.pair q (.int 1))⟩) })
  /-- A3.3: `rw_read a` on the lock block `a` shares (an `RwLocked`), with its
      payload in (no writer has it checked out): a new view of the block, at a
      key taken from `nid`, whose payload is a share of the block and the
      block's payload; the answer is the view's one share, the read guard.
      (A block whose payload is checked out has no step: the reader waits,
      `RBlocked`.)  A view owns nothing; the sweep removes it once nothing
      reaches it, which ends the read. -/
  | rwRead {a : Var} {o : Bool} {k : Nat} {t : Ty} {p : Val} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, some p⟩ → m.blk m.nid = none →
      EvalR m (.rwRead a)
        (.ok (.arc m.nid (.pair (.lk k) p)) true
          { m with nid := m.nid + 1,
                   blk := upd m.blk m.nid (some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩) })
  /-- A3.3: `rw_try_read a`: as `rw_read`, a new view of the block's payload
      and its share, the read guard, here handed back as an owned `some`
      (`inr`) ... -/
  | rwTryRead {a : Var} {o : Bool} {k : Nat} {t : Ty} {p : Val} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, some p⟩ → m.blk m.nid = none →
      EvalR m (.rwTryRead a)
        (.ok (.inr (.arc m.nid (.pair (.lk k) p))) true
          { m with nid := m.nid + 1,
                   blk := upd m.blk m.nid (some ⟨.prod (.lk t) t, .view, some (.pair (.lk k) p)⟩) })
  /-- ... and `none` (`inl 0`), the store as it was, where `rw_read` waits (a
      writer has the payload checked out): `pthread_rwlock_tryrdlock`'s
      `EBUSY`, no wait. -/
  | rwTryReadNone {a : Var} {o : Bool} {k : Nat} {t : Ty} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, none⟩ →
      EvalR m (.rwTryRead a) (.ok (.inl (.int 0)) true m)
  /-- A3.3: `rw_try_write a`'s answer, the store as it was: `some` (`inr 0`)
      when a write's check-out of the block would not wait (its payload is in
      and no view of it lives) ... -/
  | rwTryWrite {a : Var} {o : Bool} {k : Nat} {t : Ty} {p : Val} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, some p⟩ → ¬ HasView m.blk k →
      EvalR m (.rwTryWrite a) (.ok (.inr (.int 0)) true m)
  /-- ... and `none` (`inl 0`) where it would wait (the payload out, or a
      reader's view living): `pthread_rwlock_trywrlock`'s `EBUSY`, no wait. -/
  | rwTryWriteNone {a : Var} {o : Bool} {k : Nat} :
      m.st a = some ⟨o, some (.lk k)⟩ → ((∃ t, m.blk k = some ⟨t, .lock, none⟩) ∨ HasView m.blk k) →
      EvalR m (.rwTryWrite a) (.ok (.inl (.int 0)) true m)
  /-- A3.6: a read of the module global `g`: a new share of its block, as
      `lockClone` / `arcClone` make one from a binding's.  The store holds the
      global's share (`Mem.gl`), which no step writes. -/
  | glob {g : Nat} {t : Ty} {v : Val} :
      m.gl g = some v → GlobFits m.blk t v → EvalR m (.glob g t) (.ok v true m)
  /-- ... and a read of a global the store does not hold at that type panics.
      (A program the checker accepts reads each global at its declared type,
      and A3's configuration holds every global, whose block it keeps; A2's
      one thread, run from the empty store, holds none.) -/
  | globP {g : Nat} {t : Ty} :
      (¬ ∃ v, m.gl g = some v ∧ GlobFits m.blk t v) → EvalR m (.glob g t) .panic
  /-- A3.2's second cut: `locked_take a`: the payload of the lock block `a`
      shares moves out to the caller, owned (an integer is a plain integer, as
      `withLock` checks one out), and the block holds nothing, as `locked_take`
      leaves zero bytes in the slot and sets `taken`.  With the payload out
      (or a view of it living) it has no step: the thread waits (`RBlocked`),
      as every operation on a taken `Locked` does. -/
  | lockTake {a : Var} {o : Bool} {k : Nat} {t : Ty} {v : Val} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, some v⟩ → ¬ HasView m.blk k →
      EvalR m (.lockTake a) (.ok v v.owns { m with blk := upd m.blk k (some ⟨t, .lock, none⟩) })
  /-- ... `locked_restore a y`: the value taken from `y` (an owner's tree
      moves, an integer is copied) goes back into the block, whose payload is
      out; the answer is 0. -/
  | lockRestore {a y : Var} {o : Bool} {k : Nat} {t : Ty} {v : Val} {m1 : Mem} :
      m.st a = some ⟨o, some (.lk k)⟩ → TakeVal m y v m1 → m1.blk k = some ⟨t, .lock, none⟩ →
      SendCheck m1.blk [v] m1.st →
      EvalR m (.lockRestore a y)
        (.ok (.int 0) false { m1 with blk := upd m1.blk k (some ⟨t, .lock, some v⟩) })
  /-- A3.5's second cut: ... a value that fails the crossing check is not
      restored: `locked_restore` panics, before it takes the lock, the store
      as it was. -/
  | lockRestoreFail {a y : Var} {v : Val} {m1 : Mem} :
      TakeVal m y v m1 → ¬ SendCheck m1.blk [v] m1.st → EvalR m (.lockRestore a y) .panic
  /-- ... and with the payload in, it panics ("the value was not taken"),
      the store as it was. -/
  | lockRestoreP {a y : Var} {o : Bool} {k : Nat} {t : Ty} {p : Val} :
      m.st a = some ⟨o, some (.lk k)⟩ → m.blk k = some ⟨t, .lock, some p⟩ →
      EvalR m (.lockRestore a y) .panic

/-! ### Calls

A call runs the callee's body in the caller's store, its variables renamed
apart: variable `v` of the callee becomes `base + v`, except an `inout`
parameter, which becomes the caller's own binding — the callee writes the
caller's storage, as passing by address does. -/

def Expr.rename (ρ : Var → Var) : Expr → Expr
  | .lit n => .lit n
  | .var x => .var (ρ x)
  | .add a b => .add (a.rename ρ) (b.rename ρ)
  | .lt a b => .lt (a.rename ρ) (b.rename ρ)
  | .len x => .len (ρ x)
  | .slen x => .slen (ρ x)
  | .isl x => .isl (ρ x)

def Rhs.rename (ρ : Var → Var) : Rhs → Rhs
  | .expr e => .expr (e.rename ρ)
  | .new t => .new t
  | .var y => .var (ρ y)
  | .borrow y => .borrow (ρ y)
  | .at y i => .at (ρ y) (i.rename ρ)
  | .view y => .view (ρ y)
  | .sat y i => .sat (ρ y) (i.rename ρ)
  | .pop y => .pop (ρ y)
  | .popFront y => .popFront (ρ y)
  | .pair y z => .pair (ρ y) (ρ z)
  | .fst y => .fst (ρ y)
  | .snd y => .snd (ρ y)
  | .inl y b => .inl (ρ y) b
  | .inr a y => .inr a (ρ y)
  | .getl y => .getl (ρ y)
  | .getr y => .getr (ρ y)
  | .takel y => .takel (ρ y)
  | .taker y => .taker (ρ y)
  | .pack fs te ms y cs => .pack fs te ms (ρ y) (cs.map (fun c => (ρ c.1, c.2)))
  | .arcNew t y => .arcNew t (ρ y)
  | .arcClone a => .arcClone (ρ a)
  | .arcGet a => .arcGet (ρ a)
  | .lockNew t y => .lockNew t (ρ y)
  | .lockClone a => .lockClone (ρ a)
  | .atomic op a e1 e2 => .atomic op (ρ a) (e1.rename ρ) (e2.rename ρ)
  | .chanSend a y => .chanSend (ρ a) (ρ y)
  | .chanRecv w a => .chanRecv w (ρ a)
  | .chanClose a => .chanClose (ρ a)
  | .rwRead a => .rwRead (ρ a)
  | .rwTryRead a => .rwTryRead (ρ a)
  | .rwTryWrite a => .rwTryWrite (ρ a)
  | .cellNew t y => .cellNew t (ρ y)
  | .cellClone a => .cellClone (ρ a)
  | .glob g t => .glob g t
  | .lockTake a => .lockTake (ρ a)
  | .lockRestore a y => .lockRestore (ρ a) (ρ y)

def Edit.rename (ρ : Var → Var) : Edit → Edit
  | .push y => .push (ρ y)
  | .trunc i => .trunc (i.rename ρ)
  | .set i y => .set (i.rename ρ) (ρ y)

def Stmt.rename (ρ : Var → Var) : Stmt → Stmt
  | .skip => .skip
  | .seq a b => .seq (a.rename ρ) (b.rename ρ)
  | .letv x r s => .letv (ρ x) (r.rename ρ) (s.rename ρ)
  | .letcall x f args s => .letcall (ρ x) f (args.map ρ) (s.rename ρ)
  | .assign x r => .assign (ρ x) (r.rename ρ)
  | .ite c a b => .ite (c.rename ρ) (a.rename ρ) (b.rename ρ)
  | .while c s => .while (c.rename ρ) (s.rename ρ)
  | .push x y => .push (ρ x) (ρ y)
  | .free x => .free (ρ x)
  | .scope x s => .scope (ρ x) (s.rename ρ)
  | .rbind p s => .rbind (ρ p) (s.rename ρ)
  | .frozen z s => .frozen (z.map ρ) (s.rename ρ)
  | .panic => .panic
  | .letrec x f s => .letrec (ρ x) f (s.rename ρ)
  | .catchR x m0 s => .catchR (ρ x) m0 (s.rename ρ)
  | .unpair y x z s => .unpair (ρ y) (ρ x) (ρ z) (s.rename ρ)
  | .callc x c j zs s => .callc (ρ x) (ρ c) j (zs.map ρ) (s.rename ρ)
  | .letd x f r s => .letd (ρ x) f (r.rename ρ) (s.rename ρ)
  | .scopeD x f s => .scopeD (ρ x) f (s.rename ρ)
  | .edit b x op => .edit b (ρ x) (op.rename ρ)
  | .withLock a x s => .withLock (ρ a) (ρ x) (s.rename ρ)
  | .scopeL k t x s => .scopeL k t (ρ x) (s.rename ρ)
  | .insert x i y => .insert (ρ x) (i.rename ρ) (ρ y)
  | .withElem v i x s => .withElem (ρ v) (i.rename ρ) (ρ x) (s.rename ρ)
  | .callcE x c j zs s => .callcE (ρ x) (ρ c) j (zs.map ρ) (s.rename ρ)

/-- The renaming of a call of a function with parameters `ps` on `args`,
    its variables placed from `base`. -/
def callRen (ps : List (PMode × Ty)) (args : List Var) (base : Nat) (v : Var) : Var :=
  match ps[v]? with
  | some (.inout _, _) => args.getD v 0
  | _ => base + v

/-- The variables passed to `inout` parameters. -/
def inoutArgs (ps : List (PMode × Ty)) (args : List Var) : List Var :=
  ((List.range ps.length).filter (fun i => match ps[i]? with
      | some (.inout _, _) => true
      | _ => false)).map (fun i => args.getD i 0)

/-- A borrowed argument: an owner lends its handles, a borrow is copied. -/
def lendSlot : Slot → Option Val
  | ⟨true, some v⟩ => some (lendOf v)
  | ⟨false, some v⟩ => some v
  | _ => none

/-- Binding the parameters, from index `i` on. -/
inductive BindParams : Mem → List (PMode × Ty) → List Var → Nat → Nat → Mem → Prop
  | nil {m : Mem} {base i : Nat} : BindParams m [] [] base i m
  | inp {m m' : Mem} {t : Ty} {ps : List (PMode × Ty)} {a : Var} {as : List Var}
      {base i : Nat} {sl : Slot} {v : Val} :
      m.st a = some sl → lendSlot sl = some v →
      BindParams (m.set (base + i) ⟨false, some v⟩) ps as base (i + 1) m' →
      BindParams m ((.inp, t) :: ps) (a :: as) base i m'
  | sink {m m' : Mem} {t : Ty} {ps : List (PMode × Ty)} {a : Var} {as : List Var}
      {base i : Nat} {v : Val} :
      m.st a = some ⟨true, some v⟩ →
      BindParams ((m.set a ⟨true, none⟩).set (base + i) ⟨true, some v⟩) ps as base (i + 1) m' →
      BindParams m ((.sink, t) :: ps) (a :: as) base i m'
  | inout {m m' : Mem} {b : Eff} {t : Ty} {ps : List (PMode × Ty)} {a : Var} {as : List Var}
      {base i : Nat} :
      BindParams m ps as base (i + 1) m' →
      BindParams m ((.inout b, t) :: ps) (a :: as) base i m'

/-- The callee's body inside its parameters' scopes: an `in` parameter is a
    borrow bound for the call, a `sink` parameter an owner it drops. -/
def wrapParams : List (PMode × Ty) → Nat → Nat → Stmt → Stmt
  | [], _, _, s => s
  | (.inp, _) :: ps, base, i, s => .rbind (base + i) (wrapParams ps base (i + 1) s)
  | (.sink, _) :: ps, base, i, s => .scope (base + i) (wrapParams ps base (i + 1) s)
  | (.inout _, _) :: ps, base, i, s => wrapParams ps base (i + 1) s

/-- The frame of a call's result slot `r` around the call's inside.  An
    owned result of a destructor type is a destructor frame's from the start
    (`scopeD`): once the callee has set it, a panic in the callee (a later
    statement, one of its own bindings' destructors) stops at the frame,
    which runs the result's destructor before the panic goes on; on the
    normal path the result has moved to the caller's binding by the frame's
    end, which then runs nothing (`Step.scopeDMoved`).  An owned result that
    is a `Vec` of destructor values is one too: its frame drains it on such a
    panic (`Step.scopeDPDrain`).  Any other result's is a plain scope. -/
def resFrame (fn : Fn) (r : Var) (s : Stmt) : Stmt :=
  match fn.resOwn, fn.resTy with
  | true, .dtor g _ => .scopeD r g s
  | true, .vec (.dtor g _) => .scopeD r g s
  | _, _ => .scope r s

/-- The inside of a call: the result slot `r = base + n` is bound (in its
    frame, `resFrame`: a destructor frame's for a destructor result), the body
    runs with every caller binding but the `inout` arguments lent out
    (`frozen`: a bound, which typing may narrow — the bindings the closures
    handed to the call may change are not lent), and the result moves to
    the caller's binding `x`. -/
def callIn (fn : Fn) (args : List Var) (base : Nat) (x : Var) : Stmt :=
  let n := fn.params.length
  let r := base + n
  let ρ := callRen fn.params args base
  let z := (List.range base).filter (fun v => !(inoutArgs fn.params args).contains v)
  resFrame fn r (.seq (.frozen z (wrapParams fn.params base 0 (fn.body.rename ρ))) (.assign x (.var r)))

/-- What a call becomes: `x` is bound for the continuation `k`, after the
    call's inside. -/
def callStmt (fn : Fn) (args : List Var) (base : Nat) (x : Var) (k : Stmt) : Stmt :=
  .scope x (.seq (callIn fn args base x) k)

/-- What `recover f` becomes: a call of `f`, which takes no parameters and
    returns an integer, inside a `recover` frame that remembers the caller's
    store `m0`.  On a panic, the frames inside are unwound — each scope drops
    what it owns, as the allocation journal does (§7.2) — and `x` says the
    call failed. -/
def recStmt (fn : Fn) (base : Nat) (x : Var) (m0 : Mem) (k : Stmt) : Stmt :=
  .scope x (.seq (.catchR x m0 (callIn fn [] base x)) k)

/-- The arguments a call moves or changes (its `sink` and `inout` ones). -/
def movedArgs (ps : List (PMode × Ty)) (args : List Var) : List Var :=
  ((List.range ps.length).filter (fun i => match ps[i]? with
      | some (.inp, _) => false
      | _ => true)).map (fun i => args.getD i 0)

/-- What a call through a package holds still (at most): every caller
    binding but the result's and the arguments it moves or changes. -/
def heldFor (ps : List (PMode × Ty)) (args : List Var) (base x : Nat) : List Var :=
  (List.range base).filter (fun v => v != x && !(movedArgs ps args).contains v)

/-- Opening a package for a call: its environment, lent, is bound to the
    first fresh variable. -/
def envMem (m : Mem) (env : Val) : Mem :=
  { m.set m.nv ⟨false, some (lendOf env)⟩ with nv := m.nv + 1 }

/-- A2-envhand: the store a hand-over leaves.  The package `c` is moved out
    (its slot owns nothing), its environment `env` is owned by the first
    fresh variable, and the call's result binding `x` is bound, unset (`o`:
    whether the result is owned).  The next fresh variable is the inner
    call's result, so two are taken. -/
def handMem (m : Mem) (c x : Var) (env : Val) (o : Bool) : Mem :=
  { ((m.set c ⟨true, none⟩).set m.nv ⟨true, some env⟩).set x ⟨o, none⟩ with nv := m.nv + 2 }

/-- A2-envhand: what a hand-over runs, in `x`'s scope: in the scope of the
    environment's binding `y`, the code `f` is called as an ordinary call,
    with `y` as its receiver, an `inout` argument (its result in `y + 1`,
    moved to `x`); then the environment goes back into `c`, a package of the
    same code and interfaces again; then the continuation `k`. -/
def handStmt (x c : Var) (f : Nat) (zs : List Var) (fs : List Nat) (te : Ty) (ms : List Nat) (y : Var)
    (k : Stmt) : Stmt :=
  .scope x (.seq (.scope y (.seq (.letcall (y + 1) f (y :: zs) (.assign x (.var (y + 1))))
    (.assign c (.pack fs te ms y [])))) k)

/-- A step's outcome: a configuration, or a panic — with the store the
    unwinding left. -/
inductive Res where
  | ok (m : Mem) (s : Stmt)
  | panic (m : Mem)

/-- The memory a step leaves. -/
def Res.mem : Res → Mem
  | .ok m _ => m
  | .panic m => m

/-- A3.4: a right-hand side that waits: an atomic operation on an integer
    lock block whose payload a `withLock` has checked out; a channel
    operation on one too, or a `chan_recv` on an empty, open queue.  A3.3:
    or one that would change a lock block a view of which lives, or a
    `rw_read` of a block a writer has checked out. -/
def RBlocked (m : Mem) : Rhs → Prop
  | .atomic _ a _ _ => ∃ o k, m.st a = some ⟨o, some (.lk k)⟩ ∧
      (m.blk k = some ⟨.int, .lock, none⟩ ∨ HasView m.blk k)
  | .chanSend a _ => ∃ o k t, m.st a = some ⟨o, some (.lk k)⟩ ∧
      (m.blk k = some ⟨t, .lock, none⟩ ∨ HasView m.blk k)
  | .chanRecv w a => ∃ o k t, m.st a = some ⟨o, some (.lk k)⟩ ∧
      (m.blk k = some ⟨t, .lock, none⟩ ∨
        (w = true ∧ ∃ u c d, m.blk k = some ⟨t, .lock, some (.pair (.node u c d []) (.int 0))⟩) ∨
        HasView m.blk k)
  | .chanClose a => ∃ o k t, m.st a = some ⟨o, some (.lk k)⟩ ∧
      (m.blk k = some ⟨t, .lock, none⟩ ∨ HasView m.blk k)
  | .rwRead a => ∃ o k t, m.st a = some ⟨o, some (.lk k)⟩ ∧ m.blk k = some ⟨t, .lock, none⟩
  -- A3.2's second cut: a take waits while the payload is out or read
  | .lockTake a => ∃ o k t, m.st a = some ⟨o, some (.lk k)⟩ ∧
      (m.blk k = some ⟨t, .lock, none⟩ ∨ HasView m.blk k)
  | _ => False

/-- A3.2/A3.5: `a` holds a share of the lock block `k`: a lock share, or a
    cell share (a library handle's state, which a `withCell` checks out as a
    `withLock` does a lock's). -/
def LockAt (m : Mem) (a : Var) (k : Nat) : Prop :=
  ∃ o, m.st a = some ⟨o, some (.lk k)⟩ ∨ m.st a = some ⟨o, some (.cell k)⟩

/-- `LockAt` reads the slots only. -/
theorem LockAt.of_st {m m' : Mem} (hst : m'.st = m.st) {a : Var} {k : Nat} (h : LockAt m a k) :
    LockAt m' a k := by
  obtain ⟨o, h⟩ := h
  exact ⟨o, by rw [hst]; exact h⟩

/-- A3.3: a statement whose next step waits, itself (`Blocked` looks
    through the scopes around one): a `withLock` of a lock a writer has
    checked out or a reader views, or a binding or an assignment whose
    right-hand side waits. -/
def Waits (m : Mem) : Stmt → Prop
  | .withLock a _ _ => ∃ k t, LockAt m a k ∧
      (m.blk k = some ⟨t, .lock, none⟩ ∨ HasView m.blk k)
  | .letv _ r _ => RBlocked m r
  | .assign _ r => RBlocked m r
  | .letd _ _ r _ => RBlocked m r
  | _ => False

inductive Step (P : Prog) : Mem → Stmt → Res → Prop
  | seqSkip {m : Mem} {b : Stmt} : Step P m (.seq .skip b) (.ok m b)
  | seqL {m m' : Mem} {a a' b : Stmt} :
      Step P m a (.ok m' a') → Step P m (.seq a b) (.ok m' (.seq a' b))
  | seqP {m m' : Mem} {a b : Stmt} : Step P m a (.panic m') → Step P m (.seq a b) (.panic m')
  | letv {m m' : Mem} {x : Var} {r : Rhs} {s : Stmt} {v : Val} {o : Bool} :
      m.st x = none → EvalR m r (.ok v o m') →
      Step P m (.letv x r s) (.ok (m'.set x ⟨o, some v⟩) (.scope x s))
  | letvP {m : Mem} {x : Var} {r : Rhs} {s : Stmt} :
      EvalR m r .panic → Step P m (.letv x r s) (.panic m)
  | letcall {m m' : Mem} {x : Var} {f : Nat} {args : List Var} {s : Stmt} {fn : Fn} :
      P[f]? = some fn → m.st x = none →
      BindParams m fn.params args m.nv 0 m' →
      Step P m (.letcall x f args s)
        (.ok ({ (m'.set x ⟨fn.resOwn, none⟩).set (m.nv + fn.params.length) ⟨fn.resOwn, none⟩
                with nv := m.nv + fn.nvars })
             (callStmt fn args m.nv x s))
  | scopeSkip {m : Mem} {x : Var} {sl : Slot} {a' : Nat → Bool} :
      m.st x = some sl → DropSlot m.alloc sl a' →
      Step P m (.scope x .skip) (.ok ({ m with alloc := a' }.remove x) .skip)
  | scopeIn {m m' : Mem} {x : Var} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.scope x s) (.ok m' (.scope x s'))
  | scopeP {m m1 : Mem} {x : Var} {s : Stmt} {sl : Slot} {a' : Nat → Bool} :
      Step P m s (.panic m1) → m1.st x = some sl → DropSlot m1.alloc sl a' →
      Step P m (.scope x s) (.panic ({ m1 with alloc := a' }.remove x))
  | rbindSkip {m : Mem} {p : Var} {w : Option Val} :
      m.st p = some ⟨false, w⟩ → Step P m (.rbind p .skip) (.ok (m.remove p) .skip)
  | rbindIn {m m' : Mem} {p : Var} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.rbind p s) (.ok m' (.rbind p s'))
  | rbindP {m m1 : Mem} {p : Var} {s : Stmt} {w : Option Val} :
      Step P m s (.panic m1) → m1.st p = some ⟨false, w⟩ → Step P m (.rbind p s) (.panic (m1.remove p))
  | frozenSkip {m : Mem} {z : List Var} : Step P m (.frozen z .skip) (.ok m .skip)
  | frozenIn {m m' : Mem} {z : List Var} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.frozen z s) (.ok m' (.frozen z s'))
  | frozenP {m m1 : Mem} {z : List Var} {s : Stmt} :
      Step P m s (.panic m1) → Step P m (.frozen z s) (.panic m1)
  | assign {m m1 : Mem} {x : Var} {r : Rhs} {v : Val} {o : Bool} {sl : Slot} {a' : Nat → Bool} :
      (m.st x).isSome → EvalR m r (.ok v o m1) → m1.st x = some sl → DropSlot m1.alloc sl a' →
      Step P m (.assign x r) (.ok ({ m1 with alloc := a' }.set x ⟨o, some v⟩) .skip)
  | assignP {m : Mem} {x : Var} {r : Rhs} :
      EvalR m r .panic → Step P m (.assign x r) (.panic m)
  | iteT {m : Mem} {c : Expr} {a b : Stmt} {n : Nat} :
      Eval m c n → n ≠ 0 → Step P m (.ite c a b) (.ok m a)
  | iteF {m : Mem} {c : Expr} {a b : Stmt} :
      Eval m c 0 → Step P m (.ite c a b) (.ok m b)
  | while {m : Mem} {c : Expr} {s : Stmt} :
      Step P m (.while c s) (.ok m (.ite c (.seq s (.while c s)) .skip))
  | push {m m1 : Mem} {x y : Var} {v : Val} {t : Ty} {c d : Nat} {es : List Val} :
      TakeVal m y v m1 → m1.st x = some ⟨true, some (.node t c d es)⟩ →
      m1.alloc c = true → m1.alloc d = true →
      Step P m (.push x y) (.ok (m1.set x ⟨true, some (.node t c d (es ++ [v]))⟩) .skip)
  | pushRealloc {m m1 : Mem} {x y : Var} {v : Val} {t : Ty} {c d : Nat} {es : List Val} :
      TakeVal m y v m1 → m1.st x = some ⟨true, some (.node t c d es)⟩ →
      m1.alloc c = true → m1.alloc d = true →
      Step P m (.push x y)
        (.ok ({ m1 with alloc := upd (upd m1.alloc d false) m1.nid true, nid := m1.nid + 1 }.set x
                ⟨true, some (.node t c m1.nid (es ++ [v]))⟩) .skip)
  -- A2-thru (Agora #295): a change of a `Vec`'s elements made through any
  -- binding that names it rewrites its node where it lies in its owner's tree.
  | editPush {m m1 : Mem} {b : Bool} {x y o : Var} {v T T' : Val} {t : Ty} {c d : Nat}
      {es : List Val} :
      TakeVal m y v m1 → NodeOf m1 x o T t c d es →
      Repl (.node t c d es) (.node t c d (es ++ [v])) T T' →
      Step P m (.edit b x (.push y)) (.ok (m1.set o ⟨true, some T'⟩) .skip)
  | editPushRealloc {m m1 : Mem} {b : Bool} {x y o : Var} {v T T' : Val} {t : Ty} {c d : Nat}
      {es : List Val} :
      TakeVal m y v m1 → NodeOf m1 x o T t c d es →
      Repl (.node t c d es) (.node t c m1.nid (es ++ [v])) T T' →
      Step P m (.edit b x (.push y))
        (.ok ({ m1 with alloc := upd (upd m1.alloc d false) m1.nid true, nid := m1.nid + 1 }.set o
                ⟨true, some T'⟩) .skip)
  | editTrunc {m : Mem} {b : Bool} {x o : Var} {i : Expr} {n : Nat} {T T' : Val} {t : Ty}
      {c d : Nat} {es : List Val} {a' : Nat → Bool} :
      Eval m i n → NodeOf m x o T t c d es → FreesL m.alloc (es.drop n) a' →
      Repl (.node t c d es) (.node t c d (es.take n)) T T' →
      Step P m (.edit b x (.trunc i)) (.ok ({ m with alloc := a' }.set o ⟨true, some T'⟩) .skip)
  /-- `vec_set`: the `n`-th element is replaced by the value taken from `y`,
      the old one freed ... -/
  | editSet {m m1 : Mem} {b : Bool} {x y o : Var} {i : Expr} {n : Nat} {v T T' : Val} {t : Ty}
      {c d : Nat} {es : List Val} {a' : Nat → Bool} (h : n < es.length) :
      Eval m i n → TakeVal m y v m1 → NodeOf m1 x o T t c d es → Frees m1.alloc es[n] a' →
      Repl (.node t c d es) (.node t c d (es.set n v)) T T' →
      Step P m (.edit b x (.set i y)) (.ok ({ m1 with alloc := a' }.set o ⟨true, some T'⟩) .skip)
  /-- ... and out of range nothing is stored: the value is freed. -/
  | editSetOOB {m m1 : Mem} {b : Bool} {x y o : Var} {i : Expr} {n : Nat} {v T : Val} {t : Ty}
      {c d : Nat} {es : List Val} {a' : Nat → Bool} :
      Eval m i n → TakeVal m y v m1 → NodeOf m1 x o T t c d es → es.length ≤ n →
      Frees m1.alloc v a' → Step P m (.edit b x (.set i y)) (.ok { m1 with alloc := a' } .skip)
  /-- A2-elem (Agora #391): `y`'s value, taken as `vec_push` takes it, goes
      into `x`'s elements at index `n` (at the end if there are fewer): the
      give-back of an element handed over (`withElem`).  The buffer does not
      move: the runtime wrote the element in place. -/
  | insert {m m1 : Mem} {x y : Var} {i : Expr} {n : Nat} {v : Val} {t : Ty} {c d : Nat}
      {es : List Val} :
      Eval m i n → TakeVal m y v m1 → m1.st x = some ⟨true, some (.node t c d es)⟩ →
      m1.alloc c = true → m1.alloc d = true →
      Step P m (.insert x i y) (.ok (m1.set x ⟨true, some (.node t c d (es.take n ++ v :: es.drop n))⟩) .skip)
  /-- A2-elem (Agora #391): an element handed over.  Element `n` of the `Vec`
      `v` owns moves out into `x` (an owner moves in, an integer is a plain
      integer binding, as `vec_pop` takes it), and the body runs in `x`'s
      scope; after it, `x`'s value goes back in at index `n` (`insert`), and
      the scope ends.  The runtime passes a pointer to the element in place;
      `StmtT.withElem`'s premises make the two agree.  A panic in the body
      drops `x`'s value with the scope, as everything the unwinding leaves
      is dropped: `v`'s too, before anything reads it. -/
  | withElem {m : Mem} {v x : Var} {i : Expr} {s : Stmt} {t : Ty} {c d n : Nat} {es : List Val}
      (h : n < es.length) :
      m.st v = some ⟨true, some (.node t c d es)⟩ → m.alloc c = true → m.alloc d = true →
      Eval m i n → m.st x = none →
      Step P m (.withElem v i x s)
        (.ok ((m.set v ⟨true, some (.node t c d (es.take n ++ es.drop (n + 1)))⟩).set x
            ⟨es[n].owns, some es[n]⟩)
          (.scope x (.seq s (.insert v (.lit n) x))))
  /-- ... and out of range it panics, as `vec_at` does. -/
  | withElemOOB {m : Mem} {v x : Var} {i : Expr} {s : Stmt} {t : Ty} {c d n : Nat} {es : List Val} :
      m.st v = some ⟨true, some (.node t c d es)⟩ → m.alloc c = true → Eval m i n → es.length ≤ n →
      Step P m (.withElem v i x s) (.panic m)
  | free {m : Mem} {x : Var} {t : Val} {a' : Nat → Bool} :
      m.st x = some ⟨true, some t⟩ → Frees m.alloc t a' →
      Step P m (.free x) (.ok ({ m with alloc := a' }.set x ⟨true, none⟩) .skip)
  | panic {m : Mem} : Step P m .panic (.panic m)
  /-- A3.3: a thread that waits may panic instead, the store as it was: the
      runtime's panic on a lock its holder would wait for itself (writing
      an `RwLocked` it reads or writes, reading one it writes), and a
      relock's detection in general (Agora #455).  An over-approximation:
      a run may panic where it would wait. -/
  | waitPanic {m : Mem} {s : Stmt} : Waits m s → Step P m s (.panic m)
  | letrec {m : Mem} {x : Var} {f : Nat} {s : Stmt} {fn : Fn} :
      P[f]? = some fn → fn.params = [] → m.st x = none →
      Step P m (.letrec x f s)
        (.ok ({ (m.set x ⟨fn.resOwn, none⟩).set (m.nv + fn.params.length) ⟨fn.resOwn, none⟩
                with nv := m.nv + fn.nvars })
             (recStmt fn m.nv x (m.set x ⟨fn.resOwn, none⟩) s))
  | catchIn {m m' : Mem} {x : Var} {m0 : Mem} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.catchR x m0 s) (.ok m' (.catchR x m0 s'))
  | catchSkip {m : Mem} {x : Var} {m0 : Mem} : Step P m (.catchR x m0 .skip) (.ok m .skip)
  | unpair {m : Mem} {y x z : Var} {s : Stmt} {v w : Val} :
      m.st y = some ⟨true, some (.pair v w)⟩ → m.st x = none → m.st z = none → x ≠ z →
      Step P m (.unpair y x z s)
        (.ok (((m.set y ⟨true, none⟩).set x ⟨v.owns, some v⟩).set z ⟨w.owns, some w⟩)
          (.scope x (.scope z s)))
  | callc {m m1 : Mem} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt} {o : Bool} {fs : List Nat}
      {te : Ty} {ms : List Nat} {env : Val} {cs : List (Var × PMode × Ty)} {f : Nat} {fn : Fn} :
      m.st c = some ⟨o, some (.pkg fs te ms env cs)⟩ → fs[j]? = some f → P[f]? = some fn →
      m.st x = none →
      BindParams (envMem m env) fn.params (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) 0 m1 →
      Step P m (.callc x c j zs k)
        (.ok ({ (m1.set x ⟨fn.resOwn, none⟩).set (m.nv + 1 + fn.params.length) ⟨fn.resOwn, none⟩
                with nv := m.nv + 1 + fn.nvars })
             (.scope x (.seq (.frozen (heldFor fn.params (m.nv :: zs ++ cs.map (·.1)) m.nv x)
               (.rbind m.nv (callIn fn (m.nv :: zs ++ cs.map (·.1)) (m.nv + 1) x))) k)))
  /-- A2-envhand: a call through an owned package of a method whose interface
      takes the receiver `inout`.  The environment is handed over: it moves
      out of the package `c` (whose slot owns nothing for the call) into a
      fresh binding, which the code `f` takes as its `inout` receiver in an
      ordinary call, and it goes back into `c` after, as a package of the same
      code and interfaces (`handStmt`).  The runtime passes the code a pointer
      to the environment in place; `StmtT.callcE`'s premises make the two
      agree.  A panic in the code drops the environment with its binding's
      scope, as `withElem` drops an element: the runtime's journal drops it
      with the closure's binding (docs/MEMORY.md §7.2), and the frames a
      panic unwinds to a `recover` include the one that binds `c` (`recover`
      calls a function of no parameters), so `c` is never read again either
      way.  A package that captures by name has no such method
      (`Implements`). -/
  | callcE {m : Mem} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt} {fs : List Nat} {te : Ty}
      {ms : List Nat} {env : Val} {f : Nat} {fn : Fn} :
      m.st c = some ⟨true, some (.pkg fs te ms env [])⟩ → fs[j]? = some f → P[f]? = some fn →
      m.st x = none →
      Step P m (.callcE x c j zs k) (.ok (handMem m c x env fn.resOwn) (handStmt x c f zs fs te ms m.nv k))
  | catchP {m m1 : Mem} {x : Var} {m0 : Mem} {s : Stmt} :
      Step P m s (.panic m1) → (m1.st x).isSome →
      Step P m (.catchR x m0 s) (.ok (m1.set x ⟨false, some (.int 1)⟩) .skip)
  -- A2-drop: a binding whose type has a destructor (`% Drop`).
  | letd {m m' : Mem} {x : Var} {f : Nat} {r : Rhs} {s : Stmt} {v : Val} {o : Bool} :
      m.st x = none → EvalR m r (.ok v o m') →
      Step P m (.letd x f r s) (.ok (m'.set x ⟨o, some v⟩) (.scopeD x f s))
  | letdP {m : Mem} {x : Var} {f : Nat} {r : Rhs} {s : Stmt} :
      EvalR m r .panic → Step P m (.letd x f r s) (.panic m)
  | scopeDIn {m m' : Mem} {x : Var} {f : Nat} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.scopeD x f s) (.ok m' (.scopeD x f s'))
  /-- The scope's end with `x` owning its value, a struct or an enum (no
      `Vec`'s node): the destructor is called on `x` (its result in a fresh
      variable), then `x`'s scope ends.  A destructor that takes `x` lent leaves
      the tree for `scope x` to free; a struct's glue takes `x` owned, so the
      call moves the value in and it takes it apart (Agora #616, `GlueOK`; after
      the struct's own impl, `ImplGlueOK`). -/
  | scopeDEnd {m : Mem} {x : Var} {f : Nat} {v : Val} :
      m.st x = some ⟨true, some v⟩ → v.isNode = false →
      Step P m (.scopeD x f .skip) (.ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip)))
  /-- A moved binding runs no destructor. -/
  | scopeDMoved {m : Mem} {x : Var} {f : Nat} :
      m.st x = some ⟨true, none⟩ → Step P m (.scopeD x f .skip) (.ok (m.remove x) .skip)
  /-- A2-drop.3b, the drain: the scope's end with `x` owning a `Vec` of
      destructor values that still has an element.  Element 0 moves out to a
      fresh binding of its own (`vec_remove x 0`, in `letd`'s step), whose
      scope runs its destructor and frees it; then the frame is at its end
      again, one element shorter.  nurlc drops a `Vec`'s elements in index
      order (`nurl__vec_drop_elems`). -/
  | scopeDDrain {m : Mem} {x : Var} {f : Nat} {t : Ty} {c d : Nat} {e : Val} {es : List Val} :
      m.st x = some ⟨true, some (.node t c d (e :: es))⟩ →
      Step P m (.scopeD x f .skip)
        (.ok { m with nv := m.nv + 1 } (.scopeD x f (.letd m.nv f (.popFront x) .skip)))
  /-- ... and with every element gone: the empty `Vec` is freed, as any
      binding's value is at its scope's end. -/
  | scopeDEmpty {m : Mem} {x : Var} {f : Nat} {t : Ty} {c d : Nat} :
      m.st x = some ⟨true, some (.node t c d [])⟩ →
      Step P m (.scopeD x f .skip) (.ok m (.scope x .skip))
  /-- A panic stops at the frame: the destructor runs, `x` is freed, and the
      panic goes on. The frame is gone, so a panic in the destructor does not
      run it again, and `scope x` still frees the fields (of a value its
      destructor took lent; a glue has them in frames of their own). -/
  | scopeDP {m m1 : Mem} {x : Var} {f : Nat} {s : Stmt} {v : Val} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, some v⟩ → v.isNode = false →
      Step P m (.scopeD x f s)
        (.ok { m1 with nv := m1.nv + 1 } (.seq (.scope x (.letcall m1.nv f [x] .skip)) .panic))
  /-- A2-drop.3b: a panic stops at the frame of a `Vec` of destructor values
      too: the frame drains what the `Vec` still holds (each element's
      destructor runs, in index order), then the panic goes on.  A panic in
      an element's destructor comes back here through the drain's own frame,
      which goes on with the elements after it: each destructor once, as the
      journal runs bindings' (the runtime's element loop does not go on yet,
      Agora #608; `CLAIM.md`). -/
  | scopeDPDrain {m m1 : Mem} {x : Var} {f : Nat} {s : Stmt} {t : Ty} {c d : Nat} {es : List Val} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, some (.node t c d es)⟩ →
      Step P m (.scopeD x f s) (.ok m1 (.seq (.scopeD x f .skip) .panic))
  | scopeDPMoved {m m1 : Mem} {x : Var} {f : Nat} {s : Stmt} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, none⟩ →
      Step P m (.scopeD x f s) (.panic (m1.remove x))
  /-- A3.2: taking the lock `a` shares: its block's payload is checked out
      to `x` (an owner moves in, an integer is a plain integer binding, as
      `unpair` binds a field), and the body runs in `x`'s lock scope.  A
      block whose payload is checked out has no step: the thread waits
      (`Blocked`).  A3.5: so does a cell's, through a cell share
      (`withCell`). -/
  | withLock {m : Mem} {a x : Var} {s : Stmt} {k : Nat} {t : Ty} {v : Val} :
      LockAt m a k → m.blk k = some ⟨t, .lock, some v⟩ → m.st x = none →
      ¬ HasView m.blk k →
      Step P m (.withLock a x s)
        (.ok ({ m with blk := upd m.blk k (some ⟨t, .lock, none⟩) }.set x ⟨v.owns, some v⟩)
          (.scopeL k t x s))
  | scopeLIn {m m' : Mem} {k : Nat} {t : Ty} {x : Var} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.scopeL k t x s) (.ok m' (.scopeL k t x s'))
  /-- The lock scope's end gives the payload back (`Release`), when it passes
      the crossing check (A3.5's second cut) ... -/
  | scopeLSkip {m m' : Mem} {k : Nat} {t : Ty} {x : Var} :
      Release m k t x m' → (∀ sl, m.st x = some sl → GiveCheck m x sl) →
      Step P m (.scopeL k t x .skip) (.ok m' .skip)
  /-- ... and when it fails it (the body kept a copy of a handle the value
      holds, or stored into it one kept outside), the end panics with the
      lock held, as `locked_with` / `locked_update` do: the panic is put in
      the scope, as `TStep.spawnFail` puts one before its call, and its
      unwinding drops `x` (`Release.drop`), the block left checked out. -/
  | scopeLFail {m : Mem} {k : Nat} {t : Ty} {x : Var} {sl : Slot} :
      m.st x = some sl → ¬ GiveCheck m x sl →
      Step P m (.scopeL k t x .skip) (.ok m (.scopeL k t x .panic))
  /-- A3.3: so does a panic unwinding through it, as `RwLocked`'s write
      guard's drop does on the drop journal (docs/MEMORY.md §7.2): the lock
      is released, and other threads may take it or read it.  (`Locked`'s
      `locked_with` leaves the lock held on a panic: for it the model
      over-approximates, letting other threads go on where the runtime's
      wait.) -/
  | scopeLP {m m1 m2 : Mem} {k : Nat} {t : Ty} {x : Var} {s : Stmt} :
      Step P m s (.panic m1) → Release m1 k t x m2 → Step P m (.scopeL k t x s) (.panic m2)

/-- Reachability: A3.1, every step ends with the sweep, which frees the
    blocks no slot reaches (`Mem.sweep`). -/
inductive Steps (P : Prog) : Mem → Stmt → Res → Prop
  | refl {m : Mem} {s : Stmt} : Steps P m s (.ok m s)
  | step {m m' : Mem} {s s' : Stmt} {r : Res} :
      Step P m s (.ok m' s') → Steps P m'.sweep s' r → Steps P m s r
  | panic {m m' : Mem} {s : Stmt} : Step P m s (.panic m') → Steps P m s (.panic m'.sweep)

/-- Steps with no sweep: one thread's, in A3, where the sweep is the
    configuration's (the blocks every thread reaches stay). -/
inductive Steps0 (P : Prog) : Mem → Stmt → Res → Prop
  | refl {m : Mem} {s : Stmt} : Steps0 P m s (.ok m s)
  | step {m m' : Mem} {s s' : Stmt} {r : Res} :
      Step P m s (.ok m' s') → Steps0 P m' s' r → Steps0 P m s r
  | panic {m m' : Mem} {s : Stmt} : Step P m s (.panic m') → Steps0 P m s (.panic m')

/-- A3.2: the next step takes a lock whose payload is checked out: the
    thread waits for it to come back.  (Whether it ever does is deadlock
    freedom, which is not claimed.)  A3.4: or a right-hand side waits
    (`RBlocked`). -/
def Blocked (m : Mem) : Stmt → Prop
  | .withLock a _ _ => ∃ k t, LockAt m a k ∧
      (m.blk k = some ⟨t, .lock, none⟩ ∨ HasView m.blk k)
  | .letv _ r _ => RBlocked m r
  | .assign _ r => RBlocked m r
  | .letd _ _ r _ => RBlocked m r
  | .seq a _ => Blocked m a
  | .scope _ s => Blocked m s
  | .rbind _ s => Blocked m s
  | .frozen _ s => Blocked m s
  | .catchR _ _ s => Blocked m s
  | .scopeD _ _ s => Blocked m s
  | .scopeL _ _ _ s => Blocked m s
  | _ => False

/-- A configuration that is neither finished nor able to step, nor (A3.2)
    waiting for a lock: the program is about to touch memory it may not. -/
def Stuck (P : Prog) (m : Mem) (s : Stmt) : Prop :=
  s ≠ .skip ∧ ¬ Blocked m s ∧ ∀ r, ¬ Step P m s r

end A2
