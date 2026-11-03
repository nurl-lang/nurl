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
  | fn (ms : List Nat) -- a closure or a trait object: code with an environment it owns; method `j`
                        -- has the interface `ms[j]` (a function of the program whose first parameter
                        -- is the receiver); the environment's type is not part of the type
  | arc (t : Ty)      -- A3.1: a share of a counted block whose payload, a `t`, is frozen
  | lk (t : Ty)       -- A3.2: a share of a lock block (`Locked`) whose payload is a `t`
deriving DecidableEq, Repr

/-- Does a value of this type hold views (so that storing one into a
    container makes the container depend on what is viewed)? -/
def Ty.holdsView : Ty → Bool
  | .int => false
  | .vec t => t.holdsView
  | .slice _ => true
  | .prod a b => a.holdsView || b.holdsView
  | .sum a b => a.holdsView || b.holdsView
  | .fn _ => true     -- what the environment holds is not part of the type
  | .arc t => t.holdsView
  | .lk t => t.holdsView

/-- May a value of this type hold a closure (and so hold bindings by name)? -/
def Ty.hasFn : Ty → Bool
  | .int => false
  | .vec t => t.hasFn
  | .slice t => t.hasFn
  | .prod a b => a.hasFn || b.hasFn
  | .sum a b => a.hasFn || b.hasFn
  | .fn _ => true
  | .arc t => t.hasFn
  | .lk t => t.hasFn

/-- A3.1: may a value of this type hold a share (an `Arc`)?  A closure's
    environment may. -/
def Ty.hasArc : Ty → Bool
  | .int => false
  | .vec t => t.hasArc
  | .slice t => t.hasArc
  | .prod a b => a.hasArc || b.hasArc
  | .sum a b => a.hasArc || b.hasArc
  | .fn _ => true
  | .arc _ => true
  | .lk _ => true

/-- A2 types: a view's element type holds no views of its own (a view of a
    container of views is left to A2, with the other aggregates that
    carry views), and, in A3.1's first cut, no shares. -/
def Ty.ok : Ty → Bool
  | .int => true
  | .vec t => t.ok
  | .slice t => t.ok && !t.holdsView && !t.hasArc
  | .prod a b => a.ok && b.ok
  | .sum a b => a.ok && b.ok
  | .fn _ => true
  | .arc t => t.ok && !t.holdsView   -- A3.1: a payload holds no views
  | .lk t => t.ok && !t.holdsView && !t.hasArc  -- A3.2: nor does a lock's (it is Send); nor a share

/-- A type whose values own what they hold: a `Vec` or a struct.  Its
    binding is an owner (or borrows one). -/
def Ty.owning : Ty → Bool
  | .vec _ => true
  | .prod _ _ => true
  | .sum _ _ => true
  | .fn _ => true
  | .arc _ => true
  | .lk _ => true
  | _ => false

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
  | chanRecv (w : Bool) (a : Var)
                               -- `chan_recv a` (`w`) / `chan_try_recv a`: the queue's head
                               -- moves out, as `some` (`inr`); `none` (`inl 0`) when it is
                               -- empty and closed (or, `chan_try_recv`, just empty)
  | chanClose (a : Var)        -- `chan_close a`: the closed flag is set
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
deriving Repr, Inhabited

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
deriving DecidableEq, Repr

/-- A shared block: its kind, and its payload, a tree of type `ty`.  How
    many shares it has is the number of leaves naming it (ghost, so nothing
    stores it).  The payload's addresses are the block's (`BlkOwn`).  An
    `arc` block's payload is always there and never changes; a `lock`
    block's is `none` while a thread has it checked out.  No step removes a
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
                                                          -- the end (a panic drops it, and the
                                                          -- lock stays checked out)


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
