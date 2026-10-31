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

/-- A2 types: a view's element type holds no views of its own (a view of a
    container of views is left to A2, with the other aggregates that
    carry views). -/
def Ty.ok : Ty → Bool
  | .int => true
  | .vec t => t.ok
  | .slice t => t.ok && !t.holdsView
  | .prod a b => a.ok && b.ok
  | .sum a b => a.ok && b.ok
  | .fn _ => true
  | .arc t => t.ok && !t.holdsView   -- A3.1's first cut: a payload holds no views (nor a closure)

/-- A type whose values own what they hold: a `Vec` or a struct.  Its
    binding is an owner (or borrows one). -/
def Ty.owning : Ty → Bool
  | .vec _ => true
  | .prod _ _ => true
  | .sum _ _ => true
  | .fn _ => true
  | .arc _ => true
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
              memory of its own. -/
inductive Kind where
  | self
  | inner
  | view
  | name (b : Eff) (t : Ty)
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
  | arc (k : Nat)                                -- A3.1: a share of block `k`; the payload is the block's
deriving Repr, Inhabited

/-- A binding's storage: whether it owns its value (it is dropped at the end
    of the scope), and the value, if it holds one (the drop flag). -/
structure Slot where
  own : Bool
  val : Option Val

structure Mem where
  alloc : Nat → Bool
  nid   : Nat                 -- next fresh address
  nv    : Nat                 -- next fresh variable
  st    : Var → Option Slot

def upd {α : Type} (f : Nat → α) (k : Nat) (v : α) : Nat → α :=
  fun i => if i = k then v else f i

def Mem.set (m : Mem) (x : Var) (s : Slot) : Mem :=
  { m with st := upd m.st x (some s) }

def Mem.remove (m : Mem) (x : Var) : Mem :=
  { m with st := upd m.st x none }

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
