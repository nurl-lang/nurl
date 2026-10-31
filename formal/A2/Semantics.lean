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

/-- A3.1: `v` is `t`, inside it, or inside the payload of a share `t` holds:
    where a borrow of `t` can reach. (`Sub` is the tree `t` owns: a share
    owns none of its payload; the block does.) -/
inductive SubS : Val → Val → Prop
  | sub {v t : Val} : Sub v t → SubS v t
  | arc {v t p : Val} {k : Nat} : Sub (.arc k p) t → SubS v p → SubS v t

/-- A3.1: `v` lies in the payload of a share `t` holds: reached through it. -/
def ThruS (v t : Val) : Prop := ∃ k p, Sub (.arc k p) t ∧ SubS v p

theorem ThruS.subS {v t : Val} (h : ThruS v t) : SubS v t := by
  obtain ⟨_, _, hk, hs⟩ := h
  exact .arc hk hs

/-- A tree someone owns: an owned slot's, or (A3.1) a block's payload. -/
def TreeAt (m : Mem) (t : Val) : Prop :=
  (∃ x, m.st x = some ⟨true, some t⟩) ∨ (∃ k u, m.blk k = some ⟨u, t⟩)

/-- The node with control block `c`, found in an owned tree. -/
def NodeAt (m : Mem) (c : Nat) (n : Val) : Prop :=
  ∃ t, TreeAt m t ∧ Sub n t ∧ ∃ ty d es, n = .node ty c d es

/-- The node whose element buffer is `d`, found in an owned tree. -/
def DataAt (m : Mem) (d : Nat) (n : Val) : Prop :=
  ∃ t, TreeAt m t ∧ Sub n t ∧ ∃ ty c es, n = .node ty c d es

-- Releasing a tree: each address must be live when it is freed.
mutual
inductive Frees : (Nat → Bool) → Val → (Nat → Bool) → Prop
  | int {a : Nat → Bool} {n : Nat} : Frees a (.int n) a
  | view {a : Nat → Bool} {d o l : Nat} : Frees a (.view d o l) a
  /-- A3.1: a share frees nothing by itself; the step's sweep frees a block
      no share reaches. -/
  | arc {a : Nat → Bool} {k : Nat} {p : Val} : Frees a (.arc k p) a
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
  | isl {x : Var} {o : Bool} {v : Val} : m.st x = some ⟨o, some (.inl v)⟩ → Eval m (.isl x) 1
  | isr {x : Var} {o : Bool} {v : Val} : m.st x = some ⟨o, some (.inr v)⟩ → Eval m (.isl x) 0

/-- An element read out of a buffer: an element `Vec` is lent, as `href`;
    a struct is copied with what it holds lent. -/
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
  | _ => false

/-- Handing a value on: an owner gives up its value, anything else is
    copied. -/
inductive TakeVal (m : Mem) : Var → Val → Mem → Prop
  | own {y : Var} {v : Val} : m.st y = some ⟨true, some v⟩ → TakeVal m y v (m.set y ⟨true, none⟩)
  | bor {y : Var} {v : Val} : m.st y = some ⟨false, some v⟩ → TakeVal m y v m

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
      EvalR m (.pop y) (.ok e e.owns (m.set y ⟨true, some (.node t c d es)⟩))
  | popEmpty {y : Var} {t : Ty} {c d : Nat} :
      m.st y = some ⟨true, some (.node t c d [])⟩ → EvalR m (.pop y) .panic
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

/-- The inside of a call: the result slot `r = base + n` is bound, the body
    runs with every caller binding but the `inout` arguments lent out
    (`frozen`: a bound, which typing may narrow — the bindings the closures
    handed to the call may change are not lent), and the result moves to
    the caller's binding `x`. -/
def callIn (fn : Fn) (args : List Var) (base : Nat) (x : Var) : Stmt :=
  let n := fn.params.length
  let r := base + n
  let ρ := callRen fn.params args base
  let z := (List.range base).filter (fun v => !(inoutArgs fn.params args).contains v)
  .scope r (.seq (.frozen z (wrapParams fn.params base 0 (fn.body.rename ρ))) (.assign x (.var r)))

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

/-- A step's outcome: a configuration, or a panic — with the store the
    unwinding left. -/
inductive Res where
  | ok (m : Mem) (s : Stmt)
  | panic (m : Mem)

/-- The memory a step leaves. -/
def Res.mem : Res → Mem
  | .ok m _ => m
  | .panic m => m

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
  | free {m : Mem} {x : Var} {t : Val} {a' : Nat → Bool} :
      m.st x = some ⟨true, some t⟩ → Frees m.alloc t a' →
      Step P m (.free x) (.ok ({ m with alloc := a' }.set x ⟨true, none⟩) .skip)
  | panic {m : Mem} : Step P m .panic (.panic m)
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
  /-- The scope's end with `x` owning its value: the destructor runs on `x`
      lent (its result in a fresh variable), then `scope x` frees the tree —
      the drop glue after the impl. -/
  | scopeDEnd {m : Mem} {x : Var} {f : Nat} {v : Val} :
      m.st x = some ⟨true, some v⟩ →
      Step P m (.scopeD x f .skip) (.ok { m with nv := m.nv + 1 } (.scope x (.letcall m.nv f [x] .skip)))
  /-- A moved binding runs no destructor. -/
  | scopeDMoved {m : Mem} {x : Var} {f : Nat} :
      m.st x = some ⟨true, none⟩ → Step P m (.scopeD x f .skip) (.ok (m.remove x) .skip)
  /-- A panic stops at the frame: the destructor runs, `x` is freed, and the
      panic goes on. The frame is gone, so a panic in the destructor does not
      run it again, and `scope x` still frees the fields. -/
  | scopeDP {m m1 : Mem} {x : Var} {f : Nat} {s : Stmt} {v : Val} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, some v⟩ →
      Step P m (.scopeD x f s)
        (.ok { m1 with nv := m1.nv + 1 } (.seq (.scope x (.letcall m1.nv f [x] .skip)) .panic))
  | scopeDPMoved {m m1 : Mem} {x : Var} {f : Nat} {s : Stmt} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, none⟩ →
      Step P m (.scopeD x f s) (.panic (m1.remove x))

/-- Reachability. -/
inductive Steps (P : Prog) : Mem → Stmt → Res → Prop
  | refl {m : Mem} {s : Stmt} : Steps P m s (.ok m s)
  | step {m m' : Mem} {s s' : Stmt} {r : Res} :
      Step P m s (.ok m' s') → Steps P m' s' r → Steps P m s r
  | panic {m m' : Mem} {s : Stmt} : Step P m s (.panic m') → Steps P m s (.panic m')

/-- A configuration that is neither finished nor able to step: the program
    is about to touch memory it may not. -/
def Stuck (P : Prog) (m : Mem) (s : Stmt) : Prop :=
  s ≠ .skip ∧ ∀ r, ¬ Step P m s r

end A2
