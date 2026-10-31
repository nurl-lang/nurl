import A2.Soundness

/-!
  A3 — threads (`A3/DESIGN.md`): the configuration and its steps, what a
  step touches, a race, and the claims — stated over A2's own step.

  Statements only. Each claim is a `Prop` the milestones A3.0–A3.6 prove;
  nothing here is assumed, and nothing is used by A1 or A2.

  This is A3.0's language: A2 plus `spawn`. A function the program marks
  (`spawn f = true`) is called on a new thread. Its parameters are `sink`
  and of types that hold no views, so what moves to the new thread is a
  tree no binding of the spawner can reach any more (Send, as A3.0 has
  it). The shared blocks (`Arc`, `Locked`, `RwLocked`, `Atomic`,
  channels) are added by A3.1–A3.5.
-/

namespace A3
open A2

/-- What one thread has of its own: its bindings, its next fresh variable,
    and what it runs. -/
structure Thread where
  st : Var → Option Slot
  nv : Nat
  s  : Stmt

/-- A configuration: one address space and its fresh addresses, shared by
    every thread, and the threads. -/
structure Cfg where
  alloc : Nat → Bool
  nid   : Nat
  ths   : List Thread

/-- What A2's step runs on for thread `t`: the shared address space, the
    thread's own bindings. -/
def Cfg.view (C : Cfg) (t : Thread) : Mem :=
  { alloc := C.alloc, nid := C.nid, nv := t.nv, st := t.st }

/-- Thread `i`'s step written back: the address space to the configuration,
    the bindings and the statement to the thread. -/
def Cfg.put (C : Cfg) (i : Nat) (m : Mem) (s : Stmt) : Cfg :=
  { alloc := m.alloc, nid := m.nid, ths := C.ths.set i ⟨m.st, m.nv, s⟩ }

/-- A program run from the empty store, on one thread (A2's `emptyMem`). -/
def Cfg.init (s : Stmt) (nv : Nat) : Cfg :=
  { alloc := fun _ => false, nid := 0, ths := [⟨fun _ => none, nv, s⟩] }

/-- Where a statement takes its next step: `s` is `K` around `r`, through
    the forms A2's step goes into (`seqL`, `scopeIn`, `rbindIn`, `frozenIn`,
    `catchIn`). -/
inductive Redex : Stmt → (Stmt → Stmt) → Stmt → Prop
  | here {s : Stmt} : Redex s id s
  | seq {a b r : Stmt} {K : Stmt → Stmt} : Redex a K r → Redex (.seq a b) (fun y => .seq (K y) b) r
  | scope {x : Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.scope x s) (fun y => .scope x (K y)) r
  | rbind {p : Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.rbind p s) (fun y => .rbind p (K y)) r
  | frozen {z : List Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.frozen z s) (fun y => .frozen z (K y)) r
  | catchR {x : Var} {m0 : Mem} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.catchR x m0 s) (fun y => .catchR x m0 (K y)) r
  | scopeD {x : Var} {f : Nat} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.scopeD x f s) (fun y => .scopeD x f (K y)) r

/-- A spawned function: every parameter is a `sink` of a type that holds no
    views, and it returns an integer. -/
def SpawnOK (P : Prog) (spawn : Nat → Bool) : Prop :=
  ∀ f, spawn f = true → ∃ fn, P[f]? = some fn ∧ fn.resTy = .int ∧
    ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false

/-- Moving the arguments out of the spawner: each owns its value, and its
    slot is left empty (its drop flag clear). -/
inductive MoveArgs : (Var → Option Slot) → List Var → List Val → (Var → Option Slot) → Prop
  | nil {st : Var → Option Slot} : MoveArgs st [] [] st
  | cons {st st' : Var → Option Slot} {a : Var} {as : List Var} {v : Val} {vs : List Val} :
      st a = some ⟨true, some v⟩ → MoveArgs (upd st a (some ⟨true, none⟩)) as vs st' →
      MoveArgs st (a :: as) (v :: vs) st'

/-- The new thread's bindings: parameter `i` owns the `i`-th value, and the
    result slot is bound, empty. -/
def spawnSt (fn : Fn) (vs : List Val) : Var → Option Slot := fun v =>
  if v = fn.params.length then some ⟨false, none⟩ else (vs[v]?).map fun w => ⟨true, some w⟩

/-- A spawn calls `f` on a new thread. -/
def SpawnRedex (spawn : Nat → Bool) (s : Stmt) : Prop :=
  ∃ K x f args k, Redex s K (.letcall x f args k) ∧ spawn f = true

/-- One step of the configuration. -/
inductive TStep (P : Prog) (spawn : Nat → Bool) : Cfg → Cfg → Prop
  /-- A thread takes one of A2's steps, unless its next step is a spawn. -/
  | thread {C : Cfg} {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} :
      C.ths[i]? = some t → ¬ SpawnRedex spawn t.s → Step P (C.view t) t.s (.ok m' s') →
      TStep P spawn C (C.put i m' s')
  /-- A spawn: the arguments move to a new thread, which runs the body in
      its parameters' scopes and its result's (variable `n`, the number of
      parameters, as in the body's own numbering — so its end drops the
      result); the spawner's result is `0`. -/
  | spawn {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot} :
      C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true → P[f]? = some fn →
      t.st x = none → MoveArgs t.st args vs st' →
      TStep P spawn C
        { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                        [⟨spawnSt fn vs, fn.nvars,
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] }

inductive Reach (P : Prog) (spawn : Nat → Bool) : Cfg → Cfg → Prop
  | refl {C : Cfg} : Reach P spawn C C
  | step {C C' C'' : Cfg} : TStep P spawn C C' → Reach P spawn C' C'' → Reach P spawn C C''

/-! ### What a step touches

The addresses a thread's next step reads (`false`) or writes (`true`): the
ones A2's rule checks `alloc` for, changes or frees.  Slots are a thread's
own and are no address.  A fresh address is no touch: allocation is the
allocator's, which is thread-safe (the C runtime, trusted base), and two
threads that both allocate next never get one address, since `nid` moves
with each step.  Over-approximating is harmless otherwise: what a thread
may touch beyond its rule is its own. -/

/-- What evaluating an expression reads: a `Vec`'s length is in its control
    block. -/
inductive EReads (m : Mem) : Expr → Nat → Prop
  | len {x : Var} {t : Ty} {c d : Nat} {es : List Val} : VecOf m x t c d es → EReads m (.len x) c
  | addL {a b : Expr} {i : Nat} : EReads m a i → EReads m (.add a b) i
  | addR {a b : Expr} {i : Nat} : EReads m b i → EReads m (.add a b) i
  | ltL {a b : Expr} {i : Nat} : EReads m a i → EReads m (.lt a b) i
  | ltR {a b : Expr} {i : Nat} : EReads m b i → EReads m (.lt a b) i

/-- What a right-hand side touches. -/
inductive RTouch (m : Mem) : Rhs → Nat → Bool → Prop
  | expr {e : Expr} {i : Nat} : EReads m e i → RTouch m (.expr e) i false
  | atC {y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      VecOf m y t c d es → RTouch m (.at y i) c false
  | atD {y : Var} {i : Expr} {t : Ty} {c d : Nat} {es : List Val} :
      VecOf m y t c d es → RTouch m (.at y i) d false
  | atI {y : Var} {i : Expr} {a : Nat} : EReads m i a → RTouch m (.at y i) a false
  | view {y : Var} {t : Ty} {c d : Nat} {es : List Val} : VecOf m y t c d es → RTouch m (.view y) c false
  | sat {y : Var} {i : Expr} {d o l : Nat} :
      m.st y = some ⟨false, some (.view d o l)⟩ → RTouch m (.sat y i) d false
  | satI {y : Var} {i : Expr} {a : Nat} : EReads m i a → RTouch m (.sat y i) a false
  | popC {y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st y = some ⟨true, some (.node t c d es)⟩ → RTouch m (.pop y) c true
  | popD {y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st y = some ⟨true, some (.node t c d es)⟩ → RTouch m (.pop y) d true

/-- What the next step of `s` touches. -/
inductive Touch (P : Prog) (m : Mem) : Stmt → Nat → Bool → Prop
  | seq {a b : Stmt} {i : Nat} {w : Bool} : Touch P m a i w → Touch P m (.seq a b) i w
  | letv {x : Var} {r : Rhs} {s : Stmt} {i : Nat} {w : Bool} :
      RTouch m r i w → Touch P m (.letv x r s) i w
  | letd {x : Var} {f : Nat} {r : Rhs} {s : Stmt} {i : Nat} {w : Bool} :
      RTouch m r i w → Touch P m (.letd x f r s) i w
  /-- A destructor's scope: its body's step. Its end runs the destructor's
      call first, and `scope x` frees the tree after it (`scopeEnd`). -/
  | scopeD {x : Var} {f : Nat} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.scopeD x f s) i w
  | assign {x : Var} {r : Rhs} {i : Nat} {w : Bool} : RTouch m r i w → Touch P m (.assign x r) i w
  /-- An assignment releases the binding's old value. -/
  | assignDrop {x : Var} {r : Rhs} {t : Val} {i : Nat} :
      m.st x = some ⟨true, some t⟩ → i ∈ t.ids → Touch P m (.assign x r) i true
  | ite {c : Expr} {a b : Stmt} {i : Nat} : EReads m c i → Touch P m (.ite c a b) i false
  | pushC {x y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st x = some ⟨true, some (.node t c d es)⟩ → Touch P m (.push x y) c true
  | pushD {x y : Var} {t : Ty} {c d : Nat} {es : List Val} :
      m.st x = some ⟨true, some (.node t c d es)⟩ → Touch P m (.push x y) d true
  | free {x : Var} {t : Val} {i : Nat} :
      m.st x = some ⟨true, some t⟩ → i ∈ t.ids → Touch P m (.free x) i true
  | scope {x : Var} {s : Stmt} {i : Nat} {w : Bool} : Touch P m s i w → Touch P m (.scope x s) i w
  /-- A scope's end releases what its binding owns ... -/
  | scopeEnd {x : Var} {t : Val} {i : Nat} :
      m.st x = some ⟨true, some t⟩ → i ∈ t.ids → Touch P m (.scope x .skip) i true
  /-- ... and so does a panic unwinding through it. -/
  | scopeUnwind {x : Var} {s : Stmt} {m1 : Mem} {t : Val} {i : Nat} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, some t⟩ → i ∈ t.ids →
      Touch P m (.scope x s) i true
  | rbind {p : Var} {s : Stmt} {i : Nat} {w : Bool} : Touch P m s i w → Touch P m (.rbind p s) i w
  | frozen {z : List Var} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.frozen z s) i w
  | catchR {x : Var} {m0 : Mem} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.catchR x m0 s) i w

/-- A race: two threads whose next steps touch one address, one of them
    writing it.  (A3.4's `Atomic` steps are atomic and are no race.) -/
def Race (P : Prog) (C : Cfg) : Prop :=
  ∃ (i j : Nat) (ti tj : Thread) (a : Nat) (w : Bool), i ≠ j ∧ C.ths[i]? = some ti ∧
    C.ths[j]? = some tj ∧
    Touch P (C.view ti) ti.s a true ∧ Touch P (C.view tj) tj.s a w

/-! ### The claims -/

/-- No thread of a reachable configuration is stuck: A2's `memory_safe`, on
    every thread. -/
def MemorySafe (P : Prog) (spawn : Nat → Bool) (s : Stmt) (nv : Nat) : Prop :=
  ∀ C, Reach P spawn (Cfg.init s nv) C → ∀ (i : Nat) (t : Thread), C.ths[i]? = some t →
    ¬ Stuck P (C.view t) t.s

/-- No reachable configuration has a race. -/
def RaceFree (P : Prog) (spawn : Nat → Bool) (s : Stmt) (nv : Nat) : Prop :=
  ∀ C, Reach P spawn (Cfg.init s nv) C → ¬ Race P C

/-- When every thread has finished, nothing is allocated: A2's
    `no_leak_end`, over the threads. -/
def NoLeak (P : Prog) (spawn : Nat → Bool) (s : Stmt) (nv : Nat) : Prop :=
  ∀ C, Reach P spawn (Cfg.init s nv) C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false

/-- **The A3.0 claim**, for A2 plus `spawn`: a program A2 types, whose
    spawned functions take only view-free `sink` parameters, is memory-safe,
    race-free and leak-free on every interleaving.  Milestone A3.0 proves it;
    A3.1–A3.6 extend the language and restate it. -/
def Claim : Prop :=
  ∀ (P : Prog) (spawn : Nat → Bool) (s : Stmt) (Δ : Ctx) (nv : Nat),
    ProgOK P → ProgCodes P → SpawnOK P spawn →
    StmtT P (fun _ => none) [] s Δ → s.src = true → s.codesOK P → (∀ v ∈ s.vars, v < nv) →
    MemorySafe P spawn s nv ∧ RaceFree P spawn s nv ∧ NoLeak P spawn s nv

/-- The view of the initial configuration is A2's empty store. -/
theorem init_view (s : Stmt) (nv : Nat) :
    (Cfg.init s nv).view ⟨fun _ => none, nv, s⟩ = emptyMem nv := rfl

end A3
