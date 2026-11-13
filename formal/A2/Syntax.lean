/-
  A2 — the core calculus of NURL's ownership model: syntax.

  The calculus keeps exactly what docs/MEMORY.md §1–§2 reason about in
  single-threaded code without panics: owned `Vec`s whose buffers move when
  they grow (§2.10), moves and drop flags (§2.1, §7.6), borrows and views
  (§2.2, §2.10, §6.2), and the three parameter conventions `in`, `inout`
  and `sink` (§1).  A `String` is a `Vec` of bytes and `string_data` is a
  view of it, so strings need no constructs of their own.
-/

namespace A2

/-- Variables (bindings).  A function's own variables are renamed apart
    from its caller's when it is called (`Semantics.lean`). -/
abbrev Var := Nat

/-- A3.5b: what a closure's type says its environment may hold, and so where
    the closure may cross (docs/MEMORY.md §6.5).  The environment's type is
    not part of a closure's type, so the type carries this instead; `pack`
    gives it from the captures' type (`Cross.Fits`), and a call through the
    closure does not read it.  The four are ordered, each holding less, and a
    closure may be taken at a class above its own (`Cross.Le`, `RhsT.moveUp`):

  * `any`  — anything: views, and bindings captured by name (what A2's
             closures are);
  * `send` — no view and no binding by name: an owned environment that
             depends on nothing of the thread that made it, so the closure
             may move to another thread (Send; a cell share in it crosses
             only by the crossing check, `SendCheck`): a spawn's argument,
             and (A3.5's second cut) a lock's payload or a channel's
             element, every value going into which faces the check;
  * `sync` — also no cell share (a library handle is not Sync), so several
             threads may hold it at once: an `Arc`'s payload.  Its code
             changes nothing it captured: a call through it hands its code
             the environment lent (`Implements`: `inp`, and no change through
             a borrow), and the one call whose code changes the environment
             (A2-envhand, `StmtT.callcE`: handed over) types only at `send`
             or `any`, through an owner; what else it may change is a binding
             captured by name, which `send` already excludes;
  * `bare` — also no share at all.  A3.1's first cut asked it of a
             slice's element (`Ty.ok (slice t)`); since A3.2's second cut a
             lock or a channel no longer needs it, and since A3.1's slices of
             shares a slice does not either: no rule asks for it now. -/
inductive Cross where
  | any
  | send
  | sync
  | bare
  | dropd  -- Agora #609: the environment may hold destructor values; it holds no views and no
           -- cell shares (as `sync`'s), and crosses nowhere: no subsumption reaches it
           -- (`Cross.Le`), and what crosses owns no destructor value
deriving DecidableEq, Repr

/-- The environment may hold views and bindings by name. -/
@[simp] def Cross.views : Cross → Bool
  | .any => true
  | _ => false

/-- The environment may hold a cell share (a library handle). -/
@[simp] def Cross.cells : Cross → Bool
  | .any => true
  | .send => true
  | _ => false

/-- The environment may hold a share (an `Arc`, a lock, a cell). -/
@[simp] def Cross.shares : Cross → Bool
  | .bare => false
  | _ => true

/-- Agora #609: the environment may hold destructor values: the closure's
    drop runs code (its drop method), so it is a destructor value itself. -/
@[simp] def Cross.drops : Cross → Bool
  | .dropd => true
  | _ => false

/-- Types.  `vec t` is an owned, growable buffer of `t` (a `Vec`, or a
    `String` when `t` is a byte).  `slice t` is a view of such a buffer
    (`slice_from_vec`, `string_data`, a raw `s` that does not own its
    text). -/
inductive Ty where
  | int
  | vec (t : Ty)
  | slice (t : Ty)
  | prod (a b : Ty)   -- a struct value: its fields, nested in pairs (inline, no allocation)
  | sum (a b : Ty)    -- an enum value: one of two payloads, tagged (inline); `Option t` is `sum int t`
  | fn (ms : List Nat) (q : Cross)
                        -- a closure or a trait object: code with an environment it owns; method `j`
                        -- has the interface `ms[j]` (a function of the program whose first parameter
                        -- is the receiver); the environment's type is not part of the type, what it
                        -- may hold is (A3.5b: `q`, where the closure may cross)
  | arc (t : Ty)      -- A3.1: a share of a counted block whose payload, a `t`, is frozen
  | lk (t : Ty)       -- A3.2: a share of a lock block (`Locked`) whose payload is a `t`
  | cell (t : Ty)     -- A3.5: a share of a library handle's state (a `PNCounter`, a `TcpConn`, a
                      -- `Cell`): a lock block whose payload, a `t`, the library changes in place
                      -- through any share; Send, not Sync
  | dtor (f : Nat) (t : Ty)  -- A2-drop.3: a `t` whose drop first runs the program's function `f`
                             -- (its `% Drop`, DtorOK); the destructor is on the type, so every
                             -- drop of such a value runs it, wherever the value went
deriving DecidableEq, Repr

/-- Does a value of this type hold views (so that storing one into a
    container makes the container depend on what is viewed)? -/
def Ty.holdsView : Ty → Bool
  | .int => false
  | .vec t => t.holdsView
  | .slice _ => true
  | .prod a b => a.holdsView || b.holdsView
  | .sum a b => a.holdsView || b.holdsView
  | .fn _ q => q.views  -- what the environment holds is not part of the type; A3.5b: what
                         -- it may hold is
  | .arc t => t.holdsView
  | .lk t => t.holdsView
  | .cell t => t.holdsView
  | .dtor _ t => t.holdsView

/-- May a value of this type hold a closure that holds bindings by name (or
    views)?  A3.5b: a Send closure (`fn ms q`, `q` not `any`) holds neither, so
    a value of a type that answers `false` may still hold one. -/
def Ty.hasFn : Ty → Bool
  | .int => false
  | .vec t => t.hasFn
  | .slice t => t.hasFn
  | .prod a b => a.hasFn || b.hasFn
  | .sum a b => a.hasFn || b.hasFn
  | .fn _ q => q.views
  | .arc t => t.hasFn
  | .lk t => t.hasFn
  | .cell t => t.hasFn
  | .dtor _ t => t.hasFn

/-- A3.1: may a value of this type hold a share (an `Arc`)?  A closure's
    environment may, unless its type says it holds none (A3.5b: `bare`). -/
def Ty.hasArc : Ty → Bool
  | .int => false
  | .vec t => t.hasArc
  | .slice t => t.hasArc
  | .prod a b => a.hasArc || b.hasArc
  | .sum a b => a.hasArc || b.hasArc
  | .fn _ q => q.shares
  | .arc _ => true
  | .lk _ => true
  | .cell _ => true
  | .dtor _ t => t.hasArc

/-- A3.5: may a value of this type hold a cell share (a library handle whose
    copies are one state)?  A closure's environment may, unless its type says
    it holds none (A3.5b: `sync`, `bare`).  This is the Sync question: such a
    handle is not Sync, so no `Arc` payload holds one.  A3.5's second cut: a
    lock share answers `false` whatever its payload holds.  A lock's payload
    is the lock's, reached by one thread at a time, and every value going
    into it faces the crossing check, so `Locked T` is Sync when `T` is Send
    (docs/MEMORY.md §6.5: a Sync marker vouches for the container, and its
    value faces the Send question, h358). -/
def Ty.hasCell : Ty → Bool
  | .int => false
  | .vec t => t.hasCell
  | .slice t => t.hasCell
  | .prod a b => a.hasCell || b.hasCell
  | .sum a b => a.hasCell || b.hasCell
  | .fn _ q => q.cells
  | .arc t => t.hasCell
  | .lk _ => false
  | .cell _ => true
  | .dtor _ t => t.hasCell

/-- A2-drop.3: the type under every destructor wrapper; a destructor
    type's values are those of the type it wraps. -/
def Ty.undtor : Ty → Ty
  | .dtor _ t => t.undtor
  | t => t

theorem Ty.undtor_ne (τ : Ty) (f : Nat) (t : Ty) : τ.undtor ≠ .dtor f t := by
  induction τ with
  | dtor _ _ ih => exact ih
  | _ => intro h; cases h

@[simp] theorem Ty.undtor_dtor (f : Nat) (t : Ty) : (Ty.dtor f t).undtor = t.undtor := rfl

/-- A3.4, Agora #755: `τ` is a channel share of `s`: a lock share whose
    payload is the queue and the closed flag, `prod (vec s) int`, or that
    struct under a destructor type of its own (`Ty.dtor g (prod (vec s)
    int)`, `g` its glue: nurlc's `ChImpl A`, a struct whose drop glue drops
    the queue), the form a channel of destructor values takes (a lock's
    payload is no struct holding a drained `Vec` with no glue, `Ty.lkPay`). -/
def Ty.ChanOf (τ s : Ty) : Prop := ∃ t, τ = .lk t ∧ t.undtor = .prod (.vec s) .int

theorem Ty.chanOf_plain (s : Ty) : (Ty.lk (.prod (.vec s) .int)).ChanOf s := ⟨_, rfl, rfl⟩

/-- Agora #755: a type of a channel's payload's shape (`prod (vec s) int`). -/
def Ty.isChan : Ty → Bool
  | .prod (.vec _) .int => true
  | _ => false

theorem Ty.holdsView_undtor (τ : Ty) : τ.undtor.holdsView = τ.holdsView := by
  induction τ with
  | dtor _ _ ih => exact ih
  | _ => rfl

/-- A type that holds no share holds no cell share. -/
theorem Ty.hasCell_of_hasArc {t : Ty} (h : t.hasArc = false) : t.hasCell = false := by
  induction t with
  | int => rfl
  | vec t ih => exact ih h
  | slice t ih => exact ih h
  | prod a b iha ihb =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at h
    simp [Ty.hasCell, iha h.1, ihb h.2]
  | sum a b iha ihb =>
    simp only [Ty.hasArc, Bool.or_eq_false_iff] at h
    simp [Ty.hasCell, iha h.1, ihb h.2]
  | fn _ q => cases q <;> first | rfl | cases h
  | arc _ _ => cases h
  | lk _ _ => cases h
  | cell _ _ => cases h
  | dtor _ t ih => exact ih h

/-- A3.6: does a value of this type synchronise itself, so that a module
    global set at start may hold it and every thread reach it?  A lock share
    does (`Locked`, `RwLocked`, `Mutex`, `Atomic` and `Channel` are all
    `lk _`), and so does an `Arc` whose payload holds no library handle (a
    cell share is not Sync, A3.5).  A cell share does not, nor does an owned
    tree (a `Vec` pushed from two threads through a global races: h263). -/
def Ty.sync : Ty → Bool
  | .lk _ => true
  | .arc t => !t.hasCell
  | _ => false

/-- A2-drop.3: a struct or an enum, what `% Drop` is on, or (Agora #609) a
    closure of the dropping class (a destructor type wraps one of these). -/
def Ty.isStruct : Ty → Bool
  | .prod _ _ => true
  | .sum _ _ => true
  | .fn _ q => q.drops   -- Agora #609: a closure whose drop runs code (its drop method)
  | _ => false

/-- A2-drop.3a: a value of this type runs a destructor when it is dropped:
    the type is, at its top, a destructor type.  (A struct holding one in a
    field runs it inside its drop glue, `Ty.holdsDtor`.) -/
def Ty.hasDtor : Ty → Bool
  | .dtor _ _ => true
  | _ => false

/-- A2-drop.3a: a value of this type, dropped whole, owns a destructor
    value: it is one (`hasDtor`), or a struct or an enum holding one in a
    field or a payload at any depth (A2-drop.3b: a destructor value two
    levels down, in a struct that is no destructor type of its own, is one
    too; and a `Vec` of them, which `Ty.ok` admits as a binding's own type,
    drained at its end, `Step.scopeDDrain`, or as a field or a payload,
    Agora #607).  Such a struct runs its
    fields' destructors in its drop glue, so it is bound as a destructor
    type itself, its glue its destructor (`letd`, which binds the `Vec`
    too): `letv` and `assign` take no owned value of such a type. -/
def Ty.holdsDtor : Ty → Bool
  | .dtor _ _ => true
  | .prod a b => a.holdsDtor || b.holdsDtor
  | .sum a b => a.holdsDtor || b.holdsDtor
  | .vec t => t.holdsDtor
  | .fn _ q => q.drops   -- Agora #609: a closure whose environment may hold one
  | _ => false

theorem Ty.hasDtor_of_holdsDtor {t : Ty} (h : t.holdsDtor = false) : t.hasDtor = false := by
  cases t <;> simp_all [Ty.holdsDtor, Ty.hasDtor]

@[simp] theorem Ty.hasDtor_dtor (f : Nat) (t : Ty) : (Ty.dtor f t).hasDtor = true := rfl

/-- A module global's type (`Ty.sync`: a lock or an `Arc` share) is no
    destructor type. -/
theorem Ty.hasDtor_of_sync {t : Ty} (h : t.sync = true) : t.hasDtor = false := by
  cases t <;> simp_all [Ty.sync, Ty.hasDtor]

theorem Ty.holdsDtor_of_sync {t : Ty} (h : t.sync = true) : t.holdsDtor = false := by
  cases t <;> simp_all [Ty.sync, Ty.holdsDtor]

theorem Ty.hasDtor_of_isStruct {t : Ty} (h : t.isStruct = true) : t.hasDtor = false := by
  cases t <;> simp_all [Ty.isStruct, Ty.hasDtor]

/-- A2-drop.3b: a value of this type owns no destructor value in its
    tree.  A view owns nothing; a share's payload lives in its block, not in
    the tree of what holds the share (A2-drop.3d), and a closure's
    environment holds none (A2-drop.3c, `Cross.Fits`) unless the closure is
    of the dropping class, which is a destructor value itself (Agora #609). -/
def Ty.dtorFree : Ty → Bool
  | .dtor _ _ => false
  | .vec t => t.dtorFree
  | .prod a b => a.dtorFree && b.dtorFree
  | .sum a b => a.dtorFree && b.dtorFree
  | .fn _ q => !q.drops
  | _ => true

/-- A2-drop.3b's drain: a `Vec` whose elements hold a destructor value
    (`.vec (.dtor f u)`, or since Agora #607 `.vec (Ty.nest n (.dtor f u))`,
    `Ty.dnest`). It is a binding's own type, or (`Ty.ok` admits it too as a
    struct's field or an enum's payload, which the struct's or the enum's
    glue hands to a `letd`, and as another such `Vec`'s element or a view's
    element, Agora #607, and (Agora #755) as an `Arc`'s, a lock's or a
    cell's payload, which the reap of the orphaned block hands to a
    destructor frame at its own type, `Step.reap`; a lock's check-out
    binding of one is given no other value, `StmtT.withLock`'s `hna`, and
    goes back into the block.  A channel's queue of them is a struct's field
    under the struct's glue, `Ty.ChanOf`). -/
def Ty.vecD : Ty → Bool
  | .vec t => !t.dtorFree
  | _ => false

@[simp] theorem Ty.vecD_int : Ty.int.vecD = false := rfl
@[simp] theorem Ty.vecD_vec (t : Ty) : (Ty.vec t).vecD = !t.dtorFree := rfl
@[simp] theorem Ty.vecD_slice (t : Ty) : (Ty.slice t).vecD = false := rfl
@[simp] theorem Ty.vecD_prod (a b : Ty) : (Ty.prod a b).vecD = false := rfl
@[simp] theorem Ty.vecD_sum (a b : Ty) : (Ty.sum a b).vecD = false := rfl
@[simp] theorem Ty.vecD_fn (ms : List Nat) (q : Cross) : (Ty.fn ms q).vecD = false := rfl
@[simp] theorem Ty.vecD_arc (t : Ty) : (Ty.arc t).vecD = false := rfl
@[simp] theorem Ty.vecD_lk (t : Ty) : (Ty.lk t).vecD = false := rfl
@[simp] theorem Ty.vecD_cell (t : Ty) : (Ty.cell t).vecD = false := rfl
@[simp] theorem Ty.vecD_dtor (f : Nat) (t : Ty) : (Ty.dtor f t).vecD = false := rfl

/-- Agora #607: the types a drained `Vec`'s elements may be: a destructor
    type, or a `Vec` of them in turn (a `Vec (Vec D)`, drained element by
    element, each inner `Vec` by a `letd` frame of its own). -/
def Ty.dnest : Ty → Bool
  | .dtor _ _ => true
  | .vec t => t.dnest
  | _ => false

/-- `n` `Vec`s around `u`: `Ty.nest 0 u = u`, `Ty.nest (n+1) u = vec (nest n u)`. -/
def Ty.nest : Nat → Ty → Ty
  | 0, u => u
  | n + 1, u => .vec (Ty.nest n u)

@[simp] theorem Ty.nest_zero (u : Ty) : Ty.nest 0 u = u := rfl
@[simp] theorem Ty.nest_succ (n : Nat) (u : Ty) : Ty.nest (n + 1) u = .vec (Ty.nest n u) := rfl
@[simp] theorem Ty.dnest_dtor (f : Nat) (t : Ty) : (Ty.dtor f t).dnest = true := rfl
@[simp] theorem Ty.dnest_vec (t : Ty) : (Ty.vec t).dnest = t.dnest := rfl

/-- A2-drop.3a: the destructor such a value runs reads views: a binding of
    this type must keep what its value views alive to its end (`Entry.arm`).
    Agora #782: so must one of a drained `Vec` of such values (`Ty.dnest`),
    whose elements' destructors read them where its frame drains it. -/
def Ty.dtorViews (t : Ty) : Bool := t.dnest && t.holdsView

@[simp] theorem Ty.dtorViews_dtor (f : Nat) (t : Ty) : (Ty.dtor f t).dtorViews = t.holdsView := by
  simp [Ty.dtorViews, Ty.holdsView]

@[simp] theorem Ty.dtorViews_vec (t : Ty) : (Ty.vec t).dtorViews = t.dtorViews := by
  simp [Ty.dtorViews, Ty.holdsView]

/-- Agora #755 (`Locked D`): what a lock's or a cell's payload may own of
    destructor values: none, or it is one at its top (a `% Drop` struct or
    enum, or one with glue: `Ty.dtor f u`), or (`Locked (Vec D)`) a drained
    `Vec` of them at any depth (`Ty.dnest`, which contains the destructor
    type itself), that holds no cell share.  The cell rule keeps the reap's
    no-cell premise true of every value of the type, so an orphaned block of
    it is always reaped, at its own type (a `Vec` drained by the reap's
    frame).  Agora #803: it may hold `arc` and lock shares (nurlc's `Locked
    Conn`, `% Drop Conn` holding an `Arc Pool`), so its give-back's crossing
    check (`GiveCheck`) can fail (the value reaches a read guard); the value
    then goes to a destructor frame on the unwinding (`Step.scopeLPD`), never
    to the code-less drop (`Release.drop`).  Until Agora #803 it asked
    `!t.hasArc`, which kept that check unfailable. -/
def Ty.lkPay (t : Ty) : Bool := t.dtorFree || (t.dnest && !t.hasCell)

/-- Agora #804 (`RwLocked D`): a read guard's view type, `prod (lk u) u`: a
    share of the lock block and its payload, which the view reads in place
    and owns none of (`Blk.tree_view`: a view's tree is empty, so no sweep
    frees anything of it, and it is never an orphan to be, `Cand`).  Its
    payload `u` is a lock's (`Ty.lkPay`) that holds no cell share (the Sync
    question, A3.5).  The read guard, an `arc` share of the view, is of type
    `arc (prod (lk u) u)`, which `Ty.ok` admits by this disjunct even where
    `u` is a destructor value; `arc_new` asks its own `dtorFree ∨ dnest` of
    what moves in, so no `arc` block is ever of this type
    (`Blk.DtorOK.arc`). -/
def Ty.rview : Ty → Bool
  | .prod (.lk u) u' => decide (u = u') && u.lkPay && !u.hasCell
  | _ => false

/-- A read guard's view type is `prod (lk u) u`, of a lock payload holding no
    cell share. -/
theorem Ty.rview_shape {t : Ty} (h : t.rview = true) :
    ∃ u, t = .prod (.lk u) u ∧ u.lkPay = true ∧ u.hasCell = false := by
  unfold Ty.rview at h
  split at h
  · rename_i u u'
    simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at h
    obtain ⟨⟨rfl, h1⟩, h2⟩ := h
    exact ⟨u, rfl, h1, h2⟩
  · cases h

theorem Ty.rview_mk {u : Ty} (h1 : u.lkPay = true) (h2 : u.hasCell = false) :
    (Ty.prod (.lk u) u).rview = true := by
  simp [Ty.rview, h1, h2]

/-- A2 types: a view's element type holds no views of its own (a view of a
    container of views is left to A2, with the other aggregates that
    carry views).  (A3.1's first cut also asked it to hold no shares; A3.1's
    slices of shares lift that: a slice of `Arc`s, of locks, of library
    handles is typed, its elements lent as `vec_at` lends them.) -/
def Ty.ok : Ty → Bool
  | .int => true
  -- (A2-drop.3b: a `Vec`'s elements hold no destructor value, or are of a
  -- destructor type themselves, or (Agora #607) drained `Vec`s in turn,
  -- `Ty.dnest`: a drained `Vec`, `Ty.vecD`, which a binding's own type may
  -- be, or (Agora #607) a struct's field or an enum's payload, which glue
  -- hands to such a binding: it is drained at its end, element by element, each
  -- running its destructor, `Step.scopeDDrain`; any other `Vec`'s drop
  -- releases its elements, which runs no code and releases no destructor
  -- value: a share's payload lives in its block, not in the tree of what
  -- holds the share, and the environment of a closure that does not drop
  -- holds none, 3c, 3d)
  | .vec t => t.ok && (t.dtorFree || t.dnest)
  | .slice t => t.ok && !t.holdsView
  | .prod a b => a.ok && b.ok
  | .sum a b => a.ok && b.ok
  | .fn _ _ => true
  -- (A2-drop.3d: a lock's or a cell's payload owns no destructor value, or
  -- (Agora #755, `Ty.lkPay`) is one at its top, or a drained `Vec` of them,
  -- that holds no cell share (Agora #803; before, no share) (a channel of
  -- them: its state under its glue): the
  -- check-out binding is given no other value in the body and goes back on a
  -- panic, and the orphaned block is reaped as an `Arc`'s.  Agora #610: an `Arc`'s payload may be a
  -- destructor value itself: the sweep that finds its block unreached marks
  -- it `dead` and the thread whose step it ends reaps it, `Mem.sweepD`,
  -- `Settle`; Agora #755: or a drained `Vec` of them, at any depth
  -- (`Ty.dnest`), which the reap hands to a destructor frame at its own type
  -- that drains it; a payload holding one in a field is still refused)
  -- (Agora #804: or a read guard's view, `prod (lk u) u`, `Ty.rview`, which
  -- owns nothing: no `arc` block is of that type, `arc_new` asks its own)
  | .arc t => t.ok && !t.holdsView && (t.dtorFree || t.dnest || t.rview)   -- A3.1: a payload holds no views
  | .lk t => t.ok && !t.holdsView && t.lkPay  -- A3.2: nor does a lock's (it is Send); A3.2's
                                   -- second cut: it may hold `arc` and lock shares; A3.5's second cut:
                                   -- and cell shares, each value going in past the crossing check
  | .cell t => t.ok && !t.holdsView && t.lkPay  -- A3.5: a cell's payload is a lock's (A3.5's
                                     -- second cut: shares in it too, each going in past the crossing check)
  | .dtor _ t => t.isStruct && t.ok  -- A2-drop.3: `% Drop` is on a struct or an enum

@[simp] theorem Ty.dtorFree_int : Ty.int.dtorFree = true := rfl
@[simp] theorem Ty.dtorFree_slice (t : Ty) : (Ty.slice t).dtorFree = true := rfl
@[simp] theorem Ty.dtorFree_fn (ms : List Nat) (q : Cross) : (Ty.fn ms q).dtorFree = !q.drops := rfl
@[simp] theorem Ty.dtorFree_arc (t : Ty) : (Ty.arc t).dtorFree = true := rfl
@[simp] theorem Ty.dtorFree_lk (t : Ty) : (Ty.lk t).dtorFree = true := rfl
@[simp] theorem Ty.dtorFree_cell (t : Ty) : (Ty.cell t).dtorFree = true := rfl
@[simp] theorem Ty.dtorFree_dtor (f : Nat) (t : Ty) : (Ty.dtor f t).dtorFree = false := rfl
@[simp] theorem Ty.dtorFree_vec (t : Ty) : (Ty.vec t).dtorFree = t.dtorFree := rfl
@[simp] theorem Ty.dtorFree_prod (a b : Ty) : (Ty.prod a b).dtorFree = (a.dtorFree && b.dtorFree) := rfl
@[simp] theorem Ty.dtorFree_sum (a b : Ty) : (Ty.sum a b).dtorFree = (a.dtorFree && b.dtorFree) := rfl
/-- A type holds a destructor value exactly when it is not free of one. -/
theorem Ty.holdsDtor_eq_not_free (t : Ty) : t.holdsDtor = !t.dtorFree := by
  induction t with
  | prod a b iha ihb => simp [Ty.holdsDtor, iha, ihb, Bool.not_and]
  | sum a b iha ihb => simp [Ty.holdsDtor, iha, ihb, Bool.not_and]
  | vec t ih => simp [Ty.holdsDtor, ih]
  | fn _ q => simp [Ty.holdsDtor, Ty.dtorFree]
  | _ => rfl

theorem Ty.ok_prod {a b : Ty} (h : (Ty.prod a b).ok = true) : a.ok = true ∧ b.ok = true := by
  simp only [Ty.ok, Bool.and_eq_true] at h; exact h
theorem Ty.ok_sum {a b : Ty} (h : (Ty.sum a b).ok = true) : a.ok = true ∧ b.ok = true := by
  simp only [Ty.ok, Bool.and_eq_true] at h; exact h
theorem Ty.ok_slice {t : Ty} (h : (Ty.slice t).ok = true) : t.ok = true ∧ t.holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; exact h
theorem Ty.ok_arc {t : Ty} (h : (Ty.arc t).ok = true) : t.ok = true ∧ t.holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; exact h.1
/-- A2-drop.3d, Agora #610: an `Arc`'s payload owns no destructor value, or
    is one at its top, or (Agora #755) a drained `Vec` of them at any depth
    (`Ty.dnest`), or (Agora #804) the share is a read guard and its payload
    a view's, `prod (lk u) u` (`Ty.rview`), which owns nothing.  Of the
    blocks: an `arc` block's type is of the first two kinds
    (`Blk.DtorOK.arc`). -/
theorem Ty.ok_arc_dtor {t : Ty} (h : (Ty.arc t).ok = true) :
    t.dtorFree = true ∨ t.dnest = true ∨ t.rview = true := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_true] at h
  rcases h.2 with (h | h) | h
  · exact Or.inl h
  · exact Or.inr (Or.inl h)
  · exact Or.inr (Or.inr h)
theorem Ty.ok_lk {t : Ty} (h : (Ty.lk t).ok = true) : t.ok = true ∧ t.holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; exact h.1
/-- A2-drop.3d: a lock's payload owns no destructor value, or (Agora #755)
    is one at its top that holds no cell share (Agora #803). -/
theorem Ty.ok_lk_pay {t : Ty} (h : (Ty.lk t).ok = true) : t.lkPay = true := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; exact h.2
theorem Ty.ok_cell {t : Ty} (h : (Ty.cell t).ok = true) : t.ok = true ∧ t.holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; exact h.1
/-- ... and so for a cell's. -/
theorem Ty.ok_cell_pay {t : Ty} (h : (Ty.cell t).ok = true) : t.lkPay = true := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_true'] at h; exact h.2

/-- Agora #755: a lock's payload that owns a destructor value is one at its
    top or a drained `Vec` of them, and (Agora #803) holds no cell share. -/
theorem Ty.lkPay_dtor {t : Ty} (h : t.lkPay = true) (hd : t.dtorFree = false) :
    t.dnest = true ∧ t.hasCell = false := by
  simp only [Ty.lkPay, hd, Bool.false_or, Bool.and_eq_true, Bool.not_eq_true'] at h; exact h

theorem Ty.lkPay_of_free {t : Ty} (h : t.dtorFree = true) : t.lkPay = true := by
  simp [Ty.lkPay, h]

theorem Ty.lkPay_free_or_dnest {t : Ty} (h : t.lkPay = true) : t.dtorFree = true ∨ t.dnest = true := by
  simp only [Ty.lkPay, Bool.or_eq_true, Bool.and_eq_true] at h
  exact h.imp id (fun h => h.1)

/-- A type that owns no destructor value is no `Vec` of destructor values. -/
theorem Ty.vecD_of_dtorFree {t : Ty} (h : t.dtorFree = true) : t.vecD = false := by
  cases t <;> simp_all [Ty.vecD, Ty.dtorFree]

theorem Ty.ok_vec_elem {t : Ty} (h : (Ty.vec t).ok = true) : t.ok = true := by
  simp only [Ty.ok, Bool.and_eq_true] at h; exact h.1
/-- A2-drop.3b's drain: a `Vec`'s elements own no destructor value, or are of
    a destructor type, or (Agora #607) are drained `Vec`s in turn
    (`Ty.dnest`). -/
theorem Ty.ok_vec_free {t : Ty} (h : (Ty.vec t).ok = true) : t.dtorFree = true ∨ t.dnest = true := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.or_eq_true] at h; exact h.2
/-- A destructor type, or a `Vec` of them at any depth, owns a destructor value. -/
theorem Ty.dtorFree_of_dnest {t : Ty} (h : t.dnest = true) : t.dtorFree = false := by
  induction t with
  | vec t ih => simpa [Ty.dnest, Ty.dtorFree] using ih (by simpa [Ty.dnest] using h)
  | dtor => rfl
  | _ => simp [Ty.dnest] at h
/-- A `Vec` whose element type is no destructor type and no drained `Vec`
    has elements that own none (A2-drop.3b part 1's reading). -/
theorem Ty.ok_vec_free_of {t : Ty} (h : (Ty.vec t).ok = true) (hd : t.dnest = false) : t.dtorFree = true := by
  rcases Ty.ok_vec_free h with h' | h'
  · exact h'
  · rw [hd] at h'; cases h'
theorem Ty.ok_vec_mk {t : Ty} (h : t.ok = true) (hf : t.dtorFree = true) : (Ty.vec t).ok = true := by
  simp [Ty.ok, h, hf]
/-- Agora #607: a `Vec` of drained elements is well formed. -/
theorem Ty.ok_vec_mkD {t : Ty} (h : t.ok = true) (hd : t.dnest = true) : (Ty.vec t).ok = true := by
  simp [Ty.ok, h, hd]
/-- A drained element type (`Ty.dnest`) of a well-formed `Vec` is a nest of
    `Vec`s around one destructor type. -/
theorem Ty.dnest_shape {t : Ty} (h : t.dnest = true) : ∃ n f u, t = Ty.nest n (.dtor f u) := by
  induction t with
  | vec t ih =>
    obtain ⟨n, f, u, rfl⟩ := ih (by simpa [Ty.dnest] using h)
    exact ⟨n + 1, f, u, rfl⟩
  | dtor f u => exact ⟨0, f, u, rfl⟩
  | _ => simp [Ty.dnest] at h
@[simp] theorem Ty.dnest_nest (n f : Nat) (u : Ty) : (Ty.nest n (.dtor f u)).dnest = true := by
  induction n with
  | zero => rfl
  | succ n ih => simpa using ih
@[simp] theorem Ty.holdsView_nest (n : Nat) (u : Ty) : (Ty.nest n u).holdsView = u.holdsView := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [Ty.holdsView] using ih
@[simp] theorem Ty.dtorViews_nest (n f : Nat) (t : Ty) :
    (Ty.nest n (.dtor f t)).dtorViews = t.holdsView := by
  simp [Ty.dtorViews, Ty.holdsView]

@[simp] theorem Ty.dtorFree_nest (n : Nat) (u : Ty) : (Ty.nest n u).dtorFree = u.dtorFree := by
  induction n with
  | zero => rfl
  | succ n ih => simpa using ih
@[simp] theorem Ty.holdsDtor_nest (n : Nat) (u : Ty) : (Ty.nest n u).holdsDtor = u.holdsDtor := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [Ty.holdsDtor] using ih
@[simp] theorem Ty.hasFn_nest (n : Nat) (u : Ty) : (Ty.nest n u).hasFn = u.hasFn := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [Ty.hasFn] using ih
@[simp] theorem Ty.vecD_nest_succ (n f : Nat) (u : Ty) : (Ty.nest (n + 1) (.dtor f u)).vecD = true := by
  simp [Ty.vecD]
/-- A nest of `Vec`s around `dtor f t` that is a destructor type is that one. -/
theorem Ty.nest_eq_dtor {n f g : Nat} {t u : Ty} (h : Ty.nest n (.dtor f t) = .dtor g u) : g = f := by
  cases n with
  | zero => cases h; rfl
  | succ n => cases h
@[simp] theorem Ty.hasCell_nest (n : Nat) (u : Ty) : (Ty.nest n u).hasCell = u.hasCell := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [Ty.hasCell] using ih
@[simp] theorem Ty.hasArc_nest (n : Nat) (u : Ty) : (Ty.nest n u).hasArc = u.hasArc := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [Ty.hasArc] using ih
/-- Agora #755: a nest of `Vec`s around a destructor type determines its
    depth, its destructor and the type under it. -/
theorem Ty.nest_dtor_inj {n n' f f' : Nat} {u u' : Ty}
    (h : Ty.nest n (.dtor f u) = Ty.nest n' (.dtor f' u')) : n = n' ∧ f = f' ∧ u = u' := by
  induction n generalizing n' with
  | zero => cases n' with
    | zero => cases h; exact ⟨rfl, rfl, rfl⟩
    | succ n' => cases h
  | succ n ih => cases n' with
    | zero => cases h
    | succ n' =>
      obtain ⟨h1, h2, h3⟩ := ih (Ty.vec.inj h)
      exact ⟨by rw [h1], h2, h3⟩
theorem Ty.nest_dtor_ne_int (n f : Nat) (u : Ty) : Ty.nest n (.dtor f u) ≠ .int := by
  cases n <;> simp
/-- Agora #755: a drained element type is exactly a nest of `Vec`s around a
    destructor type. -/
theorem Ty.dnest_iff {t : Ty} : t.dnest = true ↔ ∃ n f u, t = Ty.nest n (.dtor f u) :=
  ⟨Ty.dnest_shape, fun ⟨n, f, u, h⟩ => by rw [h]; exact Ty.dnest_nest n f u⟩

/-- Agora #607: the destructor at the core of a destructor type or of a nest
    of `Vec`s around one (`Ty.nest n (.dtor g t)`): what a call's result frame
    (`resFrame`) runs or drains with. -/
def Ty.dhead : Ty → Option Nat
  | .dtor g _ => some g
  | .vec t => t.dhead
  | _ => none

@[simp] theorem Ty.dhead_nest (n g : Nat) (t : Ty) : (Ty.nest n (.dtor g t)).dhead = some g := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [Ty.dhead] using ih

theorem Ty.dhead_some {τ : Ty} {g : Nat} (h : τ.dhead = some g) : ∃ n t, τ = Ty.nest n (.dtor g t) := by
  induction τ with
  | vec t ih =>
    obtain ⟨n, u, rfl⟩ := ih (by simpa [Ty.dhead] using h)
    exact ⟨n + 1, u, rfl⟩
  | dtor g' u => simp [Ty.dhead] at h; subst h; exact ⟨0, u, rfl⟩
  | _ => simp [Ty.dhead] at h

/-- What a well-formed nest of `Vec`s holds at its core is well formed. -/
theorem Ty.ok_of_nest {n : Nat} {u : Ty} (h : (Ty.nest n u).ok = true) : u.ok = true := by
  induction n with
  | zero => exact h
  | succ n ih => exact ih (Ty.ok_vec_elem h)
/-- A nest of `Vec`s around a well-formed destructor type is well formed. -/
theorem Ty.ok_nest {n f : Nat} {u : Ty} (h : (Ty.dtor f u).ok = true) : (Ty.nest n (.dtor f u)).ok = true := by
  induction n with
  | zero => exact h
  | succ n ih => exact Ty.ok_vec_mkD ih (Ty.dnest_nest n f u)

/-- A2-drop.3a: the type under a destructor is well formed when the
    destructor type is. -/
theorem Ty.ok_undtor {τ : Ty} (h : τ.ok = true) : τ.undtor.ok = true := by
  induction τ with
  | dtor _ _ ih => simp only [Ty.ok, Bool.and_eq_true] at h; exact ih h.2
  | _ => exact h

theorem Ty.undtor_ne_int_of {τ : Ty} {a b : Ty} (h : τ.undtor = .prod a b) : τ ≠ .int := by
  rintro rfl; cases h

theorem Ty.undtor_ne_int_of_sum {τ : Ty} {a b : Ty} (h : τ.undtor = .sum a b) : τ ≠ .int := by
  rintro rfl; cases h

/-- A type whose values own what they hold: a `Vec` or a struct.  Its
    binding is an owner (or borrows one). -/
def Ty.owning : Ty → Bool
  | .vec _ => true
  | .prod _ _ => true
  | .sum _ _ => true
  | .fn _ _ => true
  | .arc _ => true
  | .lk _ => true
  | .cell _ => true
  | .dtor _ _ => true
  | _ => false

theorem Ty.owning_of_isStruct {t : Ty} (h : t.isStruct = true) : t.owning = true := by
  cases t <;> simp_all [Ty.isStruct, Ty.owning]

/-- What an operation does to a container, ordered by what it ends.

  * `none`    — reads it;
  * `realloc` — may move its buffer (`vec_push`): ends views;
  * `drop`    — may drop elements (`vec_pop`): ends views and borrows of
                elements;
  * `replace` — releases or replaces it (a move, `vec_free`, `=`, the end
                of its scope): ends everything. -/
inductive Eff where
  | none
  | realloc
  | drop
  | replace
deriving DecidableEq, Repr

def Eff.rank : Eff → Nat
  | .none => 0
  | .realloc => 1
  | .drop => 2
  | .replace => 3

def Eff.le (a b : Eff) : Prop := a.rank ≤ b.rank

instance (a b : Eff) : Decidable (Eff.le a b) := inferInstanceAs (Decidable (_ ≤ _))

/-- How a borrow reaches the memory of the binding it depends on.

  * `self`  — the binding's own handle (a cursor, a borrowed argument);
  * `inner` — something strictly inside its elements (`vec_at` of a
              `Vec` of `Vec`s, and every borrow taken from that);
  * `view`  — its own element buffer (`slice_from_vec`, `string_data`);
  * `name b t` — the binding itself, by name: a closure that captured it,
              as a binding of type `t`, and reads it (`b = none`) or
              changes it, at most by `b`, each time it runs.  It reaches no
              memory of its own;
  * `share`  — A3.1: memory inside the payload of a share the binding holds
              (`arc_get`, and every borrow taken from that).  A payload is
              frozen, so it ends as `inner` does: when elements are dropped
              or the binding is replaced.  No change through a borrow of
              this kind is allowed (`StmtT.editB`). -/
inductive Kind where
  | self
  | inner
  | view
  | name (b : Eff) (t : Ty)
  | share
deriving DecidableEq, Repr

def Kind.isName : Kind → Bool
  | .name _ _ => true
  | _ => false

/-- What a dependency by name lets the closure holding it do to its binding. -/
def Kind.bound : Kind → Eff
  | .name b _ => b
  | _ => .none

/-- A dependency: the value is valid only while `root` is not changed in a
    way that ends borrows of this kind. -/
structure Dep where
  root : Var
  kind : Kind
deriving DecidableEq, Repr

/-- Does effect `e` on a container of element type with `hv` (holds views)
    end a borrow of kind `k`?  A container that holds views and gains or
    loses elements also ends borrows of its whole handle: what such a
    borrow may read out of it has changed (§2.10). -/
def Eff.kills (e : Eff) (hv : Bool) (k : Kind) : Bool :=
  match e, k with
  | .none, _ => false
  | .realloc, .view => true
  | .realloc, .inner => false
  | .realloc, .share => false
  | .realloc, .self => hv
  | .drop, .self => hv
  | .replace, _ => true
  | _, .name _ _ => false
  | .drop, _ => true

/-- Integer expressions.  They read but never move. -/
inductive Expr where
  | lit (n : Nat)
  | var (x : Var)
  | add (a b : Expr)
  | lt (a b : Expr)
  | len (x : Var)    -- `vec_len`
  | slen (x : Var)   -- `slice_len`
  | isl (x : Var)    -- an enum's tag: 1 for the first variant
deriving DecidableEq, Repr

/-- Parameter conventions (§1).  An `inout` parameter carries the most the
    function may do to it — its summary. -/
inductive PMode where
  | inp
  | inout (b : Eff)
  | sink
deriving DecidableEq, Repr

/-- What a parameter lets the callee do to its argument: nothing, or what
    an `inout` bound allows (a `sink` takes it, which is not a change). -/
def PMode.bound : PMode → Eff
  | .inout b => b
  | _ => .none

/-- A3.5b: an environment of type `te`, with the bindings `cs` captured by
    name, holds no more than a closure's type says (`Cross`): a Send one holds
    no view and captures nothing by name, a Sync one also no cell share, a
    bare one no share at all.  A2-drop.3c: and, of any class but the
    dropping one (Agora #609), no destructor value: such a package's drop
    releases its environment running no code.  A package of the dropping
    class is a destructor value itself, dropped by its glue. -/
def Cross.Fits (q : Cross) (te : Ty) (cs : List (Var × PMode × Ty)) : Prop :=
  (q.views = false → te.holdsView = false ∧ cs = []) ∧
  (q.cells = false → te.hasCell = false) ∧
  (q.shares = false → te.hasArc = false) ∧
  (q.drops = false → te.holdsDtor = false)

/-- What fits reads of the captures is whether there are any, not their names. -/
theorem Cross.Fits.map {q : Cross} {te : Ty} {cs : List (Var × PMode × Ty)} (h : q.Fits te cs)
    (f : Var × PMode × Ty → Var × PMode × Ty) : q.Fits te (cs.map f) :=
  ⟨fun hq => ⟨(h.1 hq).1, by rw [(h.1 hq).2]; rfl⟩, h.2⟩

theorem Cross.fits_any (te : Ty) (cs : List (Var × PMode × Ty)) (hd : te.holdsDtor = false) :
    Cross.any.Fits te cs :=
  ⟨fun h => absurd h (by decide), fun h => absurd h (by decide), fun h => absurd h (by decide), fun _ => hd⟩

/-- A3.5b's order on classes, by what an environment may hold: `bare`, `sync`,
    `send`, `any`, each holding more than the one before.  (`dropd`'s rank is
    not used: `Cross.Le` relates it to itself only.) -/
def Cross.rank : Cross → Nat
  | .bare => 0
  | .sync => 1
  | .send => 2
  | .any => 3
  | .dropd => 4

/-- A3.5b, subsumption: a closure of class `q` may be taken as one of class `q'`
    (`bare ≤ sync ≤ send ≤ any`; Agora #609: and of the same `drops`, so `dropd`
    is comparable to itself only).  Its environment then holds no more than `q'`
    says (`Cross.Fits.mono`), so the class only forgets where it may cross. -/
def Cross.Le (q q' : Cross) : Prop := q.rank ≤ q'.rank ∧ q.drops = q'.drops

instance (q q' : Cross) : Decidable (Cross.Le q q') := inferInstanceAs (Decidable (_ ∧ _))

theorem Cross.Le.refl (q : Cross) : q.Le q := ⟨Nat.le_refl _, rfl⟩

theorem Cross.Le.trans {q q' q'' : Cross} (h : q.Le q') (h' : q'.Le q'') : q.Le q'' :=
  ⟨Nat.le_trans h.1 h'.1, h.2.trans h'.2⟩

theorem Cross.le_any (q : Cross) (hd : q.drops = false) : q.Le .any := by cases q <;> first | decide | cases hd

theorem Cross.bare_le (q : Cross) (hd : q.drops = false) : Cross.bare.Le q := by cases q <;> first | decide | cases hd

/-- Only `any` is above `any`. -/
theorem Cross.Le.any_eq {q : Cross} (h : Cross.any.Le q) : q = .any := by
  cases q <;> first | rfl | exact absurd h (by decide)

/-- What a class says its environment holds none of, a class below it holds
    none of either. -/
theorem Cross.Le.views {q q' : Cross} (h : q.Le q') (h' : q'.views = false) : q.views = false := by
  cases q <;> cases q' <;> first | rfl | exact absurd h (by decide) | exact absurd h' (by decide)

theorem Cross.Le.cells {q q' : Cross} (h : q.Le q') (h' : q'.cells = false) : q.cells = false := by
  cases q <;> cases q' <;> first | rfl | exact absurd h (by decide) | exact absurd h' (by decide)

theorem Cross.Le.shares {q q' : Cross} (h : q.Le q') (h' : q'.shares = false) : q.shares = false := by
  cases q <;> cases q' <;> first | rfl | exact absurd h (by decide) | exact absurd h' (by decide)

/-- **Subsumption is sound for what a package holds**: an environment that fits
    a class fits every class above it. -/
theorem Cross.Fits.mono {q q' : Cross} {te : Ty} {cs : List (Var × PMode × Ty)} (h : q.Fits te cs)
    (hle : q.Le q') : q'.Fits te cs :=
  ⟨fun hv => h.1 (hle.views hv), fun hc => h.2.1 (hle.cells hc), fun hs => h.2.2.1 (hle.shares hs),
    fun hd => h.2.2.2 (by rw [hle.2]; exact hd)⟩

/-- A3.4: an `Atomic`'s operations (`stdlib/std/atomic.nu`), each one
    `nurl_atomic_i64_*` (`__ATOMIC_SEQ_CST`) on the word. -/
inductive AOp where
  | load   -- `atomic_load a`
  | store  -- `atomic_store a x`
  | add    -- `atomic_add a d`: the old value
  | sub    -- `atomic_sub a d`: the old value
  | swap   -- `atomic_swap a x`: the old value
  | max    -- `atomic_max a x`: the old value
  | cas    -- `atomic_cas a expect desired`: whether it was `expect`
deriving DecidableEq, Repr

/-- What an operation answers, and the word it leaves, from the word `n`
    and its arguments.  (The calculus's integers are `Nat`s, as `Expr`'s
    are: `sub` saturates where the runtime's `i64` wraps; no memory fact
    reads the number.) -/
def AOp.run : AOp → Nat → Nat → Nat → Nat × Nat
  | .load, n, _, _ => (n, n)
  | .store, _, x, _ => (0, x)
  | .add, n, d, _ => (n, n + d)
  | .sub, n, d, _ => (n, n - d)
  | .swap, n, x, _ => (n, x)
  | .max, n, x, _ => (n, Nat.max n x)
  | .cas, n, e, d => if n = e then (1, d) else (0, n)

/-- Right-hand sides of a binding or an assignment. -/
inductive Rhs where
  | expr (e : Expr)
  | new (t : Ty)               -- `vec_new [t]`
  | var (y : Var)              -- an owner moves, anything else is copied
  | borrow (y : Var)           -- a cursor `: ~ cur y` / a borrowed argument
  | at (y : Var) (i : Expr)    -- `vec_at`: bounds-checked, lends the element
  | view (y : Var)             -- `slice_from_vec` / `string_data`
  | sat (y : Var) (i : Expr)   -- `slice_at`: bounds-checked
  | pop (y : Var)              -- `vec_pop`: the element moves out
  | remove (y : Var) (i : Expr) -- `vec_remove y i`: bounds-checked, element `i` moves out
                               -- (A2-drop.3b: the drain takes element 0, in index order;
                               -- Agora #607: `vec_set` over a destructor value is a remove
                               -- into a `letd` and an `insert`, A2/DropCode.lean)
  | pair (y z : Var)           -- a struct literal: owners move in, the rest is copied
  | fst (y : Var)              -- a field read: lends what the field holds
  | snd (y : Var)
  | inl (y : Var) (b : Ty)     -- an enum's first variant, its payload taken from `y`
  | inr (a : Ty) (y : Var)
  | getl (y : Var)             -- a match on a borrowed or owned enum: lends the payload
  | getr (y : Var)
  | takel (y : Var)            -- a match by value: the payload moves out, the enum is consumed
  | taker (y : Var)
  | pack (fs : List Nat) (te : Ty) (ms : List Nat) (y : Var) (cs : List (Var × PMode × Ty))
                                            -- a closure literal or `dyn`: the methods' code `fs`,
                                            -- the environment `y` (of type `te`) moved in, the
                                            -- interfaces `ms`, and the bindings it captures by
                                            -- name: read (`inp`) or changed (`inout b`)
  | arcNew (t : Ty) (y : Var)  -- A3.1: `arc_new`: `y`'s value (a `t`) moves into a fresh block
  | arcClone (a : Var)         -- A3.1: `arc_clone`: a new share of the block `a` shares
  | arcGet (a : Var)           -- A3.1: `arc_get`: the payload of `a`'s block, lent
  | lockNew (t : Ty) (y : Var) -- A3.2: `locked_new`: `y`'s value (a `t`) moves into a fresh lock block
  | lockClone (a : Var)        -- A3.2: `Locked_share`: a new share of the lock block `a` shares
  | atomic (op : AOp) (a : Var) (e1 e2 : Expr)
                               -- A3.4: an `Atomic`'s operation on the word of the integer
                               -- lock block `a` shares, in one step (`atomic_new` is
                               -- `lockNew .int`, `Atomic_share` is `lockClone`)
  -- A3.4: a `Channel A` is a lock block whose payload is its queue and its
  -- closed flag, a `prod (vec A) int` (`chan_new` is `lockNew` of a new
  -- `Vec` and a 0, `Channel_share` is `lockClone`); each operation is one
  -- step on the payload, under the channel's mutex
  | chanSend (a y : Var)       -- `chan_send a y`: `y`'s value moves to the back of the queue
                               -- (answer 1); on a closed channel it is dropped (answer 0)
  | chanRecv (w : Bool) (a : Var)
                               -- `chan_recv a` (`w`) / `chan_try_recv a`: the queue's head
                               -- moves out, as `some` (`inr`); `none` (`inl 0`) when it is
                               -- empty and closed (or, `chan_try_recv`, just empty)
  | chanClose (a : Var)        -- `chan_close a`: the closed flag is set
  -- A3.3: an `RwLocked A` is a `Locked A` (`rw_new` is `lockNew`, `RwLocked_share`
  -- `lockClone`, `rw_update` / `wguard_update` / `rw_set` a `withLock`, which waits
  -- while a reader lives); a reader's guard is an `arc` share of a view of it
  | rwRead (a : Var)           -- `rw_read a`: a read guard of the lock `a` shares, a new view
                               -- of its payload, which lends it in place and owns none of it
                               -- (frozen while the view lives; Agora #804: a destructor value
                               -- too); `rguard_get g` is `arcGet g` (the payload is the second
                               -- field it lends)
  | rwTryRead (a : Var)        -- `rw_try_read a`: `rw_read`'s guard as an owned `some` (`inr`),
                               -- or `none` (`inl 0`) where `rw_read` would wait, with no wait
  | rwTryWrite (a : Var)       -- `rw_try_write a`'s answer: `some` (`inr 0`) when a write's
                               -- check-out (`withLock a`) would not wait, `none` (`inl 0`) where
                               -- it would; the check-out itself is `withLock` (`Stmt.withTryWrite`)
  -- A3.5: a library handle whose copies are one state (a `PNCounter`, a
  -- `TcpConn`, a `Cell`) is a cell: a lock block whose shares are not Sync;
  -- the library's in-place change is a `withLock` on a cell share (`withCell`)
  | cellNew (t : Ty) (y : Var) -- the handle's constructor: `y`'s value (a `t`) moves into a
                               -- fresh lock block, whose one share is a cell share
  | cellClone (a : Var)        -- `PNCounter_share a` (and any copy the library makes): a new
                               -- cell share of the block `a` (an owner, or a borrow: A3.5's
                               -- third cut) shares
  -- A3.6: a module global set at start (`: ( Locked T ) g ( make )`) holds a
  -- share of a block that synchronises itself; the store holds it (`Mem.gl`),
  -- every thread reaches it, and nothing writes it
  | glob (g : Nat) (t : Ty)    -- a read of global `g`, of type `t`: a new share of its block
                               -- (`: ( Locked T ) h g` clones the handle; passing `g` to a
                               -- function lends the clone)
  -- A3.2's second cut: a `Locked`'s value checked out to the caller and back
  -- (`stdlib/std/thread.nu`; the `taken` flag is the payload being out)
  | lockTake (a : Var)         -- `locked_take a`: the payload of the lock block `a` shares moves
                               -- out, owned; the block holds nothing until a restore (it is taken,
                               -- `Mem.taken`), and every other operation on it waits
  | lockRestore (a y : Var)    -- `locked_restore a y`: `y`'s value moves back in, to a block whose
                               -- payload was taken (answer 0); with the payload in, or checked out
                               -- by a `withLock` (Agora #810), a panic
deriving DecidableEq, Repr

/-! ### Memory (here because a run-time form records a snapshot of it) -/

inductive Val where
  | int (n : Nat)
  | node (t : Ty) (c d : Nat) (es : List Val)   -- `t`: the element type (ghost)
  | href (c : Nat)
  | view (d off len : Nat)
  | pair (v w : Val)                              -- a struct value, inline
  | inl (v : Val)                                 -- an enum value, inline
  | inr (v : Val)
  | pkg (fs : List Nat) (te : Ty) (ms : List Nat) (env : Val) (cs : List (Var × PMode × Ty))
                                               -- a package: its methods' code, its environment
                                               -- (of the ghost type `te`) inline, its interfaces,
                                               -- and the bindings it captured by name
  | arc (k : Nat) (p : Val)                      -- A3.1: a share of block `k`, carrying the block's
                                               -- payload `p` as ghost data (a borrow reaches it
                                               -- through the share; the block owns its addresses)
  | lk (k : Nat)                                 -- A3.2: a share of the lock block `k` (it carries
                                               -- nothing: the payload changes, and no one reads it)
  | cell (k : Nat)                               -- A3.5: a cell share of the lock block `k` (a
                                               -- library handle's state); lent, it is itself
                                               -- (`lendOf`), a borrow the library changes the
                                               -- state through (A3.5's third cut)
deriving Repr, Inhabited

/-- Is the value a `Vec`'s node?  (A2-drop.3b: a destructor frame's end
    drains a node element by element; any other value runs the frame's
    destructor on itself.) -/
def Val.isNode : Val → Bool
  | .node _ _ _ _ => true
  | _ => false

/-- A binding's storage: whether it owns its value (it is dropped at the end
    of the scope), and the value, if it holds one (the drop flag). -/
structure Slot where
  own : Bool
  val : Option Val

/-- A3.2: what a shared block is.  An `arc` block (A3.1's `Arc`) holds a
    frozen payload that every holder of a share reads; a `lock` block
    (A3.2's `Locked`) holds a payload that no one reads while it is in the
    block, and that one thread at a time checks out. -/
inductive BKind where
  | arc
  | lock
  /-- A3.3: a read view of a lock block (`rw_read`'s guard, `RwLocked`): its
      payload is a share of the lock block and that block's payload, read in
      place (`ViewsAt`: the very value the lock block holds, not a copy the
      view owns); the view owns nothing (`Blk.tree`), so no sweep frees and
      no reap drops anything of it (Agora #804: the payload may be a
      destructor value, which the lock block alone drops).  Its holders read
      the payload, frozen, while the view lives.  A writer waits until no
      view of the block is left. -/
  | view
  /-- Agora #610: an orphan whose payload awaits its destructor.  The block
      has no share left; its payload, a destructor value (Agora #755: or a
      drained `Vec` of them, at any depth), is still in it
      (the block owns it, `Blk.tree`, and it keeps the blocks it reaches,
      `Blk.keeps`), and no one reads it (`Blk.rd`), as no one reads a lock
      block's.  `Step.reap` moves the payload out to a destructor frame of
      the thread that takes the step, and leaves the block empty.  Only
      the marking sweep makes a block `dead` (`Mem.sweepD`: an unreached
      `arc` block whose payload is a destructor value or a drained `Vec` of
      them, or, Agora #755, an unreached lock block whose payload, a
      destructor value, is in it), and the thread whose
      step it ended reaps it next (`Settle`). -/
  | dead
deriving DecidableEq, Repr

/-- A shared block: its kind, and its payload, a tree of type `ty`.  How
    many shares it has is the number of leaves naming it (ghost, so nothing
    stores it).  The payload's addresses are the block's (`BlkOwn`).  An
    `arc` block's payload is always there and never changes; a `lock`
    block's is `none` while a thread has it checked out (by a `withLock`) or
    taken (by `locked_take`), which the store tells apart (`Mem.taken`, Agora
    #810); a `dead` block's
    (Agora #610) is there until `Step.reap` moves it out.  No step removes a
    block (`arcNew` adds one, `BlkLe`); the sweep at a step's end removes
    those nothing reaches and frees their payloads (`Mem.sweep`). -/
structure Blk where
  ty   : Ty
  kind : BKind
  pay  : Option Val

structure Mem where
  alloc : Nat → Bool
  nid   : Nat                 -- next fresh address
  nv    : Nat                 -- next fresh variable
  st    : Var → Option Slot
  blk   : Nat → Option Blk    -- A3.1: the counted blocks
  gl    : Nat → Option Val    -- A3.6: the module globals set at start: global `g`'s share, made
                              -- before `main`; no step writes it
  /-- Agora #810: which lock blocks' payloads `locked_take` took out.  A lock
      block whose payload is out (`⟨t, .lock, none⟩`) is **taken** when this
      says so (`EvalR.lockTake` sets it; only `locked_restore` puts a payload
      back, `EvalR.lockRestore`), and otherwise **checked out** by a
      `withLock` (`Step.withLock` clears it; only the scope's end gives the
      payload back, `Release.put`), as the runtime's lock word is `TAKEN` or
      `HELD` (`stdlib/runtime_locked.c`).  It is read only of a lock block
      whose payload is out: every step that takes a payload out sets it. -/
  taken : Nat → Bool

def upd {α : Type} (f : Nat → α) (k : Nat) (v : α) : Nat → α :=
  fun i => if i = k then v else f i

def Mem.set (m : Mem) (x : Var) (s : Slot) : Mem :=
  { m with st := upd m.st x (some s) }

def Mem.remove (m : Mem) (x : Var) : Mem :=
  { m with st := upd m.st x none }

/-- A change of a `Vec`'s elements that A2-thru adds (Agora #295): a value
    moved in at the end, the elements from the `i`-th on dropped
    (`vec_clear` is `trunc 0`, `vec_truncate` `trunc i`), or the `i`-th
    element replaced by a value moved in, the old one dropped (`vec_set`;
    out of range, the value is dropped and nothing is stored). -/
inductive Edit where
  | push (y : Var)
  | trunc (i : Expr)
  | set (i : Expr) (y : Var)

/-- Does the change drop elements?  `vec_truncate` drops those past the new
    length, `vec_set` the one it overwrites; `vec_push` drops none. -/
def Edit.drops : Edit → Bool
  | .push _ => false
  | .trunc _ => true
  | .set _ _ => true

/-- Statements.  `scope`, `rbind`, `frozen` and `catchR` are run-time forms:
    they appear when a binding is made or a function is called, never in
    source. -/
inductive Stmt where
  | skip
  | seq (a b : Stmt)
  | letv (x : Var) (r : Rhs) (body : Stmt)                -- `: x r` scoped over `body`
  | letcall (x : Var) (f : Nat) (args : List Var) (body : Stmt)
  | assign (x : Var) (r : Rhs)                            -- `= x r`
  | ite (c : Expr) (a b : Stmt)
  | while (c : Expr) (body : Stmt)
  | push (x y : Var)                                      -- `vec_push x y`
  | free (x : Var)                                        -- `vec_free x`
  | scope (x : Var) (body : Stmt)                         -- run time: `x` is bound
  | rbind (p : Var) (body : Stmt)                         -- run time: `in` parameter `p`
  | frozen (z : List Var) (body : Stmt)                   -- run time: `z` is lent out
  | panic                                                 -- `( panic … )`
  | letrec (x : Var) (f : Nat) (body : Stmt)              -- `: !v PanicInfo x ( recover f )`
  | catchR (x : Var) (m0 : Mem) (body : Stmt)             -- run time: a `recover` frame; `m0`
                                                          -- is the caller's store (a ghost)
  | unpair (y x z : Var) (body : Stmt)                    -- a struct moved apart into its fields
  | callc (x c : Var) (j : Nat) (zs : List Var) (body : Stmt)  -- `: x ( m c zs… )`: a call of
                                                          -- method `j` of the package `c`
  | letd (x : Var) (f : Nat) (r : Rhs) (body : Stmt)      -- `: x r` with the destructor `f`
                                                          -- of its type (`% Drop`, A2-drop)
  | scopeD (x : Var) (f : Nat) (body : Stmt)              -- run time: `x` is bound, and its
                                                          -- destructor runs at the end
  | edit (thru : Bool) (x : Var) (op : Edit)             -- a change of `x`'s elements (#295):
                                                          -- `thru` marks one made through a
                                                          -- borrow; the step ignores it
  | withLock (a x : Var) (body : Stmt)                    -- A3.2: `locked_update a f`: the lock
                                                          -- `a` shares is taken and its payload
                                                          -- is checked out to `x` for `body`
  | scopeL (k : Nat) (t : Ty) (x : Var) (body : Stmt)     -- run time: `x` holds lock block `k`'s
                                                          -- payload (a `t`); it goes back at
                                                          -- the end, and on a panic's unwinding
                                                          -- (`Step.scopeLP`: dropped only if it
                                                          -- cannot go back)
  | insert (x : Var) (i : Expr) (y : Var)                 -- A2-elem (#391): `y`'s value moves into
                                                          -- `x` at index `i` (at its end if `x` is
                                                          -- shorter): an element handed over goes
                                                          -- back (`withElem`)
  | withElem (v : Var) (i : Expr) (x : Var) (body : Stmt) -- A2-elem (#391): element `i` of the
                                                          -- `Vec` `v` is handed over: it moves
                                                          -- out to `x` for `body`, and back after
  | callcE (x c : Var) (j : Nat) (zs : List Var) (body : Stmt)
                                                          -- A2-envhand: `: x ( m c zs… )`, a call
                                                          -- of method `j` of the package `c` that
                                                          -- takes its receiver `inout`: the
                                                          -- environment is handed over to the
                                                          -- code, and back into `c` after


/-- A3.5: a library's in-place change of its state (`pncounter_inc a …`,
    with the change as `body` on the state `x`): a `withLock` on a cell
    share, an owner's or (A3.5's third cut) a borrowed root's, a library's
    `in` handle.  Its check-out is the lock's (A3.2), with the lock's faithfulness
    premises; what differs is who may hold the share — one thread's
    bindings only (A3's confinement), since there is no mutex.  A second
    check-out while one is out (a library re-entering its own state) waits
    or panics (`Blocked`, `Step.waitPanic`), as `RefCell`'s borrow error. -/
def Stmt.withCell (a x : Var) (s : Stmt) : Stmt := .withLock a x s

/-- A3.3: the read scope under a guard `g` already bound: `rguard_get g` lent
    to `x` (through `y`, a share of the lock and the payload) for `s`. -/
def Stmt.readWith (g y x : Var) (s : Stmt) : Stmt :=
  .letv y (.arcGet g) (.letv x (.snd y) s)

/-- A3.3: a read scope of an `RwLocked` (`: ( RGuard A ) g ( rw_read a )`,
    then `rguard_get g`), as the calculus spells it: the guard `g`, what
    `arcGet` lends through it (`y`, a share of the lock and the payload), and
    the payload, lent frozen (`x`, the second field), for `s`.  The scopes
    are `letv`'s: `g`'s end (on a panic's unwinding too) ends every borrow
    of the payload, and the view `g` holds lives until nothing reaches it;
    a writer waits until then. -/
def Stmt.withRead (a g y x : Var) (s : Stmt) : Stmt :=
  .letv g (.rwRead a) (Stmt.readWith g y x s)

/-- A3.3: `rw_try_read a`, matched (`?? ( rw_try_read a ) { T g → s } { F → e }`):
    the option `o`; on `none` (the tag `isl` is 1), `e`; on `some`, the guard
    moves out of the option into `g` (a match by value, `taker`), and the read
    scope runs under it as `withRead`'s does. -/
def Stmt.withTryRead (a o g y x : Var) (s e : Stmt) : Stmt :=
  .letv o (.rwTryRead a) (.ite (.isl o) e (.letv g (.taker o) (Stmt.readWith g y x s)))

/-- A3.3: `rw_try_write a`, matched: the answer `o`; on `none`, `e`; on `some`,
    the write's check-out, A3.2's `withLock` (`wguard_update` / `rw_set` in
    its body, `wguard_get` a borrow of `x`, `StmtT.wguardGet`).  The answer
    and the check-out are two steps: another thread may take the lock
    between them, and the check-out then waits (or panics, `Step.waitPanic`),
    where the runtime's `pthread_rwlock_trywrlock` takes it at once — more
    runs than the runtime has, every one of the runtime's among them (the
    two steps back to back). -/
def Stmt.withTryWrite (a o x : Var) (s e : Stmt) : Stmt :=
  .letv o (.rwTryWrite a) (.ite (.isl o) e (.withLock a x s))

/-- A3.2/A3.3: a call of `f` on `x` whose result `c` moves out to `z`, a
    binding of the caller's: the tail of `rw_get`, `locked_get`,
    `locked_apply` and `wguard_apply`, where `x` is the payload (lent or
    checked out) and the result is handed back once the lock is let go. -/
def Stmt.callOut (x c z : Var) (f : Nat) : Stmt := .letcall c f [x] (.assign z (.var c))

/-- A3.3: `rw_get a`, the payload copied out under a read (`stdlib/std/rwlock.nu`:
    `rw_read`, then `mem_dup ( rguard_get g )`): the read scope's body hands
    the payload `x`, lent, to the copy `f` (`mem_dup` at the payload's type,
    a function of the program, `DupFn`), and the copy `c` moves out to `z`,
    a binding of the caller's, before the guard goes. -/
def Stmt.rwGet (a g y x c z : Var) (f : Nat) : Stmt :=
  Stmt.withRead a g y x (Stmt.callOut x c z f)

/-- A3.2: `locked_apply a f` (and `rw_apply`, an `RwLocked`'s write scope being
    a `withLock`): the payload checked out to `x`, the closure `f` (a function
    of the program, `ApplyFn`) run on it `inout`, and its result `c` moved out
    to `z`, a binding of the caller's, before the lock is let go.  Inside a
    write scope already open, the tail alone (`Stmt.callOut`) is
    `wguard_apply`. -/
def Stmt.lockedApply (a x c z : Var) (f : Nat) : Stmt := .withLock a x (Stmt.callOut x c z f)

/-- A3.2: `locked_get a`, a copy taken under the lock (`stdlib/std/thread.nu`:
    `mem_dup . p val` with the mutex held): `locked_apply`'s form, `f` being
    `mem_dup` at the payload's type (`DupFn`), which takes the payload lent.
    The payload is checked out for the copy, as the runtime holds the mutex for
    it. -/
def Stmt.lockedGet (a x c z : Var) (f : Nat) : Stmt := Stmt.lockedApply a x c z f

/-- A3.2: `locked_set a y`, the value replaced under the lock
    (`stdlib/std/thread.nu`: `mem_send_check x`, then `= . p val x` with the
    mutex held, the old value dropped).  The new value faces the crossing check
    before the lock is touched, as the runtime's: it moves into a fresh lock
    block `b`, a box no other binding reaches (`locked_new`'s check, which
    panics with the store as it was).  Then `a`'s payload is checked out to
    `x` (waiting while it is out, as the runtime waits on `taken`), replaced by
    the box's value (`assign` drops the old one), and given back at the scope's
    end.  The box, empty, goes with its scope. -/
def Stmt.lockedSet (t : Ty) (a b x y : Var) : Stmt :=
  .letv b (.lockNew t y) (.withLock a x (.assign x (.lockTake b)))

/-- A3.2: `locked_await a f`, a monitor's wait, as rounds of check-outs: while
    the answer `q` (a caller's option, `none` to start) is `none`, a round is
    `locked_apply`'s form, `f` run on the checked-out payload and its answer
    (an `Option`) moved into `q`.  Each round lets the lock go, as the
    runtime's `cond_wait` lets the mutex go between runs; a round waits at its
    check-out while another thread holds the lock (`Blocked`).  The loop ends on
    a `some`, whose payload the caller takes (`taker q`). -/
def Stmt.lockedAwait (a x c q : Var) (f : Nat) : Stmt := .while (.isl q) (Stmt.lockedApply a x c q f)

/-! A3.2: a `Mutex` (`stdlib/std/thread.nu`) guards nothing in memory: it is a
lock of an integer, `lk int`, whose payload no one reads.  `mutex_new` is
`locked_new` of an integer, `Mutex_share` is `lockClone`, its drop a share's;
`mutex_lock` takes the integer out (`lockTake`: every other `mutex_lock`
waits until it is back), `mutex_unlock` puts one back (`lockRestore`), and
`mutex_with` is A3.2's `withLock`.  What the data beside a `Mutex` is allowed
is its own type's business. -/

/-- `mutex_new`, its word taken from the integer binding `y`. -/
def Rhs.mutexNew (y : Var) : Rhs := .lockNew .int y

/-- `mutex_lock m`, the integer taken out to `u` for what follows (`s`). -/
def Stmt.mutexLock (u m : Var) (s : Stmt) : Stmt := .letv u (.lockTake m) s

/-- `mutex_unlock m`, the integer `u` put back, its answer in `r`. -/
def Stmt.mutexUnlock (r m u : Var) (s : Stmt) : Stmt := .letv r (.lockRestore m u) s

/-- `mutex_with m body`: lock, run, unlock. -/
def Stmt.mutexWith (m x : Var) (s : Stmt) : Stmt := .withLock m x s

/-- A3.2: `locked_update ( vec_at v i ) f`, a lock reached as an element of the
    `Vec` `v`: element `i` handed over to `e` (A2-elem's `withElem`: it moves
    out, and back at index `i` after), and `withLock` on `e`, an owner the body
    names neither (`withLock`'s premise) nor reaches through `v` (`withElem`'s:
    the body does not name `v`). -/
def Stmt.withLockElem (v : Var) (i : Expr) (e x : Var) (s : Stmt) : Stmt :=
  .withElem v i e (.withLock e x s)

/-- A3.2: `locked_update . y l f`, a lock reached as a field of the struct `y`:
    `y` taken apart into the lock `l` and the rest `w` (`unpair`, as a field
    replaced in place is), `withLock` on `l`, an owner the body does not name,
    and the struct put back together (`= y @ { l w }`). -/
def Stmt.withLockField (y l w x : Var) (s : Stmt) : Stmt :=
  .unpair y l w (.seq (.withLock l x s) (.assign y (.pair l w)))

/-- A3.6: an update of a `Locked` global set at start (`locked_update g f`,
    with `f`'s body as `s` and its argument as `x`): the global's handle,
    cloned into `h`, and A3.2's `withLock` on it — `h` is an owner, a root,
    which `s` does not name. -/
def Stmt.lockGlobal (h x : Var) (g : Nat) (t : Ty) (s : Stmt) : Stmt :=
  .letv h (.glob g (.lk t)) (.withLock h x s)

/-- A3.6: a scalar module global (an integer, bool, float or `s` global, which
    the runtime reads and writes with relaxed atomics) is an `Atomic` set at
    start, a global of type `lk int`.  A read `: i x g` is an atomic load of
    its word, through a clone `h` of its handle ... -/
def Stmt.loadGlobal (h x : Var) (g : Nat) (s : Stmt) : Stmt :=
  .letv h (.glob g (.lk .int)) (.letv x (.atomic .load h (.lit 0) (.lit 0)) s)

/-- ... and a write `= g e` an atomic store (its answer, 0, in `x`).  What is
    stored is an integer expression, which moves no owner: safe code cannot
    hand a scalar global a value to own (h273, h202). -/
def Stmt.storeGlobal (h x : Var) (g : Nat) (e : Expr) (s : Stmt) : Stmt :=
  .letv h (.glob g (.lk .int)) (.letv x (.atomic .store h e (.lit 0)) s)

/-- A function.  Its parameters are variables `0 … n-1`, its result slot is
    variable `n`, and every variable of its body is below `nvars`.

    The summary says what a caller may rely on: which parameters the
    result borrows from (`lends`) and holds views of (`rholds`), and what
    each `inout` parameter holds views of afterwards (`outHolds`), as pairs
    (parameter index, kind). -/
structure Fn where
  params   : List (PMode × Ty)
  resTy    : Ty
  resOwn   : Bool
  lends    : List (Nat × Kind)
  rholds   : List (Nat × Kind)
  outHolds : List (Nat × Nat × Kind)
  body     : Stmt
  nvars    : Nat

abbrev Prog := List Fn

end A2
