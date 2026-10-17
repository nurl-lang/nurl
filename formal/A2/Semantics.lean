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

inductive Val where
  | int (n : Nat)
  | node (t : Ty) (c d : Nat) (es : List Val)   -- `t`: the element type (ghost)
  | href (c : Nat)
  | view (d off len : Nat)
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

/-- `v` occurs in tree `t` (reflexively). -/
inductive Sub : Val → Val → Prop
  | refl (v : Val) : Sub v v
  | child {v e : Val} {t : Ty} {c d : Nat} {es : List Val} :
      e ∈ es → Sub v e → Sub v (.node t c d es)

/-- The node with control block `c`, found in an owned tree. -/
def NodeAt (m : Mem) (c : Nat) (n : Val) : Prop :=
  ∃ x t, m.st x = some ⟨true, some t⟩ ∧ Sub n t ∧ ∃ ty d es, n = .node ty c d es

/-- The node whose element buffer is `d`, found in an owned tree. -/
def DataAt (m : Mem) (d : Nat) (n : Val) : Prop :=
  ∃ x t, m.st x = some ⟨true, some t⟩ ∧ Sub n t ∧ ∃ ty c es, n = .node ty c d es

-- Releasing a tree: each address must be live when it is freed.
mutual
inductive Frees : (Nat → Bool) → Val → (Nat → Bool) → Prop
  | int {a : Nat → Bool} {n : Nat} : Frees a (.int n) a
  | view {a : Nat → Bool} {d o l : Nat} : Frees a (.view d o l) a
  | node {a a' : Nat → Bool} {t : Ty} {c d : Nat} {es : List Val} :
      a c = true → upd a c false d = true →
      FreesL (upd (upd a c false) d false) es a' →
      Frees a (.node t c d es) a'
inductive FreesL : (Nat → Bool) → List Val → (Nat → Bool) → Prop
  | nil {a : Nat → Bool} : FreesL a [] a
  | cons {a a1 a2 : Nat → Bool} {e : Val} {es : List Val} :
      Frees a e a1 → FreesL a1 es a2 → FreesL a (e :: es) a2
end

/-- What leaving a scope releases: an owned value whose flag is set. -/
inductive DropSlot : (Nat → Bool) → Slot → (Nat → Bool) → Prop
  | owned {a a' : Nat → Bool} {t : Val} : Frees a t a' → DropSlot a ⟨true, some t⟩ a'
  | moved {a : Nat → Bool} : DropSlot a ⟨true, none⟩ a
  | borrowed {a : Nat → Bool} {v : Option Val} : DropSlot a ⟨false, v⟩ a

/-- The vector `x` names — its own tree, or the one its borrow points at —
    with both of its addresses live. -/
def VecOf (m : Mem) (x : Var) (t : Ty) (c d : Nat) (es : List Val) : Prop :=
  m.alloc c = true ∧ m.alloc d = true ∧
  (m.st x = some ⟨true, some (.node t c d es)⟩ ∨
   (m.st x = some ⟨false, some (.href c)⟩ ∧ NodeAt m c (.node t c d es)))

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

/-- An element read out of a buffer: an element `Vec` is lent, as `href`. -/
def lendOf : Val → Val
  | .node _ c _ _ => .href c
  | v => v

/-- Does moving this element out move an owned tree? -/
def Val.isNode : Val → Bool
  | .node .. => true
  | _ => false

inductive RRes where
  | ok (v : Val) (own : Bool) (m : Mem)
  | panic

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
      EvalR m (.pop y) (.ok e e.isNode (m.set y ⟨true, some (.node t c d es)⟩))
  | popEmpty {y : Var} {t : Ty} {c d : Nat} :
      m.st y = some ⟨true, some (.node t c d [])⟩ → EvalR m (.pop y) .panic

/-- Handing a value on: an owner gives up its value, anything else is
    copied. -/
inductive TakeVal (m : Mem) : Var → Val → Mem → Prop
  | own {y : Var} {v : Val} : m.st y = some ⟨true, some v⟩ → TakeVal m y v (m.set y ⟨true, none⟩)
  | bor {y : Var} {v : Val} : m.st y = some ⟨false, some v⟩ → TakeVal m y v m

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

def Rhs.rename (ρ : Var → Var) : Rhs → Rhs
  | .expr e => .expr (e.rename ρ)
  | .new t => .new t
  | .var y => .var (ρ y)
  | .borrow y => .borrow (ρ y)
  | .at y i => .at (ρ y) (i.rename ρ)
  | .view y => .view (ρ y)
  | .sat y i => .sat (ρ y) (i.rename ρ)
  | .pop y => .pop (ρ y)

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

/-- A borrowed argument: an owner lends its handle, a borrow is copied. -/
def lendSlot : Slot → Option Val
  | ⟨true, some (.node _ c _ _)⟩ => some (.href c)
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

/-- What a call becomes: the result slot `r = base + n` and the caller's
    binding `x` are bound, the body runs with every caller binding but the
    `inout` arguments lent out (`frozen`), and the result moves to `x`. -/
def callStmt (fn : Fn) (args : List Var) (base : Nat) (x : Var) (k : Stmt) : Stmt :=
  let n := fn.params.length
  let r := base + n
  let ρ := callRen fn.params args base
  let z := (List.range base).filter (fun v => !(inoutArgs fn.params args).contains v)
  .scope x (.seq
    (.scope r (.seq (.frozen z (wrapParams fn.params base 0 (fn.body.rename ρ)))
                    (.assign x (.var r))))
    k)

inductive Res where
  | ok (m : Mem) (s : Stmt)
  | panic

inductive Step (P : Prog) : Mem → Stmt → Res → Prop
  | seqSkip {m : Mem} {b : Stmt} : Step P m (.seq .skip b) (.ok m b)
  | seqL {m m' : Mem} {a a' b : Stmt} :
      Step P m a (.ok m' a') → Step P m (.seq a b) (.ok m' (.seq a' b))
  | seqP {m : Mem} {a b : Stmt} : Step P m a .panic → Step P m (.seq a b) .panic
  | letv {m m' : Mem} {x : Var} {r : Rhs} {s : Stmt} {v : Val} {o : Bool} :
      m.st x = none → EvalR m r (.ok v o m') →
      Step P m (.letv x r s) (.ok (m'.set x ⟨o, some v⟩) (.scope x s))
  | letvP {m : Mem} {x : Var} {r : Rhs} {s : Stmt} :
      EvalR m r .panic → Step P m (.letv x r s) .panic
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
  | scopeP {m : Mem} {x : Var} {s : Stmt} : Step P m s .panic → Step P m (.scope x s) .panic
  | rbindSkip {m : Mem} {p : Var} {sl : Slot} :
      m.st p = some sl → Step P m (.rbind p .skip) (.ok (m.remove p) .skip)
  | rbindIn {m m' : Mem} {p : Var} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.rbind p s) (.ok m' (.rbind p s'))
  | rbindP {m : Mem} {p : Var} {s : Stmt} : Step P m s .panic → Step P m (.rbind p s) .panic
  | frozenSkip {m : Mem} {z : List Var} : Step P m (.frozen z .skip) (.ok m .skip)
  | frozenIn {m m' : Mem} {z : List Var} {s s' : Stmt} :
      Step P m s (.ok m' s') → Step P m (.frozen z s) (.ok m' (.frozen z s'))
  | frozenP {m : Mem} {z : List Var} {s : Stmt} : Step P m s .panic → Step P m (.frozen z s) .panic
  | assign {m m1 : Mem} {x : Var} {r : Rhs} {v : Val} {o : Bool} {sl : Slot} {a' : Nat → Bool} :
      (m.st x).isSome → EvalR m r (.ok v o m1) → m1.st x = some sl → DropSlot m1.alloc sl a' →
      Step P m (.assign x r) (.ok ({ m1 with alloc := a' }.set x ⟨o, some v⟩) .skip)
  | assignP {m : Mem} {x : Var} {r : Rhs} :
      EvalR m r .panic → Step P m (.assign x r) .panic
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
  | free {m : Mem} {x : Var} {t : Val} {a' : Nat → Bool} :
      m.st x = some ⟨true, some t⟩ → Frees m.alloc t a' →
      Step P m (.free x) (.ok ({ m with alloc := a' }.set x ⟨true, none⟩) .skip)

/-- Reachability. -/
inductive Steps (P : Prog) : Mem → Stmt → Res → Prop
  | refl {m : Mem} {s : Stmt} : Steps P m s (.ok m s)
  | step {m m' : Mem} {s s' : Stmt} {r : Res} :
      Step P m s (.ok m' s') → Steps P m' s' r → Steps P m s r
  | panic {m : Mem} {s : Stmt} : Step P m s .panic → Steps P m s .panic

/-- A configuration that is neither finished nor able to step: the program
    is about to touch memory it may not. -/
def Stuck (P : Prog) (m : Mem) (s : Stmt) : Prop :=
  s ≠ .skip ∧ ∀ r, ¬ Step P m s r

end A2
