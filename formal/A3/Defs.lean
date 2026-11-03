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
  it). A3.1's `Arc` is A2's own (`Mem.blk`, `Val.arc`): its blocks are
  shared by every thread, and the configuration's sweep ends every
  thread's step. The other shared blocks (`Locked`, `RwLocked`, `Atomic`,
  channels) are added by A3.2–A3.5.  A3.6's module globals set at start
  are the configuration's (`Cfg.gl`): every thread reads them, no step
  writes them, and the sweep keeps what they reach.
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
  blk   : Nat → Option Blk   -- A3.1: the counted blocks, shared by every thread
  gl    : Nat → Option Val     -- A3.6: the module globals set at start, which every thread reads
  ths   : List Thread

/-- What A2's step runs on for thread `t`: the shared address space, the
    thread's own bindings. -/
def Cfg.view (C : Cfg) (t : Thread) : Mem :=
  { alloc := C.alloc, nid := C.nid, nv := t.nv, st := t.st, blk := C.blk, gl := C.gl }

/-- Thread `i`'s step written back: the address space to the configuration,
    the bindings and the statement to the thread. -/
def Cfg.put (C : Cfg) (i : Nat) (m : Mem) (s : Stmt) : Cfg :=
  { alloc := m.alloc, nid := m.nid, blk := m.blk, gl := m.gl, ths := C.ths.set i ⟨m.st, m.nv, s⟩ }

/-- A3.1: the values the threads' slots hold. -/
def Cfg.vals (C : Cfg) (v : Val) : Prop :=
  ∃ (j : Nat) (t : Thread), C.ths[j]? = some t ∧ ∃ x o, t.st x = some ⟨o, some v⟩

/-- A3.6: the values the module globals hold. -/
def Cfg.globVals (C : Cfg) (v : Val) : Prop := ∃ g, C.gl g = some v

/-- The roots of the configuration's sweep: what the threads' slots hold
    (A3.1), and (A3.6) what the module globals hold, which every thread may
    read for as long as the program runs. -/
def Cfg.roots (C : Cfg) (v : Val) : Prop := C.vals v ∨ C.globVals v

/-- A3.1: the configuration's sweep, which ends every thread's step: the
    blocks nothing reaches from a thread's slot or (A3.6) a global are
    removed and their payloads freed — A2's `Mem.sweep`, from every thread's
    slots at once (the count of a block's shares is over all threads) and
    the globals (which hold a share each until the process exits). -/
noncomputable def Cfg.sweep (C : Cfg) : Cfg :=
  { C with alloc := sweepAlloc C.roots C.blk C.alloc, blk := sweepBlk C.roots C.blk }

/-- A program run from the empty store, on one thread (A2's `emptyMem`). -/
def Cfg.init (s : Stmt) (nv : Nat) : Cfg :=
  { alloc := fun _ => false, nid := 0, blk := fun _ => none, gl := fun _ => none,
    ths := [⟨fun _ => none, nv, s⟩] }

/-- **A3.6: the module globals set at start**, as `main` finds them: the
    store their `make`s left — the blocks they built, the addresses those
    blocks' payloads own, the next fresh address — and each global's share.
    They are given with the start, not run before it: `GlobsOK` asks of them
    what A2's invariant says of the store a typed `make` leaves once its
    result is the global's. -/
structure Globs where
  alloc : Nat → Bool
  nid   : Nat
  blk   : Nat → Option Blk
  gl    : Nat → Option Val

/-- No global: A3.0–A3.5's start. -/
def Globs.empty : Globs := ⟨fun _ => false, 0, fun _ => none, fun _ => none⟩

/-- The store the globals' `make`s left, with no binding. -/
def Globs.mem (G : Globs) (nv : Nat) : Mem := ⟨G.alloc, G.nid, nv, fun _ => none, G.blk, G.gl⟩

/-- A3.6: a program run with its module globals set, on one thread, which
    (as every thread it spawns) reads them through the configuration
    (`Cfg.gl`, `Cfg.view`). -/
def Cfg.start (G : Globs) (s : Stmt) (nv : Nat) : Cfg :=
  { alloc := G.alloc, nid := G.nid, blk := G.blk, gl := G.gl, ths := [⟨fun _ => none, nv, s⟩] }

/-- With no global, the start is A3.0's. -/
theorem Cfg.init_start (s : Stmt) (nv : Nat) : Cfg.init s nv = Cfg.start Globs.empty s nv := rfl

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
  | scopeL {k : Nat} {t : Ty} {x : Var} {s r : Stmt} {K : Stmt → Stmt} :
      Redex s K r → Redex (.scopeL k t x s) (fun y => .scopeL k t x (K y)) r

/-- A spawned function: every parameter is a `sink` of a type that holds no
    views, and it returns an integer. -/
def SpawnOK (P : Prog) (spawn : Nat → Bool) : Prop :=
  ∀ f, spawn f = true → ∃ fn, P[f]? = some fn ∧ fn.resTy = .int ∧
    ∀ pt ∈ fn.params, pt.1 = .sink ∧ pt.2.holdsView = false

/-- A3.1, Send: a share crosses to a new thread when its payload holds no
    views — `SpawnOK`'s question asked of `Ty.arc t`, unchanged.  Every A2
    type `arc t` meets it (`Ty.ok` asks it of the payload) ... -/
theorem arc_spawnOK {t : Ty} (h : (Ty.arc t).ok = true) : (Ty.arc t).holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h.2

/-- ... and so does every share `arc_new` makes: its payload's type holds no
    views (`RhsT.arcNew`), whatever trees it owns. -/
theorem arc_spawnOK_viewFree {t : Ty} (h : t.holdsView = false) : (Ty.arc t).holdsView = false := h

/-- A3.2, Send: a lock share crosses to a new thread when its payload holds
    no views, `SpawnOK`'s question again; every A2 type `lk t` meets it
    (`Ty.ok` asks it of the payload, `RhsT.lockNew` of what moves in). -/
theorem lk_spawnOK {t : Ty} (h : (Ty.lk t).ok = true) : (Ty.lk t).holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h.1.2

/-- A3.5, Send: a library handle (a cell share) crosses to a new thread as a
    lock share does, `SpawnOK`'s question unchanged; what it may not do is
    leave an owner behind, which the crossing check asks at run time
    (`SendCheck`). -/
theorem cell_spawnOK {t : Ty} (h : (Ty.cell t).ok = true) : (Ty.cell t).holdsView = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h.1.2

/-- A3.5, Sync: no shared payload holds a library handle.  A type that holds
    no share holds no cell share, so a lock's payload (`RhsT.lockNew`,
    `Ty.ok (lk t)`) and a channel's element (`RhsT.chanSend`) hold none;
    an `Arc`'s payload holds none by `RhsT.arcNew`'s own premise. -/
theorem _root_.A2.Ty.hasCell_of_hasArc {t : Ty} (h : t.hasArc = false) : t.hasCell = false := by
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

theorem lk_noCell {t : Ty} (h : (Ty.lk t).ok = true) : t.hasCell = false := by
  simp only [Ty.ok, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact Ty.hasCell_of_hasArc h.2

/-! ### A3.6: module globals, as A2 types them

A global set at start is read at a type that synchronises itself
(`RhsT.glob`, `Ty.sync`), into an owner of a clone of its share; A3.2–A3.4's
rules then take that owner, a root, unchanged. -/

/-- A global is read only at a type that synchronises itself. -/
theorem _root_.A2.RhsT.glob_sync {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry}
    (h : RhsT Γ F (.glob g t) E Γ1) : t.sync = true := by
  cases h with | glob hs _ => exact hs

/-- h263 (`start_global_shared_unsynchronised`): no global is a `Vec`, which
    two threads would push through it with no lock ... -/
theorem glob_not_vec {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.vec t)) E Γ1 := fun h => by cases h.glob_sync

/-- ... h272 (`struct_global_torn_between_threads`): nor a struct of plain
    values, more than one word, which no atomic access covers (it is
    `unsafe`-only, trusted base; safe code keeps one in a `Locked`) ... -/
theorem glob_not_prod {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {a b : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.prod a b)) E Γ1 := fun h => by cases h.glob_sync

/-- ... nor a bare integer: a scalar global is an `Atomic` (`lk int`), read and
    written by atomic steps (`Stmt.loadGlobal`, `Stmt.storeGlobal`) ... -/
theorem glob_not_int {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {E : Entry} :
    ¬ RhsT Γ F (.glob g .int) E Γ1 := fun h => by cases h.glob_sync

/-- ... nor a library handle, which is not Sync (A3.5) ... -/
theorem glob_not_cell {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.cell t)) E Γ1 := fun h => by cases h.glob_sync

/-- ... nor (h254, `symtab_shared_between_threads`) an `Arc` of one: a
    `SymTab` shared through an `Arc` reaches two threads, which change it with
    no lock (as `RhsT.arcNew` refuses making one, A3.5). -/
theorem glob_not_arc_cell {Γ Γ1 : Ctx} {F : List Var} {g : Nat} {t : Ty} {E : Entry} :
    ¬ RhsT Γ F (.glob g (.arc (.cell t))) E Γ1 := fun h => by cases h.glob_sync

/-- An update of a `Locked` global (`locked_update g f`) is A3.2's `withLock`,
    unchanged, on the owner `h` of a clone of the global's share: a root that
    the body does not name, holding the share for the whole body. -/
theorem _root_.A2.StmtT.lockGlobal {P : Prog} {Γ Δ : Ctx} {F : List Var} {h x : Var} {g : Nat} {t : Ty}
    {s : Stmt} (hs : s.src = true) (hh : Γ h = none) (hhF : h ∉ F) (hx : Γ x = none) (hxF : x ∉ F)
    (hxh : x ≠ h) (htok : (Ty.lk t).ok = true) (hhs : h ∉ s.vars)
    (hb : StmtT P (setE (setE Γ h ⟨.lk t, .own, true, [], [], false, false⟩) x (lockE t)) F s Δ)
    (hend : EndOK Δ x) (hlive : ∃ E, Δ x = some E ∧ E.live = true) (hendh : EndOK (exitScope x Δ) h) :
    StmtT P Γ F (Stmt.lockGlobal h x g t s) (exitScope h (exitScope x Δ)) :=
  StmtT.letv hs hh hhF (RhsT.glob rfl htok)
    (StmtT.withLock hs (by simp [setE, upd_ne _ _ hxh, hx]) hxF (upd_same _ _ _) rfl (Or.inl rfl) hb hend
      rfl hhs hlive) hendh

/-- A read of a scalar global is an atomic load, A3.4's rule unchanged, on the
    owner `h` of a clone of its share. -/
theorem _root_.A2.StmtT.loadGlobal {P : Prog} {Γ Δ : Ctx} {F : List Var} {h x : Var} {g : Nat} {s : Stmt}
    (hs : s.src = true) (hh : Γ h = none) (hhF : h ∉ F) (hx : Γ x = none) (hxF : x ∉ F) (hxh : x ≠ h)
    (hb : StmtT P (setE (setE Γ h ⟨.lk .int, .own, true, [], [], false, false⟩) x intE) F s Δ)
    (hend : EndOK Δ x) (hendh : EndOK (exitScope x Δ) h) :
    StmtT P Γ F (Stmt.loadGlobal h x g s) (exitScope h (exitScope x Δ)) :=
  StmtT.letv hs hh hhF (RhsT.glob rfl rfl)
    (StmtT.letv hs (by simp [setE, upd_ne _ _ hxh, hx]) hxF
      (RhsT.atomic (upd_same _ _ _) rfl rfl ExprT.lit ExprT.lit) hb hend) hendh

/-- ... and a write an atomic store of an integer expression, which moves no
    owner: safe code hands a scalar global nothing to own (h273, h202). -/
theorem _root_.A2.StmtT.storeGlobal {P : Prog} {Γ Δ : Ctx} {F : List Var} {h x : Var} {g : Nat} {e : Expr}
    {s : Stmt} (hs : s.src = true) (hh : Γ h = none) (hhF : h ∉ F) (hx : Γ x = none) (hxF : x ∉ F)
    (hxh : x ≠ h) (he : ExprT (setE Γ h ⟨.lk .int, .own, true, [], [], false, false⟩) e)
    (hb : StmtT P (setE (setE Γ h ⟨.lk .int, .own, true, [], [], false, false⟩) x intE) F s Δ)
    (hend : EndOK Δ x) (hendh : EndOK (exitScope x Δ) h) :
    StmtT P Γ F (Stmt.storeGlobal h x g e s) (exitScope h (exitScope x Δ)) :=
  StmtT.letv hs hh hhF (RhsT.glob rfl rfl)
    (StmtT.letv hs (by simp [setE, upd_ne _ _ hxh, hx]) hxF
      (RhsT.atomic (upd_same _ _ _) rfl rfl he ExprT.lit) hb hend) hendh

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

/-- **A3.5, the crossing check** (`mem_send_check`, docs/MEMORY.md §6.5): a
    library handle whose copies are one state (a cell) may cross only with
    every other owner of that state.  For every cell a moved value holds a
    share of, no slot the spawner keeps holds one.  A lent cell share is no
    share (`lendOf`), so the slots that hold one are its owners: the check
    is the runtime's count of the places in the moved values that hold each
    cell's block against its owners.  (A cell share lies in no payload, by
    typing, so what the values hold is what they reach.) -/
def SendCheck (vs : List Val) (st' : Var → Option Slot) : Prop :=
  ∀ k, (∃ v ∈ vs, Sub (.cell k) v) → ∀ y o w, st' y = some ⟨o, some w⟩ → ¬ Sub (.cell k) w

/-- One step of the configuration. -/
inductive TStep (P : Prog) (spawn : Nat → Bool) : Cfg → Cfg → Prop
  /-- A thread takes one of A2's steps, unless its next step is a spawn;
      (A3.1) the configuration's sweep ends it, as A2's `Steps` ends every
      step with the store's. -/
  | thread {C : Cfg} {i : Nat} {t : Thread} {m' : Mem} {s' : Stmt} :
      C.ths[i]? = some t → ¬ SpawnRedex spawn t.s → Step P (C.view t) t.s (.ok m' s') →
      TStep P spawn C (C.put i m' s').sweep
  /-- A spawn: the arguments move to a new thread, which runs the body in
      its parameters' scopes and its result's (variable `n`, the number of
      parameters, as in the body's own numbering — so its end drops the
      result); the spawner's result is `0`. -/
  | spawn {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot} :
      C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true → P[f]? = some fn →
      t.st x = none → MoveArgs t.st args vs st' → SendCheck vs st' →
      TStep P spawn C
        { C with ths := C.ths.set i ⟨upd st' x (some ⟨false, some (.int 0)⟩), t.nv, K (.scope x k)⟩ ++
                        [⟨spawnSt fn vs, fn.nvars,
                          wrapParams fn.params 0 0 (.scope fn.params.length fn.body)⟩] }
  /-- A3.5: a spawn whose crossing check fails panics in the spawner, as
      `mem_send_check` calls `nurl_panic`: no thread is made and nothing
      moves, and the spawner's next step is A2's panic, which unwinds its
      scopes (or a `recover` frame catches it). -/
  | spawnFail {C : Cfg} {i : Nat} {t : Thread} {K : Stmt → Stmt} {x f : Nat} {args : List Var}
      {k : Stmt} {fn : Fn} {vs : List Val} {st' : Var → Option Slot} :
      C.ths[i]? = some t → Redex t.s K (.letcall x f args k) → spawn f = true → P[f]? = some fn →
      t.st x = none → MoveArgs t.st args vs st' → ¬ SendCheck vs st' →
      TStep P spawn C { C with ths := C.ths.set i ⟨t.st, t.nv, K (.seq .panic (.letcall x f args k))⟩ }

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
may touch beyond its rule is its own.  (A3.1) A read may be of a live
block's payload, which a node `NodeAt` / `DataAt` finds, a view or an
`arc_get` points into; no step writes one while its block exists
(`Step.blk`). -/

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
  /-- A3.1: `arc_get` reads the payload of the block its share names (every
      address of it: an over-approximation). -/
  | arcGet {a : Var} {o : Bool} {k : Nat} {p : Val} {bl : Blk} {i : Nat} :
      m.st a = some ⟨o, some (.arc k p)⟩ → m.blk k = some bl → i ∈ bl.rd.ids →
      RTouch m (.arcGet a) i false
  /-- A3.4: `chan_send` hands over the tree `y` owns: into the queue, or, on
      a closed channel, dropped, which writes it (every address of it, either
      way: an over-approximation).  The queue's ends, which a send or a
      receive changes, are the runtime mutex's, as a lock's word is: no
      address. -/
  | chanSend {a y : Var} {v : Val} {i : Nat} :
      m.st y = some ⟨true, some v⟩ → i ∈ v.ids → RTouch m (.chanSend a y) i true

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
  /-- A change of a `Vec`'s elements (#295) writes its node's cell and
      buffer, wherever the node lies in its owner's tree ... -/
  | editC {b : Bool} {x o : Var} {op : Edit} {T : Val} {t : Ty} {c d : Nat} {es : List Val} :
      NodeOf m x o T t c d es → Touch P m (.edit b x op) c true
  | editD {b : Bool} {x o : Var} {op : Edit} {T : Val} {t : Ty} {c d : Nat} {es : List Val} :
      NodeOf m x o T t c d es → Touch P m (.edit b x op) d true
  /-- ... a truncation frees the elements it drops ... -/
  | editFree {b : Bool} {x o : Var} {i : Expr} {n : Nat} {T : Val} {t : Ty} {c d : Nat}
      {es : List Val} {a : Nat} :
      NodeOf m x o T t c d es → Eval m i n → a ∈ idsL (es.drop n) →
      Touch P m (.edit b x (.trunc i)) a true
  /-- ... and reads what its length expression reads. -/
  | editI {b : Bool} {x : Var} {i : Expr} {a : Nat} : EReads m i a → Touch P m (.edit b x (.trunc i)) a false
  /-- An element set frees the element it replaces ... -/
  | editSetFree {b : Bool} {x o y : Var} {i : Expr} {n : Nat} {T : Val} {t : Ty} {c d : Nat}
      {es : List Val} {a : Nat} (h : n < es.length) :
      NodeOf m x o T t c d es → Eval m i n → a ∈ es[n].ids → Touch P m (.edit b x (.set i y)) a true
  /-- ... or, out of range, the value it is handed ... -/
  | editSetDrop {b : Bool} {x o y : Var} {i : Expr} {n : Nat} {T : Val} {t : Ty} {c d : Nat}
      {es : List Val} {v : Val} {a : Nat} :
      NodeOf m x o T t c d es → Eval m i n → es.length ≤ n → m.st y = some ⟨true, some v⟩ →
      a ∈ v.ids → Touch P m (.edit b x (.set i y)) a true
  /-- ... and reads what its index expression reads. -/
  | editSetI {b : Bool} {x y : Var} {i : Expr} {a : Nat} :
      EReads m i a → Touch P m (.edit b x (.set i y)) a false
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
  /-- A3.2: a lock scope: its body's step; its end drops what `x` owns, or
      gives it back to the block, which touches none of its addresses (an
      over-approximation: both are counted as writes of `x`'s tree); and so
      does a panic unwinding through it.  Taking a lock (`withLock`) and
      giving it back change only the lock's word, which the runtime's mutex
      changes atomically (the trusted base): no address. -/
  | scopeL {k : Nat} {t : Ty} {x : Var} {s : Stmt} {i : Nat} {w : Bool} :
      Touch P m s i w → Touch P m (.scopeL k t x s) i w
  | scopeLEnd {k : Nat} {t : Ty} {x : Var} {T : Val} {i : Nat} :
      m.st x = some ⟨true, some T⟩ → i ∈ T.ids → Touch P m (.scopeL k t x .skip) i true
  | scopeLUnwind {k : Nat} {t : Ty} {x : Var} {s : Stmt} {m1 : Mem} {T : Val} {i : Nat} :
      Step P m s (.panic m1) → m1.st x = some ⟨true, some T⟩ → i ∈ T.ids →
      Touch P m (.scopeL k t x s) i true

/-- A3.1: what the sweep that ends thread `i`'s next step frees: an address
    live before the step and after it, which the sweep frees — the payload
    of a block no thread reaches any more.  (A fresh address is no touch, as
    above.) -/
def SweepFrees (P : Prog) (C : Cfg) (i : Nat) (t : Thread) (a : Nat) : Prop :=
  ∃ m' s', Step P (C.view t) t.s (.ok m' s') ∧ C.alloc a = true ∧ m'.alloc a = true ∧
    (C.put i m' s').sweep.alloc a = false

/-- What thread `t` (the `i`-th) touches next in the configuration: what its
    rule touches, and (A3.1) what the sweep that ends its step frees, a
    write. -/
inductive CTouch (P : Prog) (C : Cfg) (i : Nat) (t : Thread) : Nat → Bool → Prop
  | step {a : Nat} {w : Bool} : Touch P (C.view t) t.s a w → CTouch P C i t a w
  | sweep {a : Nat} : SweepFrees P C i t a → CTouch P C i t a true

/-- Two threads whose next steps touch one address, one of them writing it.
    (A3.4's `Atomic` steps are atomic and are no race; so is a share's
    count, which is ghost here.) -/
def AddrRace (P : Prog) (C : Cfg) : Prop :=
  ∃ (i j : Nat) (ti tj : Thread) (a : Nat) (w : Bool), i ≠ j ∧ C.ths[i]? = some ti ∧
    C.ths[j]? = some tj ∧ CTouch P C i ti a true ∧ CTouch P C j tj a w

/-- A3.5: the keys of the lock scopes a statement is inside of (its spine's
    `scopeL` frames, innermost last). -/
def _root_.A2.Stmt.lkeys : Stmt → List Nat
  | .seq a _ => a.lkeys
  | .scope _ s => s.lkeys
  | .scopeD _ _ s => s.lkeys
  | .rbind _ s => s.lkeys
  | .frozen _ s => s.lkeys
  | .catchR _ _ s => s.lkeys
  | .scopeL k _ _ s => k :: s.lkeys
  | _ => []

/-- A3.5: thread `t`'s next step changes the state of cell `k` (a library
    handle's, which the library changes in place with no lock): it checks the
    state out through a share of it (`withCell`), or it runs inside a
    check-out of it, holding a share of it (the one the check-out is
    through, which `withLock`'s premises keep in its binding for the whole
    body).  Such a step writes the state wherever it is: the model checks it
    out as a lock's payload, so two threads at once would be serialized
    there, where the runtime's copies write one memory with no lock; so a
    step on a cell is not an address's touch, but a race of its own. -/
def CellOp (t : Thread) (k : Nat) : Prop :=
  (∃ K a x s o, Redex t.s K (.withLock a x s) ∧ t.st a = some ⟨o, some (.cell k)⟩) ∨
  (k ∈ t.s.lkeys ∧ ∃ y o v, t.st y = some ⟨o, some v⟩ ∧ Sub (.cell k) v)

/-- A3.5: two threads whose next steps change one cell's state. -/
def CellRace (C : Cfg) : Prop :=
  ∃ (i j : Nat) (ti tj : Thread) (k : Nat), i ≠ j ∧ C.ths[i]? = some ti ∧ C.ths[j]? = some tj ∧
    CellOp ti k ∧ CellOp tj k

/-- A race: two threads whose next steps touch one address, one of them
    writing it (`AddrRace`), or (A3.5) change one cell's state (`CellRace`). -/
def Race (P : Prog) (C : Cfg) : Prop := AddrRace P C ∨ CellRace C

/-! ### The claims -/

/-- No thread of a configuration reachable from `C0` is stuck: A2's
    `memory_safe`, on every thread. -/
def MemorySafe (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
  ∀ C, Reach P spawn C0 C → ∀ (i : Nat) (t : Thread), C.ths[i]? = some t →
    ¬ Stuck P (C.view t) t.s

/-- No configuration reachable from `C0` has a race. -/
def RaceFree (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
  ∀ C, Reach P spawn C0 C → ¬ Race P C

/-- When every thread has finished, nothing is allocated but (A3.6) what the
    module globals reach: A2's `no_leak_end`, over the threads.  Every live
    address is owned by the payload of a block a global reaches, which lives
    until the process exits, as the runtime's globals do.  With no global,
    nothing is allocated (`NoLeak.empty`). -/
def NoLeak (P : Prog) (spawn : Nat → Bool) (C0 : Cfg) : Prop :=
  ∀ C, Reach P spawn C0 C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = true →
    ∃ k bl, C.blk k = some bl ∧ i ∈ bl.tree.ids ∧ Reached C0.globVals C.blk k

/-- With no global (A3.0–A3.5's start), nothing is allocated once every
    thread has finished: no block is reached from no root. -/
theorem NoLeak.empty {P : Prog} {spawn : Nat → Bool} {s : Stmt} {nv : Nat}
    (h : NoLeak P spawn (Cfg.start Globs.empty s nv)) :
    ∀ C, Reach P spawn (Cfg.init s nv) C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false := by
  intro C hr hend i
  cases hi : C.alloc i with
  | false => rfl
  | true =>
    obtain ⟨k, -, -, -, hk⟩ := h C hr hend i hi
    exfalso
    induction hk with
    | root hv _ => obtain ⟨g, hg⟩ := hv; cases hg
    | pay _ _ _ ih => exact ih

/-- **A3.6, what a start-set global may be**, as the claim asks it of the
    start:
    - each global holds a share of a block that synchronises itself, at a
      type `Ty.sync` admits (`GlobFits`): a lock share (`Locked`, `RwLocked`,
      `Mutex`, `Atomic`, `Channel`) or an `Arc` of no library handle — never a
      `Vec` (h263), a cell share or any other owned tree;
    - the store the globals' `make`s left is one A2's invariant holds of with
      no binding (`MInv`: every block a well-formed tree of its type that owns
      its payload's addresses once; `Covers`: nothing else is allocated);
    - every block is reached from a global (the sweep that ended the last
      `make` left no other);
    - (A3.5b) every package a block holds (a Sync closure an `Arc` global
      keeps) names code of its signature, as A2's `MemCodes` says of the
      store a typed `make` leaves. -/
structure GlobsOK (P : Prog) (G : Globs) : Prop where
  sync  : ∀ g v, G.gl g = some v → ∃ t, t.sync = true ∧ t.ok = true ∧ GlobFits G.blk t v
  inv   : MInv (G.mem 0) (fun _ => none)
  cover : Covers (G.mem 0)
  reach : ∀ k bl, G.blk k = some bl → Reached (fun v => ∃ g, G.gl g = some v) G.blk k
  codes : BlkCodes P G.blk

/-- **The A3.0 claim**, for A2 plus `spawn`: a program A2 types, whose
    spawned functions take only view-free `sink` parameters, is memory-safe,
    race-free and leak-free on every interleaving.  Milestone A3.0 proves it,
    and A3.1 for A2 with `Arc` (shares of view-free payloads, collected by
    reachability); A3.2–A3.6 extend the language and restate it (A3.5: a
    spawn runs the crossing check, `SendCheck`, and a race includes two
    threads changing one library handle's state, `CellRace`; A3.6: the start
    holds the module globals, `GlobsOK`, and what they reach is left at the
    end). -/
def Claim : Prop :=
  ∀ (P : Prog) (spawn : Nat → Bool) (G : Globs) (s : Stmt) (Δ : Ctx) (nv : Nat),
    ProgOK P → ProgCodes P → SpawnOK P spawn → GlobsOK P G →
    StmtT P (fun _ => none) [] s Δ → s.src = true → s.codesOK P → (∀ v ∈ s.vars, v < nv) →
    MemorySafe P spawn (Cfg.start G s nv) ∧ RaceFree P spawn (Cfg.start G s nv) ∧
      NoLeak P spawn (Cfg.start G s nv)

/-- The view of the initial configuration is A2's empty store. -/
theorem init_view (s : Stmt) (nv : Nat) :
    (Cfg.init s nv).view ⟨fun _ => none, nv, s⟩ = emptyMem nv := rfl

end A3
